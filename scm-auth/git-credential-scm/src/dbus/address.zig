//! D-Bus server address parsing (`DBUS_SESSION_BUS_ADDRESS`).
//!
//! Only `unix:path=<socket>` is supported; other transports (`unix:abstract=`,
//! `tcp:`, `launchd:`, ...) are reported as `error.UnsupportedAddress`.
//! Addresses may be a `;`-separated list: the first `unix:path=` entry wins.

const std = @import("std");

/// Longest socket path accepted (`sockaddr_un.sun_path` without the NUL).
pub const max_path_len = std.Io.net.UnixAddress.max_len - 1;

pub const Error = error{
    /// The address is unset or empty.
    NoSessionBus,
    /// Only non-`unix:path=` transports are listed.
    UnsupportedAddress,
    /// Malformed escapes, missing path, path too long or containing NUL.
    InvalidAddress,
};

/// Returns the unescaped socket path of the first `unix:path=` entry of
/// `address`, written into `buf`.
pub fn parseUnixPath(address: []const u8, buf: *[max_path_len]u8) Error![]const u8 {
    var result: Error = error.NoSessionBus;
    var entries = std.mem.splitScalar(u8, address, ';');
    while (entries.next()) |entry| {
        if (entry.len == 0) continue;
        const path = parseEntry(entry, buf) catch |err| {
            // A malformed unix entry is a stronger signal than a foreign one.
            if (err == error.InvalidAddress or result == error.NoSessionBus) result = err;
            continue;
        };
        return path;
    }
    return result;
}

fn parseEntry(entry: []const u8, buf: *[max_path_len]u8) Error![]const u8 {
    const colon = std.mem.findScalar(u8, entry, ':') orelse return error.InvalidAddress;
    if (!std.mem.eql(u8, entry[0..colon], "unix")) return error.UnsupportedAddress;
    var path: ?[]const u8 = null;
    var params = std.mem.splitScalar(u8, entry[colon + 1 ..], ',');
    while (params.next()) |param| {
        if (param.len == 0) continue;
        const eq = std.mem.findScalar(u8, param, '=') orelse return error.InvalidAddress;
        const key = param[0..eq];
        const value = param[eq + 1 ..];
        if (std.mem.eql(u8, key, "path")) {
            if (path != null) return error.InvalidAddress;
            path = try unescape(value, buf);
        } else if (std.mem.eql(u8, key, "guid")) {
            // Identifies the server; nothing to check before connecting.
        } else if (std.mem.eql(u8, key, "abstract") or std.mem.eql(u8, key, "dir") or
            std.mem.eql(u8, key, "tmpdir") or std.mem.eql(u8, key, "runtime"))
        {
            return error.UnsupportedAddress;
        } else {
            return error.InvalidAddress;
        }
    }
    return path orelse error.InvalidAddress;
}

/// Percent-unescapes `value` into `buf` per the D-Bus address syntax.
fn unescape(value: []const u8, buf: *[max_path_len]u8) Error![]const u8 {
    var len: usize = 0;
    var i: usize = 0;
    while (i < value.len) : (len += 1) {
        if (len == buf.len) return error.InvalidAddress;
        var c = value[i];
        if (c == '%') {
            if (value.len - i < 3) return error.InvalidAddress;
            const hex = value[i + 1 .. i + 3];
            if (!std.ascii.isHex(hex[0]) or !std.ascii.isHex(hex[1])) return error.InvalidAddress;
            c = std.fmt.parseInt(u8, hex, 16) catch return error.InvalidAddress;
            i += 3;
        } else {
            i += 1;
        }
        if (c == 0) return error.InvalidAddress;
        buf[len] = c;
    }
    if (len == 0) return error.InvalidAddress;
    return buf[0..len];
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "unix:path addresses" {
    var buf: [max_path_len]u8 = undefined;
    try testing.expectEqualStrings("/run/user/1000/bus", try parseUnixPath("unix:path=/run/user/1000/bus", &buf));
    try testing.expectEqualStrings("/tmp/a b", try parseUnixPath("unix:path=/tmp/a%20b,guid=0123456789abcdef0123456789abcdef", &buf));
    try testing.expectEqualStrings("/x/y", try parseUnixPath("unix:guid=00,path=%2fx%2Fy", &buf));
    try testing.expectEqualStrings("/s", try parseUnixPath("unix:abstract=/tmp/dbus-x;unix:path=/s", &buf));
    try testing.expectEqualStrings("/s", try parseUnixPath(";tcp:host=localhost,port=1;unix:path=/s;", &buf));
}

test "address errors" {
    var buf: [max_path_len]u8 = undefined;
    try testing.expectError(error.NoSessionBus, parseUnixPath("", &buf));
    try testing.expectError(error.NoSessionBus, parseUnixPath(";;", &buf));
    try testing.expectError(error.UnsupportedAddress, parseUnixPath("unix:abstract=/tmp/dbus-x", &buf));
    try testing.expectError(error.UnsupportedAddress, parseUnixPath("tcp:host=localhost,port=1", &buf));
    try testing.expectError(error.UnsupportedAddress, parseUnixPath("unix:runtime=yes", &buf));
    try testing.expectError(error.UnsupportedAddress, parseUnixPath("launchd:env=X", &buf));
    try testing.expectError(error.InvalidAddress, parseUnixPath("unix:path=", &buf));
    try testing.expectError(error.InvalidAddress, parseUnixPath("unix:guid=00", &buf));
    try testing.expectError(error.InvalidAddress, parseUnixPath("unix:path=/a%2", &buf));
    try testing.expectError(error.InvalidAddress, parseUnixPath("unix:path=/a%zz", &buf));
    try testing.expectError(error.InvalidAddress, parseUnixPath("unix:path=/a%00b", &buf));
    try testing.expectError(error.InvalidAddress, parseUnixPath("unix:path=/a,path=/b", &buf));
    try testing.expectError(error.InvalidAddress, parseUnixPath("unix:path", &buf));
    try testing.expectError(error.InvalidAddress, parseUnixPath("unix:bogus=1,path=/a", &buf));
    try testing.expectError(error.InvalidAddress, parseUnixPath("unixpath=/a", &buf));
    // A malformed unix entry wins over an unsupported one.
    try testing.expectError(error.InvalidAddress, parseUnixPath("tcp:host=h;unix:path=", &buf));
    const long: [max_path_len + 1]u8 = @splat('a');
    try testing.expectError(error.InvalidAddress, parseUnixPath("unix:path=" ++ long, &buf));
    const max: [max_path_len]u8 = @splat('b');
    try testing.expectEqual(max_path_len, (try parseUnixPath("unix:path=" ++ max, &buf)).len);
}
