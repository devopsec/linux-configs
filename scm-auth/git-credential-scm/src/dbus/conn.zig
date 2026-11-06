//! D-Bus connection: method calls with reply matching, match rules and
//! signal waiting.
//!
//! `Conn` speaks the message protocol over any `std.Io.Reader`/`Writer`
//! (in-memory in tests); `Bus` owns a real unix socket to the session bus,
//! authenticates and says `Hello`.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const message = @import("message.zig");
const address = @import("address.zig");
const auth = @import("auth.zig");
const Message = message.Message;
const Value = message.Value;
const Header = message.Header;

/// Signals matching a registered rule that arrive while waiting for a reply
/// are queued, up to this many; more are dropped.
pub const max_pending_signals = 64;
/// D-Bus names are at most 255 bytes.
pub const max_name_len = 255;

pub const bus_name = "org.freedesktop.DBus";
pub const bus_path = "/org/freedesktop/DBus";
pub const bus_interface = "org.freedesktop.DBus";

pub const Error = error{
    NoSessionBus,
    UnsupportedAddress,
    InvalidAddress,
    ConnectFailed,
    AuthRejected,
    /// Malformed data from the peer.
    Protocol,
    /// The peer answered with an error reply; see `Conn.errorName`.
    RemoteError,
    /// The connection was closed by the peer.
    Disconnected,
    ReadFailed,
    WriteFailed,
    /// A message we were asked to send is malformed.
    InvalidValue,
    OutOfMemory,
};

/// Signal match: unset fields match anything. Sender filtering is left to
/// the bus (signals carry unique names, rules may use well-known ones).
pub const MatchRule = struct {
    sender: ?[]const u8 = null,
    path: ?[]const u8 = null,
    interface: ?[]const u8 = null,
    member: ?[]const u8 = null,

    pub fn matches(rule: MatchRule, h: Header) bool {
        if (h.type != .signal) return false;
        return fieldMatches(rule.path, h.path) and
            fieldMatches(rule.interface, h.interface) and
            fieldMatches(rule.member, h.member);
    }

    fn fieldMatches(want: ?[]const u8, have: ?[]const u8) bool {
        const w = want orelse return true;
        const h = have orelse return false;
        return std.mem.eql(u8, w, h);
    }

    /// The bus match-rule string, e.g. `type='signal',path='/a'`.
    pub fn format(rule: MatchRule, gpa: Allocator) Error![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        try out.appendSlice(gpa, "type='signal'");
        const fields = [_]struct { []const u8, ?[]const u8 }{
            .{ "sender", rule.sender },
            .{ "path", rule.path },
            .{ "interface", rule.interface },
            .{ "member", rule.member },
        };
        for (fields) |f| {
            const v = f[1] orelse continue;
            if (v.len == 0 or v.len > max_name_len) return error.InvalidValue;
            for (v) |c| if (c == '\'' or c == ',' or c == '\\' or c == 0) return error.InvalidValue;
            try out.print(gpa, ",{s}='{s}'", .{ f[0], v });
        }
        return out.toOwnedSlice(gpa);
    }

    fn dupe(rule: MatchRule, gpa: Allocator) Allocator.Error!MatchRule {
        var r: MatchRule = .{};
        errdefer r.free(gpa);
        if (rule.sender) |s| r.sender = try gpa.dupe(u8, s);
        if (rule.path) |s| r.path = try gpa.dupe(u8, s);
        if (rule.interface) |s| r.interface = try gpa.dupe(u8, s);
        if (rule.member) |s| r.member = try gpa.dupe(u8, s);
        return r;
    }

    fn free(rule: MatchRule, gpa: Allocator) void {
        inline for (.{ rule.sender, rule.path, rule.interface, rule.member }) |f| {
            if (f) |s| gpa.free(s);
        }
    }

    fn eql(a: MatchRule, b: MatchRule) bool {
        return optEql(a.sender, b.sender) and optEql(a.path, b.path) and
            optEql(a.interface, b.interface) and optEql(a.member, b.member);
    }

    fn optEql(a: ?[]const u8, b: ?[]const u8) bool {
        if (a == null or b == null) return a == null and b == null;
        return std.mem.eql(u8, a.?, b.?);
    }
};

pub const Call = struct {
    destination: ?[]const u8,
    path: []const u8,
    interface: ?[]const u8,
    member: []const u8,
    signature: []const u8 = "",
    body: []const Value = &.{},
    flags: u8 = 0,
};

pub const Conn = struct {
    gpa: Allocator,
    reader: *Io.Reader,
    writer: *Io.Writer,
    last_serial: u32 = 0,
    rules: std.ArrayList(MatchRule) = .empty,
    pending: std.ArrayList(Message) = .empty,
    unique_name_buf: [max_name_len]u8 = undefined,
    unique_name_len: usize = 0,
    error_name_buf: [max_name_len]u8 = undefined,
    error_name_len: usize = 0,

    pub fn init(gpa: Allocator, reader: *Io.Reader, writer: *Io.Writer) Conn {
        return .{ .gpa = gpa, .reader = reader, .writer = writer };
    }

    pub fn deinit(c: *Conn) void {
        for (c.rules.items) |r| r.free(c.gpa);
        c.rules.deinit(c.gpa);
        for (c.pending.items) |*m| m.deinit(c.gpa);
        c.pending.deinit(c.gpa);
        c.* = undefined;
    }

    /// Our unique bus name (after `hello`).
    pub fn uniqueName(c: *const Conn) []const u8 {
        return c.unique_name_buf[0..c.unique_name_len];
    }

    /// Error name of the last `error.RemoteError` (truncated to 255 bytes).
    pub fn errorName(c: *const Conn) []const u8 {
        return c.error_name_buf[0..c.error_name_len];
    }

    fn nextSerial(c: *Conn) u32 {
        c.last_serial +%= 1;
        if (c.last_serial == 0) c.last_serial = 1;
        return c.last_serial;
    }

    /// Sends a message, assigning its serial, which is returned.
    pub fn send(c: *Conn, h: Header, body: []const Value) Error!u32 {
        var header = h;
        header.serial = c.nextSerial();
        const bytes = message.encodeMessage(c.gpa, header, body) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidValue, error.MessageTooLong => return error.InvalidValue,
        };
        defer {
            std.crypto.secureZero(u8, bytes);
            c.gpa.free(bytes);
        }
        c.writer.writeAll(bytes) catch return error.WriteFailed;
        c.writer.flush() catch return error.WriteFailed;
        return header.serial;
    }

    /// Reads the next complete message. Caller owns it.
    pub fn readMessage(c: *Conn) Error!Message {
        var prefix: [message.prefix_len]u8 = undefined;
        c.reader.readSliceAll(&prefix) catch |err| return mapRead(err);
        const len = try message.messageLength(&prefix);
        const raw = try c.gpa.alloc(u8, len);
        @memcpy(raw[0..prefix.len], &prefix);
        c.reader.readSliceAll(raw[prefix.len..]) catch |err| {
            std.crypto.secureZero(u8, raw);
            c.gpa.free(raw);
            return mapRead(err);
        };
        return message.parse(c.gpa, raw);
    }

    fn mapRead(err: Io.Reader.Error) Error {
        return switch (err) {
            error.EndOfStream => error.Disconnected,
            error.ReadFailed => error.ReadFailed,
        };
    }

    /// Calls a method and waits for its reply. Error replies become
    /// `error.RemoteError` (see `errorName`). Signals matching a registered
    /// rule are queued for `waitSignal`; other messages are dropped.
    pub fn call(c: *Conn, args: Call) Error!Message {
        const serial = try c.send(.{
            .type = .method_call,
            .flags = args.flags,
            .path = args.path,
            .interface = args.interface,
            .member = args.member,
            .destination = args.destination,
            .signature = args.signature,
        }, args.body);
        while (true) {
            var m = try c.readMessage();
            const h = m.header;
            if ((h.type == .method_return or h.type == .error_reply) and h.reply_serial == serial) {
                if (h.type == .method_return) return m;
                const name = h.error_name orelse "";
                c.error_name_len = @min(name.len, c.error_name_buf.len);
                @memcpy(c.error_name_buf[0..c.error_name_len], name[0..c.error_name_len]);
                m.deinit(c.gpa);
                return error.RemoteError;
            }
            try c.queueOrDrop(m);
        }
    }

    fn queueOrDrop(c: *Conn, m: Message) Error!void {
        var msg = m;
        for (c.rules.items) |r| {
            if (r.matches(msg.header) and c.pending.items.len < max_pending_signals) {
                c.pending.append(c.gpa, msg) catch |err| {
                    msg.deinit(c.gpa);
                    return err;
                };
                return;
            }
        }
        msg.deinit(c.gpa);
    }

    /// Says `Hello` and records the unique name. Must be the first call.
    pub fn hello(c: *Conn) Error!void {
        var reply = try c.call(.{ .destination = bus_name, .path = bus_path, .interface = bus_interface, .member = "Hello" });
        defer reply.deinit(c.gpa);
        if (!std.mem.eql(u8, reply.header.signature, "s")) return error.Protocol;
        const name = reply.body[0].string;
        if (name.len == 0 or name.len > max_name_len) return error.Protocol;
        @memcpy(c.unique_name_buf[0..name.len], name);
        c.unique_name_len = name.len;
    }

    /// Registers a match rule with the bus and locally.
    pub fn addMatch(c: *Conn, rule: MatchRule) Error!void {
        const text = try rule.format(c.gpa);
        defer c.gpa.free(text);
        const owned = try rule.dupe(c.gpa);
        errdefer owned.free(c.gpa);
        try c.rules.ensureUnusedCapacity(c.gpa, 1);
        var reply = try c.call(.{
            .destination = bus_name,
            .path = bus_path,
            .interface = bus_interface,
            .member = "AddMatch",
            .signature = "s",
            .body = &.{.{ .string = text }},
        });
        reply.deinit(c.gpa);
        c.rules.appendAssumeCapacity(owned);
    }

    /// Unregisters a rule added with `addMatch` and drops its queued signals.
    pub fn removeMatch(c: *Conn, rule: MatchRule) Error!void {
        const idx = for (c.rules.items, 0..) |r, i| {
            if (r.eql(rule)) break i;
        } else return;
        const text = try rule.format(c.gpa);
        defer c.gpa.free(text);
        const removed = c.rules.orderedRemove(idx);
        defer removed.free(c.gpa);
        var i: usize = 0;
        while (i < c.pending.items.len) {
            if (removed.matches(c.pending.items[i].header) and !c.anyRuleMatches(c.pending.items[i].header)) {
                var m = c.pending.orderedRemove(i);
                m.deinit(c.gpa);
            } else i += 1;
        }
        var reply = try c.call(.{
            .destination = bus_name,
            .path = bus_path,
            .interface = bus_interface,
            .member = "RemoveMatch",
            .signature = "s",
            .body = &.{.{ .string = text }},
        });
        reply.deinit(c.gpa);
    }

    fn anyRuleMatches(c: *const Conn, h: Header) bool {
        for (c.rules.items) |r| if (r.matches(h)) return true;
        return false;
    }

    /// Blocks (no timeout) until a signal matching `filter` arrives, taking
    /// queued signals first. Register a covering rule with `addMatch` before
    /// triggering the signal, or it may be missed. Caller owns the result.
    pub fn waitSignal(c: *Conn, filter: MatchRule) Error!Message {
        for (c.pending.items, 0..) |m, i| {
            if (filter.matches(m.header)) return c.pending.orderedRemove(i);
        }
        while (true) {
            const m = try c.readMessage();
            if (filter.matches(m.header)) return m;
            try c.queueOrDrop(m);
        }
    }
};

const session_addr_max = "unix:path=".len + address.max_path_len;

/// `DBUS_SESSION_BUS_ADDRESS`, else `unix:path=$XDG_RUNTIME_DIR/bus` (the
/// sd-bus/gio default), so callers without the variable (cron, daemons, IDE
/// background jobs) still reach the keyring; null when neither is usable.
pub fn sessionAddress(environ: *const std.process.Environ.Map, buf: *[session_addr_max]u8) ?[]const u8 {
    if (environ.get("DBUS_SESSION_BUS_ADDRESS")) |addr| {
        if (addr.len > 0) return addr;
    }
    const runtime = environ.get("XDG_RUNTIME_DIR") orelse return null;
    if (runtime.len == 0 or runtime[0] != '/') return null;
    return std.fmt.bufPrint(buf, "unix:path={s}/bus", .{runtime}) catch null;
}

/// A connection to the session bus over a unix socket. Not movable once
/// opened (the reader/writer interfaces point into it).
pub const Bus = struct {
    io: Io,
    stream: Io.net.Stream,
    reader: Io.net.Stream.Reader,
    writer: Io.net.Stream.Writer,
    read_buf: [64 * 1024]u8,
    write_buf: [4 * 1024]u8,
    guid: [auth.guid_len]u8,
    conn: Conn,

    /// Opens the session bus named by `environ` (see `sessionAddress`).
    pub fn openSession(bus: *Bus, gpa: Allocator, io: Io, environ: *const std.process.Environ.Map) Error!void {
        var buf: [session_addr_max]u8 = undefined;
        const addr = sessionAddress(environ, &buf) orelse return error.NoSessionBus;
        return bus.open(gpa, io, addr);
    }

    /// Connects to `addr` (`unix:path=` only), authenticates and says Hello.
    pub fn open(bus: *Bus, gpa: Allocator, io: Io, addr: []const u8) Error!void {
        var path_buf: [address.max_path_len]u8 = undefined;
        const path = try address.parseUnixPath(addr, &path_buf);
        const ua = Io.net.UnixAddress.init(path) catch return error.InvalidAddress;
        bus.io = io;
        bus.stream = ua.connect(io) catch return error.ConnectFailed;
        errdefer bus.stream.close(io);
        bus.reader = bus.stream.reader(io, &bus.read_buf);
        bus.writer = bus.stream.writer(io, &bus.write_buf);
        try auth.authenticate(&bus.reader.interface, &bus.writer.interface, auth.currentUid(), &bus.guid);
        bus.conn = .init(gpa, &bus.reader.interface, &bus.writer.interface);
        errdefer bus.conn.deinit();
        try bus.conn.hello();
    }

    pub fn close(bus: *Bus) void {
        bus.conn.deinit();
        bus.stream.close(bus.io);
        std.crypto.secureZero(u8, &bus.read_buf);
        std.crypto.secureZero(u8, &bus.write_buf);
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

/// Builds a server byte stream from messages.
fn serverStream(gpa: Allocator, msgs: []const struct { Header, []const Value }) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (msgs) |m| {
        const bytes = try message.encodeMessage(gpa, m[0], m[1]);
        defer gpa.free(bytes);
        try out.appendSlice(gpa, bytes);
    }
    return out.toOwnedSlice(gpa);
}

fn replyHeader(serial: u32, reply_serial: u32, sig: []const u8) Header {
    return .{ .type = .method_return, .serial = serial, .reply_serial = reply_serial, .sender = bus_name, .signature = sig };
}

fn signalHeader(serial: u32, path: []const u8, member: []const u8) Header {
    return .{ .type = .signal, .serial = serial, .path = path, .interface = "org.freedesktop.Secret.Prompt", .member = member, .signature = "bv" };
}

const completed_body = [_]Value{ .{ .boolean = false }, .{ .variant = .{ .signature = "s", .value = &.{ .string = "" } } } };

test "hello, call with interleaved messages, queued signals" {
    const gpa = testing.allocator;
    const stream = try serverStream(gpa, &.{
        .{ replyHeader(1, 1, "s"), &.{.{ .string = ":1.42" }} }, // Hello
        .{ replyHeader(2, 2, ""), &.{} }, // AddMatch
        .{ signalHeader(3, "/p/other", "Completed"), &completed_body }, // dropped: no rule
        .{ signalHeader(4, "/p/1", "Completed"), &completed_body }, // queued
        .{ replyHeader(5, 99, "s"), &.{.{ .string = "stale" }} }, // reply to someone else
        .{ replyHeader(6, 3, "s"), &.{.{ .string = "pong" }} }, // our call
    });
    defer gpa.free(stream);
    var r: Io.Reader = .fixed(stream);
    var w: Io.Writer.Allocating = .init(gpa);
    defer w.deinit();
    var c: Conn = .init(gpa, &r, &w.writer);
    defer c.deinit();

    try c.hello();
    try testing.expectEqualStrings(":1.42", c.uniqueName());
    try c.addMatch(.{ .interface = "org.freedesktop.Secret.Prompt", .member = "Completed", .path = "/p/1" });

    var m = try c.call(.{ .destination = "org.x", .path = "/", .interface = "org.x.I", .member = "Ping" });
    defer m.deinit(gpa);
    try testing.expectEqualStrings("pong", m.body[0].asString().?);
    try testing.expectEqual(1, c.pending.items.len);

    var s = try c.waitSignal(.{ .path = "/p/1", .member = "Completed" });
    defer s.deinit(gpa);
    try testing.expectEqual(4, s.header.serial);
    try testing.expectEqual(false, s.body[0].asBool().?);
    try testing.expectEqual(0, c.pending.items.len);

    // Everything sent parses, with serials 1..3 and the AddMatch rule text.
    var sent: Io.Reader = .fixed(w.written());
    var sc: Conn = .init(gpa, &sent, &w.writer);
    defer sc.deinit();
    const members = [_][]const u8{ "Hello", "AddMatch", "Ping" };
    for (members, 1..) |member, serial| {
        var out = try sc.readMessage();
        defer out.deinit(gpa);
        try testing.expectEqual(serial, out.header.serial);
        try testing.expectEqualStrings(member, out.header.member.?);
        if (serial == 2) try testing.expectEqualStrings(
            "type='signal',path='/p/1',interface='org.freedesktop.Secret.Prompt',member='Completed'",
            out.body[0].asString().?,
        );
    }
    try testing.expectError(error.Disconnected, sc.readMessage());
}

test "error replies and disconnects" {
    const gpa = testing.allocator;
    const stream = try serverStream(gpa, &.{
        .{ .{ .type = .error_reply, .serial = 1, .reply_serial = 1, .error_name = "org.freedesktop.Secret.Error.NoSuchObject", .signature = "s" }, &.{.{ .string = "No such item" }} },
    });
    defer gpa.free(stream);
    var r: Io.Reader = .fixed(stream);
    var w: Io.Writer.Allocating = .init(gpa);
    defer w.deinit();
    var c: Conn = .init(gpa, &r, &w.writer);
    defer c.deinit();
    try testing.expectError(error.RemoteError, c.call(.{ .destination = "d", .path = "/i", .interface = "i.I", .member = "Delete" }));
    try testing.expectEqualStrings("org.freedesktop.Secret.Error.NoSuchObject", c.errorName());
    try testing.expectError(error.Disconnected, c.call(.{ .destination = "d", .path = "/i", .interface = "i.I", .member = "Delete" }));
    try testing.expectError(error.Disconnected, c.waitSignal(.{}));
    try testing.expectError(error.InvalidValue, c.call(.{ .destination = "d", .path = "bad path", .interface = "i.I", .member = "M" }));
}

test "truncated and malformed streams" {
    const gpa = testing.allocator;
    const stream = try serverStream(gpa, &.{.{ replyHeader(1, 1, "s"), &.{.{ .string = ":1.1" }} }});
    defer gpa.free(stream);
    for ([_]usize{ 0, 5, 16, stream.len - 1 }) |n| {
        var r: Io.Reader = .fixed(stream[0..n]);
        var w: Io.Writer.Allocating = .init(gpa);
        defer w.deinit();
        var c: Conn = .init(gpa, &r, &w.writer);
        defer c.deinit();
        try testing.expectError(error.Disconnected, c.hello());
    }
    var bad = try gpa.dupe(u8, stream);
    defer gpa.free(bad);
    bad[0] = 'X';
    var r: Io.Reader = .fixed(bad);
    var w: Io.Writer.Allocating = .init(gpa);
    defer w.deinit();
    var c: Conn = .init(gpa, &r, &w.writer);
    defer c.deinit();
    try testing.expectError(error.Protocol, c.hello());
}

test "pending signal queue is bounded and removeMatch drops queued signals" {
    const gpa = testing.allocator;
    const n = max_pending_signals + 6;
    var msgs: [n + 3]struct { Header, []const Value } = undefined;
    msgs[0] = .{ replyHeader(1, 1, ""), &.{} }; // AddMatch
    for (1..n + 1) |i| msgs[i] = .{ signalHeader(@intCast(i + 1), "/p/1", "Completed"), &completed_body };
    msgs[n + 1] = .{ replyHeader(n + 2, 2, ""), &.{} }; // our call
    msgs[n + 2] = .{ replyHeader(n + 3, 3, ""), &.{} }; // RemoveMatch
    const stream = try serverStream(gpa, &msgs);
    defer gpa.free(stream);
    var r: Io.Reader = .fixed(stream);
    var w: Io.Writer.Allocating = .init(gpa);
    defer w.deinit();
    var c: Conn = .init(gpa, &r, &w.writer);
    defer c.deinit();
    const rule: MatchRule = .{ .path = "/p/1" };
    try c.addMatch(rule);
    var m = try c.call(.{ .destination = "d", .path = "/", .interface = "i.I", .member = "M" });
    m.deinit(gpa);
    try testing.expectEqual(max_pending_signals, c.pending.items.len);
    try c.removeMatch(rule);
    try testing.expectEqual(0, c.pending.items.len);
    try testing.expectEqual(0, c.rules.items.len);
}

test "match rule formatting and matching" {
    const gpa = testing.allocator;
    const text = try (MatchRule{ .sender = "org.freedesktop.secrets", .member = "Completed" }).format(gpa);
    defer gpa.free(text);
    try testing.expectEqualStrings("type='signal',sender='org.freedesktop.secrets',member='Completed'", text);
    try testing.expectError(error.InvalidValue, (MatchRule{ .path = "/a'b" }).format(gpa));
    try testing.expectError(error.InvalidValue, (MatchRule{ .member = "" }).format(gpa));

    const h = signalHeader(1, "/p/1", "Completed");
    try testing.expect((MatchRule{}).matches(h));
    try testing.expect((MatchRule{ .path = "/p/1", .sender = "ignored" }).matches(h));
    try testing.expect(!(MatchRule{ .path = "/p/2" }).matches(h));
    try testing.expect(!(MatchRule{}).matches(replyHeader(1, 1, "")));
}

test "Bus.open rejects unsupported addresses before connecting" {
    var bus: Bus = undefined;
    try testing.expectError(error.UnsupportedAddress, bus.open(testing.allocator, testing.io, "unix:abstract=/tmp/x"));
    try testing.expectError(error.NoSessionBus, bus.open(testing.allocator, testing.io, ""));
    try testing.expectError(error.ConnectFailed, bus.open(testing.allocator, testing.io, "unix:path=/nonexistent/scm-auth-test.sock"));
    var env: std.process.Environ.Map = .init(testing.allocator);
    defer env.deinit();
    try testing.expectError(error.NoSessionBus, bus.openSession(testing.allocator, testing.io, &env));
}

test "sessionAddress falls back to XDG_RUNTIME_DIR/bus" {
    var buf: [session_addr_max]u8 = undefined;
    var env: std.process.Environ.Map = .init(testing.allocator);
    defer env.deinit();
    try testing.expectEqual(null, sessionAddress(&env, &buf));
    try env.put("XDG_RUNTIME_DIR", "relative");
    try testing.expectEqual(null, sessionAddress(&env, &buf));
    try env.put("XDG_RUNTIME_DIR", "/run/user/1000");
    try testing.expectEqualStrings("unix:path=/run/user/1000/bus", sessionAddress(&env, &buf).?);
    try env.put("DBUS_SESSION_BUS_ADDRESS", "");
    try testing.expectEqualStrings("unix:path=/run/user/1000/bus", sessionAddress(&env, &buf).?);
    try env.put("DBUS_SESSION_BUS_ADDRESS", "unix:path=/x/bus");
    try testing.expectEqualStrings("unix:path=/x/bus", sessionAddress(&env, &buf).?);
    const long: [200]u8 = @splat('/');
    try env.put("XDG_RUNTIME_DIR", &long);
    try env.put("DBUS_SESSION_BUS_ADDRESS", "");
    try testing.expectEqual(null, sessionAddress(&env, &buf));
}
