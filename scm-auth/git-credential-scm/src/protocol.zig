//! git credential helper protocol: request parsing, response writing, keyring
//! attribute and label construction, and the secret text format shared with
//! git's stock `git-credential-libsecret` helper.
//!
//! This module is transport-agnostic: it never talks to D-Bus.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

/// Maximum number of bytes accepted on the credential input.
pub const max_input_len: usize = 64 * 1024;
/// Secret Service schema used by the stock helper.
pub const schema_name = "org.git.Password";
/// Value of the `application` attribute on items written by this helper.
pub const application_name = "scm-auth";
/// Tool recorded in the `tool` attribute when none is given.
pub const default_tool = "git";
/// Prefix of the labels written by this helper.
pub const label_prefix = "scm-auth: ";
/// Longest accepted `--tool` value.
pub const max_tool_len = 32;

pub const attr_schema = "xdg:schema";
pub const attr_user = "user";
pub const attr_protocol = "protocol";
pub const attr_server = "server";
pub const attr_port = "port";
pub const attr_object = "object";
pub const attr_application = "application";
pub const attr_tool = "tool";

const expiry_prefix = "password_expiry_utc=";
const refresh_prefix = "oauth_refresh_token=";

/// Actions accepted on the command line. `get`, `store` and `erase` are the
/// git credential helper actions; `list` and `retag` are admin commands.
pub const Action = enum {
    get,
    store,
    erase,
    list,
    retag,

    pub fn fromString(name: []const u8) ?Action {
        return std.meta.stringToEnum(Action, name);
    }

    /// True for the actions that read a git credential request on stdin.
    pub fn readsCredential(action: Action) bool {
        return switch (action) {
            .get, .store, .erase => true,
            .list, .retag => false,
        };
    }
};

pub const ParseError = error{ Protocol, ReadFailed, OutOfMemory };

/// A parsed git credential request. All slices are owned by the request.
/// `password` and `oauth_refresh_token` are wiped before they are freed.
pub const Request = struct {
    protocol: ?[]const u8 = null,
    host: ?[]const u8 = null,
    port: ?u16 = null,
    path: ?[]const u8 = null,
    username: ?[]const u8 = null,
    password: ?[]u8 = null,
    password_expiry_utc: ?i64 = null,
    oauth_refresh_token: ?[]u8 = null,

    /// Reads `key=value` lines until a blank line or end of stream.
    ///
    /// Unknown keys (including `capability[]`, `wwwauth[]`, `state[]`, `url`)
    /// are skipped. A line without `=`, an empty key, a NUL byte, a value
    /// that is not UTF-8, a bad port or expiry, or more than `limit` bytes of
    /// input yields `error.Protocol`; nothing from the input is echoed.
    ///
    /// Secret values pass through the reader's buffer: the caller owns that
    /// buffer and should wipe it after parsing.
    pub fn parse(gpa: Allocator, r: *Reader, limit: usize) ParseError!Request {
        var req: Request = .{};
        errdefer req.deinit(gpa);
        var consumed: usize = 0;
        while (true) {
            const maybe_line = r.takeDelimiter('\n') catch |err| switch (err) {
                error.StreamTooLong => return error.Protocol,
                error.ReadFailed => return error.ReadFailed,
            };
            const line = maybe_line orelse break;
            consumed += line.len + 1;
            if (consumed > limit) return error.Protocol;
            if (line.len == 0) break;
            try req.applyLine(gpa, line);
        }
        return req;
    }

    fn applyLine(req: *Request, gpa: Allocator, line: []const u8) ParseError!void {
        if (std.mem.findScalar(u8, line, 0) != null) return error.Protocol;
        const eq = std.mem.findScalar(u8, line, '=') orelse return error.Protocol;
        if (eq == 0) return error.Protocol;
        const key = line[0..eq];
        const value = line[eq + 1 ..];

        const Key = enum { protocol, host, path, username, password, password_expiry_utc, oauth_refresh_token };
        const known = std.meta.stringToEnum(Key, key) orelse return;
        if (!std.unicode.utf8ValidateSlice(value)) return error.Protocol;
        switch (known) {
            .protocol => try replace(gpa, &req.protocol, value),
            .path => try replace(gpa, &req.path, value),
            .username => try replace(gpa, &req.username, value),
            .host => {
                const split = try splitHostPort(value);
                try replace(gpa, &req.host, split.host);
                req.port = split.port;
            },
            .password => try replaceSecret(gpa, &req.password, value),
            .oauth_refresh_token => try replaceSecret(gpa, &req.oauth_refresh_token, value),
            .password_expiry_utc => req.password_expiry_utc = std.fmt.parseInt(i64, value, 10) catch
                return error.Protocol,
        }
    }

    /// Frees every field; secrets are wiped first.
    pub fn deinit(req: *Request, gpa: Allocator) void {
        if (req.protocol) |s| gpa.free(s);
        if (req.host) |s| gpa.free(s);
        if (req.path) |s| gpa.free(s);
        if (req.username) |s| gpa.free(s);
        if (req.password) |s| wipeFree(gpa, s);
        if (req.oauth_refresh_token) |s| wipeFree(gpa, s);
        req.* = .{};
    }

    /// The keyring lookup key of this request (borrows from `req`).
    pub fn target(req: *const Request) Target {
        return .{
            .protocol = req.protocol,
            .host = req.host,
            .port = req.port,
            .path = req.path,
            .username = req.username,
        };
    }

    /// `get` needs a protocol and a host or path, like the stock helper.
    pub fn lookupable(req: *const Request) bool {
        return req.protocol != null and (req.host != null or req.path != null);
    }

    /// `store` needs a non-empty protocol and host, a password, and an
    /// expiry (if any) that is not in the past relative to `now_unix`.
    pub fn storable(req: *const Request, now_unix: i64) bool {
        const protocol = req.protocol orelse return false;
        const host = req.host orelse return false;
        if (protocol.len == 0 or host.len == 0 or req.password == null) return false;
        if (req.password_expiry_utc) |expiry| return expiry >= now_unix;
        return true;
    }

    /// `erase` refuses an empty pattern, which would match everything.
    pub fn erasable(req: *const Request) bool {
        return req.protocol != null or req.host != null or req.path != null or req.username != null;
    }
};

fn replace(gpa: Allocator, field: *?[]const u8, value: []const u8) Allocator.Error!void {
    const copy = try gpa.dupe(u8, value);
    if (field.*) |old| gpa.free(old);
    field.* = copy;
}

fn replaceSecret(gpa: Allocator, field: *?[]u8, value: []const u8) Allocator.Error!void {
    const copy = try gpa.dupe(u8, value);
    if (field.*) |old| wipeFree(gpa, old);
    field.* = copy;
}

const HostPort = struct { host: []const u8, port: ?u16 };

/// Splits `host[:port]` (or `[v6]:port`). An empty or zero port means no port,
/// as in the stock helper; a non-numeric or out-of-range port is an error.
fn splitHostPort(value: []const u8) error{Protocol}!HostPort {
    var host_end: usize = value.len;
    var port_text: ?[]const u8 = null;
    if (value.len > 0 and value[0] == '[') {
        const close = std.mem.findScalar(u8, value, ']') orelse return error.Protocol;
        host_end = close + 1;
        if (host_end < value.len) {
            if (value[host_end] != ':') return error.Protocol;
            port_text = value[host_end + 1 ..];
        }
    } else if (std.mem.findScalarLast(u8, value, ':')) |colon| {
        host_end = colon;
        port_text = value[colon + 1 ..];
    }
    return .{ .host = value[0..host_end], .port = try parsePort(port_text orelse "") };
}

fn parsePort(text: []const u8) error{Protocol}!?u16 {
    if (text.len == 0) return null;
    for (text) |c| if (!std.ascii.isDigit(c)) return error.Protocol;
    const port = std.fmt.parseInt(u16, text, 10) catch return error.Protocol;
    return if (port == 0) null else port;
}

/// The stock-attribute key of a keyring item. Slices are borrowed.
pub const Target = struct {
    protocol: ?[]const u8 = null,
    host: ?[]const u8 = null,
    port: ?u16 = null,
    path: ?[]const u8 = null,
    username: ?[]const u8 = null,

    /// Rebuilds a target from item attributes (borrows from `attrs`).
    /// An unparsable `port` attribute is `error.Protocol`.
    pub fn fromAttrs(attrs: []const Attr) error{Protocol}!Target {
        return .{
            .protocol = findAttr(attrs, attr_protocol),
            .host = findAttr(attrs, attr_server),
            .port = try parsePort(findAttr(attrs, attr_port) orelse ""),
            .path = findAttr(attrs, attr_object),
            .username = findAttr(attrs, attr_user),
        };
    }
};

pub const Attr = struct { key: []const u8, value: []const u8 };

pub fn findAttr(attrs: []const Attr, key: []const u8) ?[]const u8 {
    for (attrs) |a| if (std.mem.eql(u8, a.key, key)) return a.value;
    return null;
}

pub const AttrKind = union(enum) {
    /// Stock attributes only, without `xdg:schema`: matches legacy and
    /// tagged items alike (the stock helper ignores the schema name too).
    search,
    /// Everything written on store: schema, stock attributes,
    /// `application=scm-auth` and `tool=<tool>`.
    store: []const u8,
};

/// An ordered attribute list. Values borrow from the `Target` (and the tool
/// string) used to build it, except the port text, which is owned.
pub const AttrSet = struct {
    items: []Attr,
    port_text: ?[]u8,

    pub fn init(gpa: Allocator, t: Target, kind: AttrKind) Allocator.Error!AttrSet {
        var list: std.ArrayList(Attr) = try .initCapacity(gpa, 8);
        errdefer list.deinit(gpa);
        var port_text: ?[]u8 = null;
        errdefer if (port_text) |p| gpa.free(p);

        if (kind == .store) list.appendAssumeCapacity(.{ .key = attr_schema, .value = schema_name });
        if (t.username) |v| list.appendAssumeCapacity(.{ .key = attr_user, .value = v });
        if (t.protocol) |v| list.appendAssumeCapacity(.{ .key = attr_protocol, .value = v });
        if (t.host) |v| list.appendAssumeCapacity(.{ .key = attr_server, .value = v });
        if (t.port) |port| {
            port_text = try gpa.print("{d}", .{port});
            list.appendAssumeCapacity(.{ .key = attr_port, .value = port_text.? });
        }
        if (t.path) |v| list.appendAssumeCapacity(.{ .key = attr_object, .value = v });
        switch (kind) {
            .search => {},
            .store => |tool| {
                list.appendAssumeCapacity(.{ .key = attr_application, .value = application_name });
                list.appendAssumeCapacity(.{ .key = attr_tool, .value = tool });
            },
        }
        return .{ .items = try list.toOwnedSlice(gpa), .port_text = port_text };
    }

    pub fn deinit(set: *AttrSet, gpa: Allocator) void {
        gpa.free(set.items);
        if (set.port_text) |p| gpa.free(p);
        set.* = undefined;
    }

    pub fn get(set: *const AttrSet, key: []const u8) ?[]const u8 {
        return findAttr(set.items, key);
    }
};

/// `scm-auth: <protocol>://<host>[:port]/[path]`; caller frees.
pub fn makeLabel(gpa: Allocator, t: Target) Allocator.Error![]u8 {
    const protocol = t.protocol orelse "";
    const host = t.host orelse "";
    const path = t.path orelse "";
    if (t.port) |port| return gpa.print("{s}{s}://{s}:{d}/{s}", .{ label_prefix, protocol, host, port, path });
    return gpa.print("{s}{s}://{s}/{s}", .{ label_prefix, protocol, host, path });
}

/// Tool to record for an untagged item during `retag`: items created by
/// forge carry a `forge: <host>` label.
pub fn toolForLegacyLabel(label: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, label, "forge: ")) "forge" else default_tool;
}

/// True when `name` is a usable `tool` attribute value: 1–32 bytes of
/// `[a-z0-9_-]`.
pub fn validTool(name: []const u8) bool {
    if (name.len == 0 or name.len > max_tool_len) return false;
    for (name) |c| switch (c) {
        'a'...'z', '0'...'9', '_', '-' => {},
        else => return false,
    };
    return true;
}

/// Encodes the stock helper's secret text:
/// `<password>[\npassword_expiry_utc=<n>][\noauth_refresh_token=<t>]`.
/// The result is allocated once at its exact size; free it with `wipeFree`.
pub fn encodeSecret(
    gpa: Allocator,
    password: []const u8,
    expiry: ?i64,
    refresh_token: ?[]const u8,
) Allocator.Error![]u8 {
    var expiry_buf: [24]u8 = undefined; // an i64 needs at most 20 bytes
    const expiry_text: ?[]const u8 = if (expiry) |e|
        expiry_buf[0..std.fmt.printInt(&expiry_buf, e, 10, .lower, .{})]
    else
        null;
    var len = password.len;
    if (expiry_text) |e| len += 1 + expiry_prefix.len + e.len;
    if (refresh_token) |t| len += 1 + refresh_prefix.len + t.len;

    const out = try gpa.alloc(u8, len);
    var pos: usize = 0;
    append(out, &pos, password);
    if (expiry_text) |e| {
        append(out, &pos, "\n" ++ expiry_prefix);
        append(out, &pos, e);
    }
    if (refresh_token) |t| {
        append(out, &pos, "\n" ++ refresh_prefix);
        append(out, &pos, t);
    }
    std.debug.assert(pos == len);
    return out;
}

fn append(out: []u8, pos: *usize, bytes: []const u8) void {
    @memcpy(out[pos.*..][0..bytes.len], bytes);
    pos.* += bytes.len;
}

/// A decoded secret; every field is owned and wiped on `deinit`.
pub const StoredSecret = struct {
    password: []u8,
    password_expiry_utc: ?i64 = null,
    oauth_refresh_token: ?[]u8 = null,

    pub fn deinit(s: *StoredSecret, gpa: Allocator) void {
        wipeFree(gpa, s.password);
        if (s.oauth_refresh_token) |t| wipeFree(gpa, t);
        s.* = undefined;
    }
};

/// Decodes the stock secret text the way `git-credential-libsecret` does:
/// the first line is the password; later lines with a known prefix set the
/// expiry or refresh token (last one wins); anything else is ignored. An
/// expiry that is not an integer is dropped.
pub fn decodeSecret(gpa: Allocator, text: []const u8) Allocator.Error!StoredSecret {
    var it = std.mem.splitScalar(u8, text, '\n');
    const first = it.first();
    var expiry: ?i64 = null;
    var token_text: ?[]const u8 = null;
    while (it.next()) |line| {
        if (std.mem.startsWith(u8, line, expiry_prefix)) {
            expiry = std.fmt.parseInt(i64, line[expiry_prefix.len..], 10) catch null;
        } else if (std.mem.startsWith(u8, line, refresh_prefix)) {
            token_text = line[refresh_prefix.len..];
        }
    }
    const password = try gpa.dupe(u8, first);
    errdefer wipeFree(gpa, password);
    const token: ?[]u8 = if (token_text) |t| try gpa.dupe(u8, t) else null;
    return .{ .password = password, .password_expiry_utc = expiry, .oauth_refresh_token = token };
}

/// Fields written back to git on `get`.
pub const Credential = struct {
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    password_expiry_utc: ?i64 = null,
    oauth_refresh_token: ?[]const u8 = null,
};

pub const WriteError = error{ Protocol, WriteFailed };

/// Writes `key=value` lines in the stock order. Every value is validated
/// first (no newline or NUL), so either all fields are written or none.
/// Does not flush.
pub fn writeCredential(w: *Writer, c: Credential) WriteError!void {
    const texts = [_]?[]const u8{ c.username, c.password, c.oauth_refresh_token };
    for (texts) |maybe| if (maybe) |v| {
        if (std.mem.findAny(u8, v, "\n\x00") != null) return error.Protocol;
    };
    if (c.username) |v| try w.print("username={s}\n", .{v});
    if (c.password) |v| try w.print("password={s}\n", .{v});
    if (c.password_expiry_utc) |v| try w.print("password_expiry_utc={d}\n", .{v});
    if (c.oauth_refresh_token) |v| try w.print("oauth_refresh_token={s}\n", .{v});
}

/// Wipes `buf` and frees it.
pub fn wipeFree(gpa: Allocator, buf: []u8) void {
    std.crypto.secureZero(u8, buf);
    gpa.free(buf);
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn parseText(gpa: Allocator, text: []const u8) ParseError!Request {
    var r: Reader = .fixed(text);
    return Request.parse(gpa, &r, max_input_len);
}

test "parse full request" {
    var req = try parseText(testing.allocator,
        \\protocol=https
        \\host=example.test:8443
        \\path=org/repo.git
        \\username=alice
        \\password=s3cret
        \\password_expiry_utc=1700000000
        \\oauth_refresh_token=refresh
        \\capability[]=authtype
        \\wwwauth[]=Basic realm="x"
        \\url=https://example.test/
        \\
        \\protocol=ignored-after-blank-line
        \\
    );
    defer req.deinit(testing.allocator);
    try testing.expectEqualStrings("https", req.protocol.?);
    try testing.expectEqualStrings("example.test", req.host.?);
    try testing.expectEqual(8443, req.port.?);
    try testing.expectEqualStrings("org/repo.git", req.path.?);
    try testing.expectEqualStrings("alice", req.username.?);
    try testing.expectEqualStrings("s3cret", req.password.?);
    try testing.expectEqual(1700000000, req.password_expiry_utc.?);
    try testing.expectEqualStrings("refresh", req.oauth_refresh_token.?);
}

test "parse until EOF without trailing blank line or newline" {
    var req = try parseText(testing.allocator, "protocol=https\nhost=github.com");
    defer req.deinit(testing.allocator);
    try testing.expectEqualStrings("github.com", req.host.?);
    try testing.expectEqual(null, req.port);
    try testing.expect(req.lookupable());
}

test "parse empty input" {
    var req = try parseText(testing.allocator, "");
    defer req.deinit(testing.allocator);
    try testing.expect(!req.lookupable());
    try testing.expect(!req.erasable());
}

test "parse keeps the last duplicate and empty values" {
    var req = try parseText(testing.allocator, "password=a\npassword=b\nusername=\nhost=h:\n\n");
    defer req.deinit(testing.allocator);
    try testing.expectEqualStrings("b", req.password.?);
    try testing.expectEqualStrings("", req.username.?);
    try testing.expectEqualStrings("h", req.host.?);
    try testing.expectEqual(null, req.port);
}

test "parse host and port forms" {
    const cases = [_]struct { in: []const u8, host: []const u8, port: ?u16 }{
        .{ .in = "host=h:0\n", .host = "h", .port = null },
        .{ .in = "host=h:65535\n", .host = "h", .port = 65535 },
        .{ .in = "host=[::1]\n", .host = "[::1]", .port = null },
        .{ .in = "host=[::1]:22\n", .host = "[::1]", .port = 22 },
    };
    for (cases) |case| {
        var req = try parseText(testing.allocator, case.in);
        defer req.deinit(testing.allocator);
        try testing.expectEqualStrings(case.host, req.host.?);
        try testing.expectEqual(case.port, req.port);
    }
}

test "parse rejects malformed input" {
    const bad = [_][]const u8{
        "protocol\n",
        "=value\n",
        "host=h:65536\n",
        "host=h:1x\n",
        "host=[::1\n",
        "host=[::1]x\n",
        "password_expiry_utc=soon\n",
        "password_expiry_utc=\n",
        "username=a\x00b\n",
        "username=\xff\n",
        "password=\xc3\x28\n",
    };
    for (bad) |text| try testing.expectError(error.Protocol, parseText(testing.allocator, text));
}

test "parse enforces the input limit" {
    const gpa = testing.allocator;
    const big = try gpa.alloc(u8, max_input_len + 16);
    defer gpa.free(big);
    @memset(big, 'a');
    @memcpy(big[0..9], "username=");
    try testing.expectError(error.Protocol, parseText(gpa, big));

    // Many short lines past the cap fail too.
    var aw: Writer.Allocating = .init(gpa);
    defer aw.deinit();
    while (aw.written().len <= max_input_len) try aw.writer.writeAll("capability[]=authtype\n");
    try testing.expectError(error.Protocol, parseText(gpa, aw.written()));

    // A small reader buffer reports an over-long line as a protocol error.
    var small_buf: [16]u8 = undefined;
    var src: Reader = .fixed("username=this-line-is-longer-than-sixteen\n");
    var limited = src.limited(.unlimited, &small_buf);
    try testing.expectError(error.Protocol, Request.parse(gpa, &limited.interface, max_input_len));
}

test "parse survives every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(gpa: Allocator) !void {
            var req = try parseText(gpa,
                \\protocol=https
                \\host=example.test:443
                \\path=p
                \\username=u
                \\password=pw
                \\password=pw2
                \\oauth_refresh_token=t
                \\
            );
            req.deinit(gpa);
        }
    }.run, .{});
}

test "request predicates" {
    var req = try parseText(testing.allocator, "protocol=https\nhost=h\npassword=p\npassword_expiry_utc=100\n");
    defer req.deinit(testing.allocator);
    try testing.expect(req.storable(100));
    try testing.expect(req.storable(50));
    try testing.expect(!req.storable(101));
    try testing.expect(req.erasable());

    var no_pw = try parseText(testing.allocator, "protocol=https\nhost=h\n");
    defer no_pw.deinit(testing.allocator);
    try testing.expect(!no_pw.storable(0));
    try testing.expect(no_pw.lookupable());

    var path_only = try parseText(testing.allocator, "protocol=file\npath=/srv/repo\n");
    defer path_only.deinit(testing.allocator);
    try testing.expect(path_only.lookupable());
    try testing.expect(!path_only.storable(0));
}

test "search attributes are the stock ones in order" {
    const gpa = testing.allocator;
    var set: AttrSet = try .init(gpa, .{ .protocol = "https", .host = "github.com", .username = "bob" }, .search);
    defer set.deinit(gpa);
    try testing.expectEqual(3, set.items.len);
    try testing.expectEqualStrings(attr_user, set.items[0].key);
    try testing.expectEqualStrings(attr_protocol, set.items[1].key);
    try testing.expectEqualStrings(attr_server, set.items[2].key);
    try testing.expectEqual(null, set.get(attr_schema));
    try testing.expectEqual(null, set.get(attr_application));
}

test "store attributes add schema, port, object, application and tool" {
    const gpa = testing.allocator;
    const t: Target = .{ .protocol = "https", .host = "h.test", .port = 8443, .path = "a/b.git" };
    var set: AttrSet = try .init(gpa, t, .{ .store = "forge" });
    defer set.deinit(gpa);
    const want = [_]Attr{
        .{ .key = "xdg:schema", .value = "org.git.Password" },
        .{ .key = "protocol", .value = "https" },
        .{ .key = "server", .value = "h.test" },
        .{ .key = "port", .value = "8443" },
        .{ .key = "object", .value = "a/b.git" },
        .{ .key = "application", .value = "scm-auth" },
        .{ .key = "tool", .value = "forge" },
    };
    try testing.expectEqual(want.len, set.items.len);
    for (want, set.items) |w, got| {
        try testing.expectEqualStrings(w.key, got.key);
        try testing.expectEqualStrings(w.value, got.value);
    }
    const back = try Target.fromAttrs(set.items);
    try testing.expectEqual(8443, back.port.?);
    try testing.expectEqualStrings("a/b.git", back.path.?);
    try testing.expectEqual(null, back.username);
}

test "attribute set survives every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(gpa: Allocator) !void {
            var set: AttrSet = try .init(gpa, .{ .protocol = "https", .host = "h", .port = 1 }, .{ .store = "git" });
            set.deinit(gpa);
        }
    }.run, .{});
}

test "target from attrs rejects a bad port" {
    const attrs = [_]Attr{.{ .key = "port", .value = "http" }};
    try testing.expectError(error.Protocol, Target.fromAttrs(&attrs));
}

test "labels" {
    const gpa = testing.allocator;
    const cases = [_]struct { t: Target, want: []const u8 }{
        .{ .t = .{ .protocol = "https", .host = "github.com" }, .want = "scm-auth: https://github.com/" },
        .{ .t = .{ .protocol = "https", .host = "h", .port = 8443 }, .want = "scm-auth: https://h:8443/" },
        .{ .t = .{ .protocol = "https", .host = "h", .path = "o/r.git" }, .want = "scm-auth: https://h/o/r.git" },
    };
    for (cases) |case| {
        const label = try makeLabel(gpa, case.t);
        defer gpa.free(label);
        try testing.expectEqualStrings(case.want, label);
    }
    try testing.expectEqualStrings("forge", toolForLegacyLabel("forge: github.com"));
    try testing.expectEqualStrings("git", toolForLegacyLabel("Git: https://github.com/"));
}

test "tool names" {
    try testing.expect(validTool("git"));
    try testing.expect(validTool("forge"));
    try testing.expect(validTool("hf"));
    try testing.expect(!validTool(""));
    try testing.expect(!validTool("Git"));
    try testing.expect(!validTool("a b"));
    const too_long: [max_tool_len + 1]u8 = @splat('a');
    try testing.expect(!validTool(&too_long));
}

test "secret text matches the stock helper format" {
    const gpa = testing.allocator;
    const cases = [_]struct { pw: []const u8, exp: ?i64, tok: ?[]const u8, want: []const u8 }{
        .{ .pw = "hunter2", .exp = null, .tok = null, .want = "hunter2" },
        .{ .pw = "hunter2", .exp = 1684189401, .tok = null, .want = "hunter2\npassword_expiry_utc=1684189401" },
        .{ .pw = "hunter2", .exp = null, .tok = "xyzzy", .want = "hunter2\noauth_refresh_token=xyzzy" },
        .{
            .pw = "hunter2",
            .exp = 1684189401,
            .tok = "xyzzy",
            .want = "hunter2\npassword_expiry_utc=1684189401\noauth_refresh_token=xyzzy",
        },
        .{ .pw = "", .exp = null, .tok = null, .want = "" },
    };
    for (cases) |case| {
        const text = try encodeSecret(gpa, case.pw, case.exp, case.tok);
        defer wipeFree(gpa, text);
        try testing.expectEqualStrings(case.want, text);

        var s = try decodeSecret(gpa, text);
        defer s.deinit(gpa);
        try testing.expectEqualStrings(case.pw, s.password);
        try testing.expectEqual(case.exp, s.password_expiry_utc);
        if (case.tok) |tok| try testing.expectEqualStrings(tok, s.oauth_refresh_token.?) else try testing.expectEqual(null, s.oauth_refresh_token);
    }
}

test "decode secret like the stock helper" {
    const gpa = testing.allocator;
    var s = try decodeSecret(gpa, "pw\nunknown=1\noauth_refresh_token=a\npassword_expiry_utc=bad\noauth_refresh_token=b\n");
    defer s.deinit(gpa);
    try testing.expectEqualStrings("pw", s.password);
    try testing.expectEqual(null, s.password_expiry_utc);
    try testing.expectEqualStrings("b", s.oauth_refresh_token.?);
}

test "decode secret survives every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(gpa: Allocator) !void {
            var s = try decodeSecret(gpa, "pw\noauth_refresh_token=t");
            s.deinit(gpa);
        }
    }.run, .{});
}

test "write credential" {
    var buf: [256]u8 = undefined;
    var w: Writer = .fixed(&buf);
    try writeCredential(&w, .{ .username = "u", .password = "p", .password_expiry_utc = 42, .oauth_refresh_token = "t" });
    try testing.expectEqualStrings("username=u\npassword=p\npassword_expiry_utc=42\noauth_refresh_token=t\n", w.buffered());

    var w2: Writer = .fixed(&buf);
    try writeCredential(&w2, .{ .password = "p" });
    try testing.expectEqualStrings("password=p\n", w2.buffered());

    var w3: Writer = .fixed(&buf);
    try testing.expectError(error.Protocol, writeCredential(&w3, .{ .username = "u", .password = "a\nb" }));
    try testing.expectEqual(0, w3.buffered().len);
}

test "parse then write round trip" {
    const gpa = testing.allocator;
    const input = "protocol=https\nhost=h\nusername=u\npassword=p\npassword_expiry_utc=7\noauth_refresh_token=t\n\n";
    var req = try parseText(gpa, input);
    defer req.deinit(gpa);
    var buf: [256]u8 = undefined;
    var w: Writer = .fixed(&buf);
    try writeCredential(&w, .{
        .username = req.username,
        .password = req.password,
        .password_expiry_utc = req.password_expiry_utc,
        .oauth_refresh_token = req.oauth_refresh_token,
    });
    try testing.expectEqualStrings("username=u\npassword=p\npassword_expiry_utc=7\noauth_refresh_token=t\n", w.buffered());
}

test "fuzz parse" {
    try testing.fuzz({}, fuzzParse, .{ .corpus = &.{
        "protocol=https\nhost=example.test:443\nusername=u\npassword=p\n\n",
        "host=[::1]:22\npassword_expiry_utc=-1\n",
        "capability[]=authtype\nwwwauth[]=x\n\n",
    } });
}

fn fuzzParse(_: void, smith: *testing.Smith) anyerror!void {
    var buf: [1024]u8 = undefined;
    const len = smith.slice(&buf);
    var r: Reader = .fixed(buf[0..len]);
    var req = Request.parse(testing.allocator, &r, 512) catch return;
    defer req.deinit(testing.allocator);
    if (req.host) |h| try testing.expect(std.mem.findScalar(u8, h, '\n') == null);
    var set = try AttrSet.init(testing.allocator, req.target(), .{ .store = default_tool });
    defer set.deinit(testing.allocator);
    const label = try makeLabel(testing.allocator, req.target());
    defer testing.allocator.free(label);
    if (req.password) |pw| {
        const text = try encodeSecret(testing.allocator, pw, req.password_expiry_utc, req.oauth_refresh_token);
        defer wipeFree(testing.allocator, text);
        var s = try decodeSecret(testing.allocator, text);
        defer s.deinit(testing.allocator);
        try testing.expectEqualStrings(pw, s.password);
        try testing.expectEqual(req.password_expiry_utc, s.password_expiry_utc);
    }
}
