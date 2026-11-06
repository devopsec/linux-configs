//! In-memory Secret Service for unit tests: implements the transport
//! interface of `conn.Conn` (`call`, `addMatch`, `removeMatch`,
//! `waitSignal`, `errorName`). Requests and replies go through the real
//! marshaller, so signatures are checked on both sides. Test-only.

const std = @import("std");
const Allocator = std.mem.Allocator;
const conn = @import("dbus/conn.zig");
const message = @import("dbus/message.zig");
const crypto = @import("crypto.zig");
const protocol = @import("protocol.zig");
const Value = message.Value;
const Message = message.Message;
const Attr = protocol.Attr;

pub const Item = struct {
    path: []u8,
    label: []u8,
    attrs: std.ArrayList(Attr),
    secret: []u8,
    modified: u64,
    locked: bool = false,

    fn free(item: *Item, gpa: Allocator) void {
        gpa.free(item.path);
        gpa.free(item.label);
        freeAttrs(gpa, &item.attrs);
        protocol.wipeFree(gpa, item.secret);
    }
};

fn freeAttrs(gpa: Allocator, attrs: *std.ArrayList(Attr)) void {
    for (attrs.items) |a| {
        gpa.free(a.key);
        gpa.free(a.value);
    }
    attrs.deinit(gpa);
}

pub const PromptMode = enum { none, complete, dismiss, forged_then_complete };

const Pending = union(enum) {
    unlock: std.ArrayList([]u8),
    create: Item,
};

const Signal = struct {
    path: []u8,
    sender: []const u8,
    dismissed: bool,
    /// Created item path for create prompts; null for unlock prompts.
    result: ?[]u8,
};

pub const FakeBus = struct {
    /// Allocator for the fake's own state.
    gpa: Allocator,
    /// Allocator for messages handed to the client (the client's gpa).
    msg_gpa: Allocator,
    owner: []const u8 = ":1.7",
    items: std.ArrayList(Item) = .empty,
    rules: std.ArrayList([]u8) = .empty,
    signals: std.ArrayList(Signal) = .empty,
    pending: ?Pending = null,
    pending_path: [64]u8 = undefined,
    pending_path_len: usize = 0,
    next_id: u32 = 1,
    clock: u64 = 1000,
    session: ?crypto.Session = null,
    prompt_mode: PromptMode = .none,
    bad_open_session: bool = false,
    bad_server_key: bool = false,
    /// Number of Delete calls served.
    deletes: usize = 0,
    error_name: []const u8 = "",

    pub fn init(gpa: Allocator) FakeBus {
        return .{ .gpa = gpa, .msg_gpa = gpa };
    }

    pub fn deinit(f: *FakeBus) void {
        for (f.items.items) |*item| item.free(f.gpa);
        f.items.deinit(f.gpa);
        for (f.rules.items) |r| f.gpa.free(r);
        f.rules.deinit(f.gpa);
        for (f.signals.items) |s| f.freeSignal(s);
        f.signals.deinit(f.gpa);
        f.dropPending();
        if (f.session) |*s| s.wipe();
        f.* = undefined;
    }

    fn freeSignal(f: *FakeBus, s: Signal) void {
        f.gpa.free(s.path);
        if (s.result) |r| f.gpa.free(r);
    }

    fn dropPending(f: *FakeBus) void {
        const p = f.pending orelse return;
        switch (p) {
            .unlock => |list| {
                var l = list;
                for (l.items) |s| f.gpa.free(s);
                l.deinit(f.gpa);
            },
            .create => |item| {
                var it = item;
                it.free(f.gpa);
            },
        }
        f.pending = null;
    }

    /// Seeds an item (test setup). Returns its path (owned by the fake).
    pub fn addItem(f: *FakeBus, label: []const u8, attrs: []const Attr, secret: []const u8, modified: u64, locked: bool) ![]const u8 {
        var item = try f.newItem(label, attrs, secret);
        item.modified = modified;
        item.locked = locked;
        errdefer item.free(f.gpa);
        try f.items.append(f.gpa, item);
        return item.path;
    }

    pub fn find(f: *FakeBus, path: []const u8) ?*Item {
        for (f.items.items) |*item| if (std.mem.eql(u8, item.path, path)) return item;
        return null;
    }

    fn newItem(f: *FakeBus, label: []const u8, attrs: []const Attr, secret: []const u8) !Item {
        const path = try std.fmt.allocPrint(f.gpa, "/org/freedesktop/secrets/collection/login/{d}", .{f.next_id});
        errdefer f.gpa.free(path);
        f.next_id += 1;
        const l = try f.gpa.dupe(u8, label);
        errdefer f.gpa.free(l);
        var list = try f.dupeAttrList(attrs);
        errdefer freeAttrs(f.gpa, &list);
        const s = try f.gpa.dupe(u8, secret);
        f.clock += 1;
        return .{ .path = path, .label = l, .attrs = list, .secret = s, .modified = f.clock };
    }

    fn dupeAttrList(f: *FakeBus, attrs: []const Attr) !std.ArrayList(Attr) {
        var list: std.ArrayList(Attr) = .empty;
        errdefer freeAttrs(f.gpa, &list);
        try list.ensureTotalCapacity(f.gpa, attrs.len);
        for (attrs) |a| {
            const k = try f.gpa.dupe(u8, a.key);
            const v = f.gpa.dupe(u8, a.value) catch |err| {
                f.gpa.free(k);
                return err;
            };
            list.appendAssumeCapacity(.{ .key = k, .value = v });
        }
        return list;
    }

    pub fn errorName(f: *const FakeBus) []const u8 {
        return f.error_name;
    }

    pub fn addMatch(f: *FakeBus, rule: conn.MatchRule) conn.Error!void {
        const p = try f.gpa.dupe(u8, rule.path orelse "");
        errdefer f.gpa.free(p);
        try f.rules.append(f.gpa, p);
    }

    pub fn removeMatch(f: *FakeBus, rule: conn.MatchRule) conn.Error!void {
        for (f.rules.items, 0..) |r, i| {
            if (std.mem.eql(u8, r, rule.path orelse "")) {
                f.gpa.free(f.rules.orderedRemove(i));
                return;
            }
        }
    }

    pub fn waitSignal(f: *FakeBus, rule: conn.MatchRule) conn.Error!Message {
        for (f.signals.items, 0..) |s, i| {
            if (!std.mem.eql(u8, s.path, rule.path orelse s.path)) continue;
            const sig = f.signals.orderedRemove(i);
            defer f.freeSignal(sig);
            var arena: std.heap.ArenaAllocator = .init(f.gpa);
            defer arena.deinit();
            const result: Value = if (sig.result) |r|
                .{ .object_path = r }
            else
                .{ .array = .{ .signature = "o", .items = &.{} } };
            const sig_text: []const u8 = if (sig.result != null) "o" else "ao";
            const res_ptr = try arena.allocator().create(Value);
            res_ptr.* = result;
            return f.build(.{
                .type = .signal,
                .serial = f.nextSerial(),
                .path = sig.path,
                .interface = "org.freedesktop.Secret.Prompt",
                .member = "Completed",
                .sender = sig.sender,
                .signature = "bv",
            }, &.{ .{ .boolean = sig.dismissed }, .{ .variant = .{ .signature = sig_text, .value = res_ptr } } });
        }
        return error.Disconnected;
    }

    fn nextSerial(f: *FakeBus) u32 {
        f.next_id += 1;
        return f.next_id;
    }

    fn build(f: *FakeBus, h: message.Header, body: []const Value) conn.Error!Message {
        const raw = message.encodeMessage(f.msg_gpa, h, body) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.InvalidValue,
        };
        return message.parse(f.msg_gpa, raw);
    }

    fn reply(f: *FakeBus, signature: []const u8, body: []const Value) conn.Error!Message {
        return f.build(.{
            .type = .method_return,
            .serial = f.nextSerial(),
            .reply_serial = 1,
            .sender = f.owner,
            .signature = signature,
        }, body);
    }

    fn fail(f: *FakeBus, name: []const u8) conn.Error {
        f.error_name = name;
        return error.RemoteError;
    }

    pub fn call(f: *FakeBus, args: conn.Call) conn.Error!Message {
        // Round-trip the request through the marshaller.
        const raw = message.encodeMessage(f.gpa, .{
            .type = .method_call,
            .serial = 1,
            .path = args.path,
            .interface = args.interface,
            .member = args.member,
            .destination = args.destination,
            .signature = args.signature,
        }, args.body) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => error.InvalidValue,
        };
        var req = try message.parse(f.gpa, raw);
        defer req.deinit(f.gpa);
        var arena: std.heap.ArenaAllocator = .init(f.gpa);
        defer arena.deinit();
        return f.dispatch(arena.allocator(), args.member, args.path, req.body) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.RemoteError => error.RemoteError,
            error.Disconnected => error.Disconnected,
            error.InvalidValue => error.InvalidValue,
            error.Protocol => error.Protocol,
            else => error.Protocol,
        };
    }

    fn dispatch(f: *FakeBus, a: Allocator, member: []const u8, path: []const u8, body: []const Value) anyerror!Message {
        const M = enum { GetNameOwner, OpenSession, SearchItems, Unlock, Prompt, GetSecret, CreateItem, Delete, GetAll, Set, Close };
        const m = std.meta.stringToEnum(M, member) orelse return f.fail("org.freedesktop.DBus.Error.UnknownMethod");
        switch (m) {
            .GetNameOwner => return f.reply("s", &.{.{ .string = f.owner }}),
            .Close => return f.reply("", &.{}),
            .OpenSession => {
                const session_path: Value = .{ .object_path = "/org/freedesktop/secrets/session/s1" };
                if (f.bad_open_session) return f.reply("s", &.{.{ .string = "x" }});
                if (std.mem.eql(u8, body[0].string, "plain")) {
                    f.session = null;
                    const out = try a.create(Value);
                    out.* = .{ .string = "" };
                    return f.reply("vo", &.{ .{ .variant = .{ .signature = "s", .value = out } }, session_path });
                }
                var kp = try crypto.KeyPair.generate(std.testing.io);
                defer kp.wipe();
                const client_pk = body[1].unwrap().asBytes() orelse return error.Protocol;
                f.session = .{ .key = try kp.deriveKey(client_pk) };
                const out = try a.create(Value);
                out.* = .{ .bytes = if (f.bad_server_key) &.{1} else try a.dupe(u8, &kp.public) };
                return f.reply("vo", &.{ .{ .variant = .{ .signature = "ay", .value = out } }, session_path });
            },
            .SearchItems => {
                var unlocked: std.ArrayList(Value) = .empty;
                var locked: std.ArrayList(Value) = .empty;
                const want = body[0].asArray().?;
                for (f.items.items) |*item| {
                    const matches = for (want) |e| {
                        const v = protocol.findAttr(item.attrs.items, e.dict_entry[0].string) orelse break false;
                        if (!std.mem.eql(u8, v, e.dict_entry[1].string)) break false;
                    } else true;
                    if (!matches) continue;
                    try (if (item.locked) &locked else &unlocked).append(a, .{ .object_path = item.path });
                }
                return f.reply("aoao", &.{
                    .{ .array = .{ .signature = "o", .items = unlocked.items } },
                    .{ .array = .{ .signature = "o", .items = locked.items } },
                });
            },
            .Unlock => {
                const paths = body[0].asArray().?;
                if (f.prompt_mode == .none) {
                    for (paths) |p| if (f.find(p.object_path)) |item| {
                        item.locked = false;
                    };
                    return f.reply("aoo", &.{ body[0], .{ .object_path = "/" } });
                }
                f.dropPending();
                var list: std.ArrayList([]u8) = .empty;
                errdefer {
                    for (list.items) |s| f.gpa.free(s);
                    list.deinit(f.gpa);
                }
                for (paths) |p| {
                    const s = try f.gpa.dupe(u8, p.object_path);
                    list.append(f.gpa, s) catch |err| {
                        f.gpa.free(s);
                        return err;
                    };
                }
                f.pending = .{ .unlock = list };
                return f.reply("aoo", &.{ .{ .array = .{ .signature = "o", .items = &.{} } }, .{ .object_path = f.newPromptPath() } });
            },
            .Prompt => {
                if (f.pending == null or !std.mem.eql(u8, path, f.pending_path[0..f.pending_path_len]))
                    return f.fail("org.freedesktop.Secret.Error.NoSuchObject");
                switch (f.prompt_mode) {
                    .none => unreachable, // prompts only exist in the other modes
                    .dismiss => {
                        f.dropPending();
                        try f.queueSignal(path, f.owner, true, null);
                    },
                    .complete, .forged_then_complete => {
                        if (f.prompt_mode == .forged_then_complete) try f.queueSignal(path, ":1.99", false, null);
                        var result: ?[]const u8 = null;
                        switch (f.pending.?) {
                            .unlock => |list| for (list.items) |p| if (f.find(p)) |item| {
                                item.locked = false;
                            },
                            .create => |item| {
                                try f.items.append(f.gpa, item);
                                result = item.path;
                                f.pending = null;
                            },
                        }
                        try f.queueSignal(path, f.owner, false, result);
                        f.dropPending();
                    },
                }
                return f.reply("", &.{});
            },
            .GetSecret => {
                const item = f.find(path) orelse return f.fail("org.freedesktop.Secret.Error.NoSuchObject");
                if (item.locked) return f.fail("org.freedesktop.Secret.Error.IsLocked");
                var iv: []const u8 = "";
                var value: []const u8 = item.secret;
                if (f.session) |*s| {
                    const enc = try s.encrypt(a, std.testing.io, item.secret);
                    iv = try a.dupe(u8, &enc.iv);
                    value = enc.ciphertext;
                }
                const fields = [_]Value{ body[0], .{ .bytes = iv }, .{ .bytes = value }, .{ .string = "text/plain" } };
                return f.reply("(oayays)", &.{.{ .structure = &fields }});
            },
            .CreateItem => {
                const props = body[0];
                const label = props.dictGet("org.freedesktop.Secret.Item.Label").?.unwrap().string;
                const attrs_v = props.dictGet("org.freedesktop.Secret.Item.Attributes").?.unwrap();
                const attrs = try @import("secret.zig").dupeAttrs(a, attrs_v);
                const s = body[1].structure;
                const plain = if (f.session) |*sess|
                    try sess.decrypt(a, s[1].bytes, s[2].bytes)
                else
                    try a.dupe(u8, s[2].bytes);
                const replace = body[2].boolean;
                if (replace) for (f.items.items) |*item| {
                    if (!sameAttrs(item.attrs.items, attrs)) continue;
                    const new_secret = try f.gpa.dupe(u8, plain);
                    protocol.wipeFree(f.gpa, item.secret);
                    item.secret = new_secret;
                    const new_label = try f.gpa.dupe(u8, label);
                    f.gpa.free(item.label);
                    item.label = new_label;
                    f.clock += 1;
                    item.modified = f.clock;
                    return f.reply("oo", &.{ .{ .object_path = item.path }, .{ .object_path = "/" } });
                };
                var item = try f.newItem(label, attrs, plain);
                if (f.prompt_mode != .none) {
                    f.dropPending();
                    f.pending = .{ .create = item };
                    return f.reply("oo", &.{ .{ .object_path = "/" }, .{ .object_path = f.newPromptPath() } });
                }
                f.items.append(f.gpa, item) catch |err| {
                    item.free(f.gpa);
                    return err;
                };
                return f.reply("oo", &.{ .{ .object_path = item.path }, .{ .object_path = "/" } });
            },
            .Delete => {
                for (f.items.items, 0..) |*item, i| {
                    if (!std.mem.eql(u8, item.path, path)) continue;
                    if (item.locked) return f.fail("org.freedesktop.Secret.Error.IsLocked");
                    var removed = f.items.orderedRemove(i);
                    removed.free(f.gpa);
                    f.deletes += 1;
                    return f.reply("o", &.{.{ .object_path = "/" }});
                }
                return f.fail("org.freedesktop.Secret.Error.NoSuchObject");
            },
            .GetAll => {
                const item = f.find(path) orelse return f.fail("org.freedesktop.Secret.Error.NoSuchObject");
                const vals = try a.alloc(Value, 4);
                vals[0] = .{ .string = item.label };
                vals[1] = try @import("secret.zig").attrDict(a, item.attrs.items);
                vals[2] = .{ .uint64 = item.modified };
                vals[3] = .{ .boolean = item.locked };
                const names = [_][]const u8{ "Label", "Attributes", "Modified", "Locked" };
                const sigs = [_][]const u8{ "s", "a{ss}", "t", "b" };
                const pairs = try a.alloc([2]Value, 4);
                const entries = try a.alloc(Value, 4);
                for (0..4) |i| {
                    pairs[i] = .{ .{ .string = names[i] }, .{ .variant = .{ .signature = sigs[i], .value = &vals[i] } } };
                    entries[i] = .{ .dict_entry = &pairs[i] };
                }
                return f.reply("a{sv}", &.{.{ .array = .{ .signature = "{sv}", .items = entries } }});
            },
            .Set => {
                const item = f.find(path) orelse return f.fail("org.freedesktop.Secret.Error.NoSuchObject");
                if (item.locked) return f.fail("org.freedesktop.Secret.Error.IsLocked");
                const name = body[1].string;
                const v = body[2].unwrap();
                if (std.mem.eql(u8, name, "Label")) {
                    const l = try f.gpa.dupe(u8, v.string);
                    f.gpa.free(item.label);
                    item.label = l;
                } else if (std.mem.eql(u8, name, "Attributes")) {
                    var list = try f.dupeAttrList(try @import("secret.zig").dupeAttrs(a, v));
                    std.mem.swap(std.ArrayList(Attr), &list, &item.attrs);
                    freeAttrs(f.gpa, &list);
                } else return f.fail("org.freedesktop.DBus.Error.PropertyReadOnly");
                return f.reply("", &.{});
            },
        }
    }

    fn newPromptPath(f: *FakeBus) []const u8 {
        f.next_id += 1;
        const p = std.fmt.bufPrint(&f.pending_path, "/org/freedesktop/secrets/prompt/p{d}", .{f.next_id}) catch unreachable; // fits 64 bytes
        f.pending_path_len = p.len;
        return p;
    }

    fn queueSignal(f: *FakeBus, path: []const u8, sender: []const u8, dismissed: bool, result: ?[]const u8) !void {
        const p = try f.gpa.dupe(u8, path);
        errdefer f.gpa.free(p);
        const r: ?[]u8 = if (result) |s| try f.gpa.dupe(u8, s) else null;
        errdefer if (r) |s| f.gpa.free(s);
        try f.signals.append(f.gpa, .{ .path = p, .sender = sender, .dismissed = dismissed, .result = r });
    }
};

fn sameAttrs(a: []const Attr, b: []const Attr) bool {
    if (a.len != b.len) return false;
    for (b) |x| {
        const v = protocol.findAttr(a, x.key) orelse return false;
        if (!std.mem.eql(u8, v, x.value)) return false;
    }
    return true;
}
