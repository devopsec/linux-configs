//! Secret Service client (org.freedesktop.Secret.*) over D-Bus: encrypted
//! session, search, prompt-aware unlock, secret retrieval, item creation,
//! deletion and property access.
//!
//! `ClientT` is generic over its transport so tests can drive it with an
//! in-memory fake service; `Client` uses a real `conn.Conn`. A transport
//! provides `call`, `addMatch`, `removeMatch`, `waitSignal` and `errorName`
//! with the signatures of `conn.Conn`.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const conn = @import("dbus/conn.zig");
const message = @import("dbus/message.zig");
const crypto = @import("crypto.zig");
const protocol = @import("protocol.zig");
const Value = message.Value;
const Message = message.Message;
const Attr = protocol.Attr;

pub const service_name = "org.freedesktop.secrets";
pub const service_path = "/org/freedesktop/secrets";
pub const default_collection = "/org/freedesktop/secrets/aliases/default";
pub const iface_service = "org.freedesktop.Secret.Service";
pub const iface_collection = "org.freedesktop.Secret.Collection";
pub const iface_item = "org.freedesktop.Secret.Item";
pub const iface_session = "org.freedesktop.Secret.Session";
pub const iface_prompt = "org.freedesktop.Secret.Prompt";
pub const iface_props = "org.freedesktop.DBus.Properties";
pub const content_type = "text/plain";
/// Set to `1` to negotiate an unencrypted `plain` session (tests only).
pub const plain_env = "SCM_AUTH_ALLOW_PLAIN_SESSION";
/// Object path meaning "no prompt needed".
const no_prompt = "/";

pub const Error = error{
    NoSessionBus,
    UnsupportedAddress,
    InvalidAddress,
    ConnectFailed,
    AuthRejected,
    /// Malformed or unexpected data from the bus or the service.
    BusProtocol,
    /// The service answered with an error reply; see `errorName`.
    RemoteError,
    Disconnected,
    ReadFailed,
    WriteFailed,
    InvalidValue,
    /// The user dismissed an unlock or confirmation prompt.
    PromptDismissed,
    BadCiphertext,
    InvalidPeerKey,
    EntropyUnavailable,
    OutOfMemory,
};

pub fn mapConn(err: conn.Error) Error {
    return switch (err) {
        error.Protocol => error.BusProtocol,
        inline else => |e| e,
    };
}

/// True when the environment opts into a `plain` session.
pub fn plainAllowed(environ: *const std.process.Environ.Map) bool {
    const v = environ.get(plain_env) orelse return false;
    return std.mem.eql(u8, v, "1");
}

/// Item paths returned by `SearchItems`.
pub const Found = struct {
    unlocked: []const []const u8,
    locked: []const []const u8,

    pub fn count(f: Found) usize {
        return f.unlocked.len + f.locked.len;
    }
};

/// Metadata of an item (never its secret).
pub const ItemInfo = struct {
    path: []const u8,
    label: []const u8,
    attrs: []const Attr,
    modified: u64,
    locked: bool,
};

const Transfer = union(enum) {
    plain,
    dh: crypto.Session,
};

pub const Options = struct {
    /// Negotiate `plain` instead of the DH algorithm (tests only).
    allow_plain: bool = false,
};

pub const Client = ClientT(conn.Conn);

pub fn ClientT(comptime Transport: type) type {
    return struct {
        const Self = @This();

        gpa: Allocator,
        io: Io,
        bus: *Transport,
        transfer: Transfer,
        session_path: []u8,
        owner_buf: [conn.max_name_len]u8,
        owner_len: usize,

        /// Opens a transfer session and records the service's unique name.
        /// `bus` must outlive the client.
        pub fn init(gpa: Allocator, io: Io, bus: *Transport, opts: Options) Error!Self {
            var self: Self = .{
                .gpa = gpa,
                .io = io,
                .bus = bus,
                .transfer = .plain,
                .session_path = &.{},
                .owner_buf = undefined,
                .owner_len = 0,
            };
            if (opts.allow_plain) {
                const empty: Value = .{ .string = "" };
                var reply = try self.call(service_path, iface_service, "OpenSession", "sv", &.{
                    .{ .string = "plain" },
                    .{ .variant = .{ .signature = "s", .value = &empty } },
                });
                defer reply.deinit(gpa);
                try expectSignature(&reply, "vo");
                self.session_path = try gpa.dupe(u8, reply.body[1].asString() orelse return error.BusProtocol);
            } else {
                var kp = try crypto.KeyPair.generate(io);
                defer kp.wipe();
                const pk: Value = .{ .bytes = &kp.public };
                var reply = try self.call(service_path, iface_service, "OpenSession", "sv", &.{
                    .{ .string = crypto.algorithm },
                    .{ .variant = .{ .signature = "ay", .value = &pk } },
                });
                defer reply.deinit(gpa);
                try expectSignature(&reply, "vo");
                const server_pk = reply.body[0].unwrap().asBytes() orelse return error.BusProtocol;
                const path = reply.body[1].asString() orelse return error.BusProtocol;
                var key = try kp.deriveKey(server_pk);
                defer std.crypto.secureZero(u8, &key);
                self.session_path = gpa.dupe(u8, path) catch |err| {
                    self.closeBorrowedSession(path);
                    return err;
                };
                self.transfer = .{ .dh = .{ .key = key } };
            }
            errdefer self.deinit();

            var name_reply = bus.call(.{
                .destination = conn.bus_name,
                .path = conn.bus_path,
                .interface = conn.bus_interface,
                .member = "GetNameOwner",
                .signature = "s",
                .body = &.{.{ .string = service_name }},
            }) catch |err| return mapConn(err);
            defer name_reply.deinit(gpa);
            try expectSignature(&name_reply, "s");
            const name = name_reply.body[0].string;
            if (name.len == 0 or name.len > self.owner_buf.len) return error.BusProtocol;
            @memcpy(self.owner_buf[0..name.len], name);
            self.owner_len = name.len;
            return self;
        }

        /// Best-effort close of a session path that is not yet owned by
        /// `self` (used when copying the path fails after OpenSession).
        fn closeBorrowedSession(self: *Self, path: []const u8) void {
            var reply = self.call(path, iface_session, "Close", "", &.{}) catch return;
            reply.deinit(self.gpa);
        }

        /// Closes the transfer session on the service. Called best effort
        /// by `deinit` if not done before.
        pub fn closeSession(self: *Self) Error!void {
            if (self.session_path.len == 0) return;
            const path = self.session_path;
            self.session_path = &.{};
            defer self.gpa.free(path);
            var reply = try self.call(path, iface_session, "Close", "", &.{});
            reply.deinit(self.gpa);
        }

        /// Closes the session (best effort) and wipes the transfer key.
        pub fn deinit(self: *Self) void {
            self.closeSession() catch {};
            switch (self.transfer) {
                .plain => {},
                .dh => |*s| s.wipe(),
            }
            self.* = undefined;
        }

        /// Unique bus name of the Secret Service.
        pub fn owner(self: *const Self) []const u8 {
            return self.owner_buf[0..self.owner_len];
        }

        /// D-Bus error name of the last `error.RemoteError`.
        pub fn errorName(self: *const Self) []const u8 {
            return self.bus.errorName();
        }

        fn call(self: *Self, path: []const u8, interface: []const u8, member: []const u8, signature: []const u8, body: []const Value) Error!Message {
            return self.bus.call(.{
                .destination = service_name,
                .path = path,
                .interface = interface,
                .member = member,
                .signature = signature,
                .body = body,
            }) catch |err| mapConn(err);
        }

        /// Items whose attributes include all of `attrs`. Paths are
        /// allocated with `out`.
        pub fn search(self: *Self, out: Allocator, attrs: []const Attr) Error!Found {
            var arena: std.heap.ArenaAllocator = .init(self.gpa);
            defer arena.deinit();
            const dict = try attrDict(arena.allocator(), attrs);
            var reply = try self.call(service_path, iface_service, "SearchItems", "a{ss}", &.{dict});
            defer reply.deinit(self.gpa);
            try expectSignature(&reply, "aoao");
            return .{
                .unlocked = try dupePaths(out, reply.body[0]),
                .locked = try dupePaths(out, reply.body[1]),
            };
        }

        /// Unlocks `items`, running the service's prompt if it asks for one.
        pub fn unlock(self: *Self, items: []const []const u8) Error!void {
            if (items.len == 0) return;
            var arena: std.heap.ArenaAllocator = .init(self.gpa);
            defer arena.deinit();
            const paths = try pathArray(arena.allocator(), items);
            var reply = try self.call(service_path, iface_service, "Unlock", "ao", &.{paths});
            defer reply.deinit(self.gpa);
            try expectSignature(&reply, "aoo");
            const prompt_path = reply.body[1].asString() orelse return error.BusProtocol;
            if (std.mem.eql(u8, prompt_path, no_prompt)) return;
            var done = try self.prompt(prompt_path);
            done.deinit(self.gpa);
        }

        /// Runs a prompt and returns its `Completed` signal (caller deinits).
        /// The signal must come from the service's unique name; forged
        /// signals from other peers are ignored. Waits without a timeout.
        fn prompt(self: *Self, path: []const u8) Error!Message {
            const rule: conn.MatchRule = .{
                .sender = self.owner(),
                .path = path,
                .interface = iface_prompt,
                .member = "Completed",
            };
            self.bus.addMatch(rule) catch |err| return mapConn(err);
            defer self.bus.removeMatch(rule) catch {};
            var started = try self.call(path, iface_prompt, "Prompt", "s", &.{.{ .string = "" }});
            started.deinit(self.gpa);
            while (true) {
                var sig = self.bus.waitSignal(rule) catch |err| return mapConn(err);
                const sender = sig.header.sender orelse "";
                if (!std.mem.eql(u8, sender, self.owner())) {
                    sig.deinit(self.gpa);
                    continue;
                }
                errdefer sig.deinit(self.gpa);
                try expectSignature(&sig, "bv");
                const dismissed = sig.body[0].asBool() orelse return error.BusProtocol;
                if (dismissed) return error.PromptDismissed;
                return sig;
            }
        }

        /// The plaintext secret of an unlocked item. Caller wipes and frees
        /// it with the client's allocator (`protocol.wipeFree`).
        pub fn getSecret(self: *Self, item: []const u8) Error![]u8 {
            var reply = try self.call(item, iface_item, "GetSecret", "o", &.{.{ .object_path = self.session_path }});
            defer reply.deinit(self.gpa);
            try expectSignature(&reply, "(oayays)");
            const s = reply.body[0].asStruct() orelse return error.BusProtocol;
            const params = s[1].asBytes() orelse return error.BusProtocol;
            const value = s[2].asBytes() orelse return error.BusProtocol;
            return switch (self.transfer) {
                .plain => self.gpa.dupe(u8, value),
                .dh => |*session| session.decrypt(self.gpa, params, value),
            };
        }

        /// Creates an item in the default collection, replacing one whose
        /// attributes are all equal. Returns the item path (allocated with
        /// `out`).
        pub fn create(self: *Self, out: Allocator, label: []const u8, attrs: []const Attr, secret: []const u8) Error![]const u8 {
            var arena: std.heap.ArenaAllocator = .init(self.gpa);
            defer arena.deinit();
            var enc: ?crypto.Encrypted = null;
            defer if (enc) |*e| e.deinit(self.gpa);
            var params: []const u8 = "";
            var value: []const u8 = secret;
            switch (self.transfer) {
                .plain => {},
                .dh => |*session| {
                    enc = try session.encrypt(self.gpa, self.io, secret);
                    params = &enc.?.iv;
                    value = enc.?.ciphertext;
                },
            }
            const label_v: Value = .{ .string = label };
            const attrs_v = try attrDict(arena.allocator(), attrs);
            const label_pair = [2]Value{
                .{ .string = iface_item ++ ".Label" },
                .{ .variant = .{ .signature = "s", .value = &label_v } },
            };
            const attrs_pair = [2]Value{
                .{ .string = iface_item ++ ".Attributes" },
                .{ .variant = .{ .signature = "a{ss}", .value = &attrs_v } },
            };
            const prop_items = [_]Value{ .{ .dict_entry = &label_pair }, .{ .dict_entry = &attrs_pair } };
            const props: Value = .{ .array = .{ .signature = "{sv}", .items = &prop_items } };
            const fields = [_]Value{
                .{ .object_path = self.session_path },
                .{ .bytes = params },
                .{ .bytes = value },
                .{ .string = content_type },
            };
            var reply = try self.call(default_collection, iface_collection, "CreateItem", "a{sv}(oayays)b", &.{
                props,
                .{ .structure = &fields },
                .{ .boolean = true },
            });
            defer reply.deinit(self.gpa);
            try expectSignature(&reply, "oo");
            const item = reply.body[0].asString() orelse return error.BusProtocol;
            const prompt_path = reply.body[1].asString() orelse return error.BusProtocol;
            if (std.mem.eql(u8, prompt_path, no_prompt)) return out.dupe(u8, item);
            var done = try self.prompt(prompt_path);
            defer done.deinit(self.gpa);
            const created = done.body[1].unwrap().asString() orelse return error.BusProtocol;
            if (!message.validObjectPath(created) or std.mem.eql(u8, created, no_prompt)) return error.BusProtocol;
            return out.dupe(u8, created);
        }

        /// Deletes an item (prompt aware).
        pub fn delete(self: *Self, item: []const u8) Error!void {
            var reply = try self.call(item, iface_item, "Delete", "", &.{});
            defer reply.deinit(self.gpa);
            try expectSignature(&reply, "o");
            const prompt_path = reply.body[0].asString() orelse return error.BusProtocol;
            if (std.mem.eql(u8, prompt_path, no_prompt)) return;
            var done = try self.prompt(prompt_path);
            done.deinit(self.gpa);
        }

        /// Label, attributes, modification time and lock state of an item.
        /// Strings are allocated with `out`.
        pub fn info(self: *Self, out: Allocator, item: []const u8) Error!ItemInfo {
            var reply = try self.call(item, iface_props, "GetAll", "s", &.{.{ .string = iface_item }});
            defer reply.deinit(self.gpa);
            try expectSignature(&reply, "a{sv}");
            const props = reply.body[0];
            const label = (props.dictGet("Label") orelse return error.BusProtocol).unwrap().asString() orelse
                return error.BusProtocol;
            const attrs = (props.dictGet("Attributes") orelse return error.BusProtocol).unwrap();
            const modified = (props.dictGet("Modified") orelse return error.BusProtocol).unwrap().asU64() orelse
                return error.BusProtocol;
            const locked = if (props.dictGet("Locked")) |v| v.unwrap().asBool() orelse false else false;
            return .{
                .path = try out.dupe(u8, item),
                .label = try out.dupe(u8, label),
                .attrs = try dupeAttrs(out, attrs),
                .modified = modified,
                .locked = locked,
            };
        }

        /// Replaces an unlocked item's attributes and label.
        pub fn setLabelAndAttrs(self: *Self, item: []const u8, label: []const u8, attrs: []const Attr) Error!void {
            var arena: std.heap.ArenaAllocator = .init(self.gpa);
            defer arena.deinit();
            const attrs_v = try attrDict(arena.allocator(), attrs);
            try self.setProperty(item, "Attributes", "a{ss}", &attrs_v);
            const label_v: Value = .{ .string = label };
            try self.setProperty(item, "Label", "s", &label_v);
        }

        fn setProperty(self: *Self, item: []const u8, name: []const u8, signature: []const u8, v: *const Value) Error!void {
            var reply = try self.call(item, iface_props, "Set", "ssv", &.{
                .{ .string = iface_item },
                .{ .string = name },
                .{ .variant = .{ .signature = signature, .value = v } },
            });
            reply.deinit(self.gpa);
        }
    };
}

fn expectSignature(m: *const Message, signature: []const u8) Error!void {
    if (!std.mem.eql(u8, m.header.signature, signature)) return error.BusProtocol;
}

/// `a{ss}` value for `attrs`; storage comes from `arena`.
pub fn attrDict(arena: Allocator, attrs: []const Attr) Allocator.Error!Value {
    const pairs = try arena.alloc([2]Value, attrs.len);
    const items = try arena.alloc(Value, attrs.len);
    for (attrs, pairs, items) |a, *pair, *item| {
        pair.* = .{ .{ .string = a.key }, .{ .string = a.value } };
        item.* = .{ .dict_entry = pair };
    }
    return .{ .array = .{ .signature = "{ss}", .items = items } };
}

/// `ao` value for `paths`; storage comes from `arena`.
pub fn pathArray(arena: Allocator, paths: []const []const u8) Allocator.Error!Value {
    const items = try arena.alloc(Value, paths.len);
    for (paths, items) |p, *item| item.* = .{ .object_path = p };
    return .{ .array = .{ .signature = "o", .items = items } };
}

fn dupePaths(out: Allocator, v: Value) Error![]const []const u8 {
    const items = v.asArray() orelse return error.BusProtocol;
    const paths = try out.alloc([]const u8, items.len);
    for (items, paths) |item, *p| {
        if (item != .object_path) return error.BusProtocol;
        p.* = try out.dupe(u8, item.object_path);
    }
    return paths;
}

/// Copies an `a{ss}` value into an attribute list allocated with `out`.
pub fn dupeAttrs(out: Allocator, v: Value) Error![]const Attr {
    const items = v.asArray() orelse return error.BusProtocol;
    const attrs = try out.alloc(Attr, items.len);
    for (items, attrs) |item, *a| {
        if (item != .dict_entry) return error.BusProtocol;
        const k = item.dict_entry[0].asString() orelse return error.BusProtocol;
        const val = item.dict_entry[1].asString() orelse return error.BusProtocol;
        a.* = .{ .key = try out.dupe(u8, k), .value = try out.dupe(u8, val) };
    }
    return attrs;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const FakeBus = @import("fake_bus.zig").FakeBus;
const TestClient = ClientT(FakeBus);

fn testAttrs(host: []const u8) [4]Attr {
    return .{
        .{ .key = "xdg:schema", .value = protocol.schema_name },
        .{ .key = "protocol", .value = "https" },
        .{ .key = "server", .value = host },
        .{ .key = "application", .value = "scm-auth" },
    };
}

test "DH session: create, search, info, get secret, set, delete" {
    const gpa = testing.allocator;
    var fake: FakeBus = .init(gpa);
    defer fake.deinit();
    var c = try TestClient.init(gpa, testing.io, &fake, .{});
    defer c.deinit();
    try testing.expectEqualStrings(fake.owner, c.owner());
    try testing.expect(c.transfer == .dh);

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const attrs = testAttrs("example.test");
    const path = try c.create(a, "scm-auth: https://example.test/", &attrs, "s3cret\npassword_expiry_utc=5");
    try testing.expectEqual(1, fake.items.items.len);
    try testing.expectEqualStrings("s3cret\npassword_expiry_utc=5", fake.items.items[0].secret);

    // Replace keeps a single item.
    const again = try c.create(a, "scm-auth: https://example.test/", &attrs, "new");
    try testing.expectEqualStrings(path, again);
    try testing.expectEqual(1, fake.items.items.len);

    const found = try c.search(a, &.{.{ .key = "server", .value = "example.test" }});
    try testing.expectEqual(1, found.unlocked.len);
    try testing.expectEqual(0, found.locked.len);
    const none = try c.search(a, &.{.{ .key = "server", .value = "other.test" }});
    try testing.expectEqual(0, none.count());

    const item = try c.info(a, path);
    try testing.expectEqualStrings("scm-auth: https://example.test/", item.label);
    try testing.expectEqualStrings("scm-auth", protocol.findAttr(item.attrs, "application").?);
    try testing.expect(item.modified > 0);

    const secret = try c.getSecret(path);
    defer protocol.wipeFree(gpa, secret);
    try testing.expectEqualStrings("new", secret);

    const new_attrs = [_]Attr{ attrs[0], attrs[1], attrs[2], .{ .key = "tool", .value = "forge" } };
    try c.setLabelAndAttrs(path, "relabelled", &new_attrs);
    try testing.expectEqualStrings("relabelled", fake.items.items[0].label);
    try testing.expectEqualStrings("forge", protocol.findAttr(fake.items.items[0].attrs.items, "tool").?);

    try c.delete(path);
    try testing.expectEqual(0, fake.items.items.len);
}

test "plain session only when asked" {
    const gpa = testing.allocator;
    var fake: FakeBus = .init(gpa);
    defer fake.deinit();
    var c = try TestClient.init(gpa, testing.io, &fake, .{ .allow_plain = true });
    defer c.deinit();
    try testing.expect(c.transfer == .plain);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const attrs = testAttrs("h");
    const path = try c.create(arena.allocator(), "l", &attrs, "pw");
    const secret = try c.getSecret(path);
    defer protocol.wipeFree(gpa, secret);
    try testing.expectEqualStrings("pw", secret);

    var env: std.process.Environ.Map = .init(gpa);
    defer env.deinit();
    try testing.expect(!plainAllowed(&env));
    try env.put(plain_env, "yes");
    try testing.expect(!plainAllowed(&env));
    try env.put(plain_env, "1");
    try testing.expect(plainAllowed(&env));
}

test "unlock with prompt, forged signal ignored, dismissal" {
    const gpa = testing.allocator;
    var fake: FakeBus = .init(gpa);
    defer fake.deinit();
    var c = try TestClient.init(gpa, testing.io, &fake, .{});
    defer c.deinit();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const attrs = testAttrs("h");
    const path = try c.create(a, "l", &attrs, "pw");
    fake.items.items[0].locked = true;

    const found = try c.search(a, &.{.{ .key = "server", .value = "h" }});
    try testing.expectEqual(1, found.locked.len);
    try testing.expect((try c.info(a, path)).locked);
    try testing.expectError(error.RemoteError, c.getSecret(path));
    try testing.expectEqualStrings("org.freedesktop.Secret.Error.IsLocked", c.errorName());

    fake.prompt_mode = .dismiss;
    try testing.expectError(error.PromptDismissed, c.unlock(found.locked));
    try testing.expect(fake.items.items[0].locked);

    fake.prompt_mode = .forged_then_complete;
    try c.unlock(found.locked);
    try testing.expect(!fake.items.items[0].locked);
    try testing.expectEqual(0, fake.rules.items.len);

    fake.items.items[0].locked = true;
    fake.prompt_mode = .none;
    try c.unlock(found.locked);
    try testing.expect(!fake.items.items[0].locked);
    try c.unlock(&.{});
}

test "create through a prompt returns the prompted item path" {
    const gpa = testing.allocator;
    var fake: FakeBus = .init(gpa);
    defer fake.deinit();
    var c = try TestClient.init(gpa, testing.io, &fake, .{});
    defer c.deinit();
    fake.prompt_mode = .complete;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const attrs = testAttrs("h");
    const path = try c.create(arena.allocator(), "l", &attrs, "pw");
    try testing.expectEqualStrings(fake.items.items[0].path, path);
    try c.delete(path);
    try testing.expectEqual(0, fake.items.items.len);

    fake.prompt_mode = .dismiss;
    try testing.expectError(error.PromptDismissed, c.create(arena.allocator(), "l", &attrs, "pw"));
    try testing.expectEqual(0, fake.items.items.len);
}

test "malformed service replies are protocol errors" {
    const gpa = testing.allocator;
    var fake: FakeBus = .init(gpa);
    defer fake.deinit();
    fake.bad_open_session = true;
    try testing.expectError(error.BusProtocol, TestClient.init(gpa, testing.io, &fake, .{}));
    fake.bad_open_session = false;
    fake.bad_server_key = true;
    try testing.expectError(error.InvalidPeerKey, TestClient.init(gpa, testing.io, &fake, .{}));
}

test "client survives every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(gpa: Allocator) !void {
            var fake: FakeBus = .init(testing.allocator);
            defer fake.deinit();
            fake.msg_gpa = gpa;
            var c = try TestClient.init(gpa, testing.io, &fake, .{ .allow_plain = true });
            defer c.deinit();
            var arena: std.heap.ArenaAllocator = .init(gpa);
            defer arena.deinit();
            const attrs = testAttrs("h");
            const path = try c.create(arena.allocator(), "l", &attrs, "pw");
            _ = try c.search(arena.allocator(), &attrs);
            _ = try c.info(arena.allocator(), path);
            const s = try c.getSecret(path);
            protocol.wipeFree(gpa, s);
            try c.delete(path);
            try c.closeSession();
        }
    }.run, .{});
}
