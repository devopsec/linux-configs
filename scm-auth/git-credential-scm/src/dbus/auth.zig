//! D-Bus SASL authentication: the `EXTERNAL` mechanism over a unix socket.
//!
//! Client: `\0AUTH EXTERNAL <hex(ascii decimal uid)>\r\n`, server: `OK <guid>`,
//! client: `BEGIN\r\n`. After `BEGIN` the stream carries D-Bus messages.

const std = @import("std");
const Io = std.Io;

/// Longest SASL line accepted from the server, including `\r\n`.
pub const max_line_len = 512;
/// The server GUID is 16 bytes, hex encoded.
pub const guid_len = 32;

pub const Error = error{
    /// The server refused EXTERNAL (`REJECTED`/`ERROR`).
    AuthRejected,
    /// Unexpected or malformed server line.
    Protocol,
    ReadFailed,
    WriteFailed,
};

/// The current process's real uid (Linux only).
pub fn currentUid() u32 {
    return std.os.linux.getuid();
}

/// Runs the handshake for `uid` and returns the server GUID in `guid`.
pub fn authenticate(r: *Io.Reader, w: *Io.Writer, uid: u32, guid: *[guid_len]u8) Error!void {
    var hex_buf: [hex_uid_len]u8 = undefined;
    const hex = hexUid(uid, &hex_buf);

    w.writeAll("\x00AUTH EXTERNAL ") catch return error.WriteFailed;
    w.writeAll(hex) catch return error.WriteFailed;
    w.writeAll("\r\n") catch return error.WriteFailed;
    w.flush() catch return error.WriteFailed;

    var line_buf: [max_line_len]u8 = undefined;
    const line = try readLine(r, &line_buf);
    if (std.mem.startsWith(u8, line, "OK ")) {
        const g = line["OK ".len..];
        if (g.len != guid_len) return error.Protocol;
        for (g) |c| if (!std.ascii.isHex(c)) return error.Protocol;
        @memcpy(guid, g);
    } else if (std.mem.eql(u8, line, "REJECTED") or std.mem.startsWith(u8, line, "REJECTED ") or
        std.mem.eql(u8, line, "ERROR") or std.mem.startsWith(u8, line, "ERROR "))
    {
        // Be polite: end the conversation; the caller closes the socket.
        return error.AuthRejected;
    } else {
        return error.Protocol;
    }

    w.writeAll("BEGIN\r\n") catch return error.WriteFailed;
    w.flush() catch return error.WriteFailed;
}

const hex_uid_len = 2 * 10; // u32 has at most 10 decimal digits

/// Hex encoding of the ASCII decimal form of `uid` (EXTERNAL's identity).
fn hexUid(uid: u32, buf: *[hex_uid_len]u8) []const u8 {
    var digits: [10]u8 = undefined;
    var n: usize = 0;
    var v = uid;
    while (true) {
        digits[digits.len - 1 - n] = '0' + @as(u8, @intCast(v % 10));
        n += 1;
        v /= 10;
        if (v == 0) break;
    }
    const charset = "0123456789abcdef";
    for (digits[digits.len - n ..], 0..) |d, i| {
        buf[2 * i] = charset[d >> 4];
        buf[2 * i + 1] = charset[d & 0xf];
    }
    return buf[0 .. 2 * n];
}

/// Reads one `\r\n`-terminated line (without the terminator) into `buf`.
fn readLine(r: *Io.Reader, buf: *[max_line_len]u8) Error![]const u8 {
    var len: usize = 0;
    while (true) {
        const c = r.takeByte() catch |err| switch (err) {
            error.EndOfStream => return error.Protocol,
            error.ReadFailed => return error.ReadFailed,
        };
        if (c == '\n') {
            if (len == 0 or buf[len - 1] != '\r') return error.Protocol;
            return buf[0 .. len - 1];
        }
        if (len == buf.len) return error.Protocol;
        // SASL lines are ASCII; anything else is a confused peer.
        if (c == 0 or c > 0x7e) return error.Protocol;
        buf[len] = c;
        len += 1;
    }
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn runAuth(server: []const u8, uid: u32, out: []u8, guid: *[guid_len]u8) !usize {
    var r: Io.Reader = .fixed(server);
    var w: Io.Writer = .fixed(out);
    try authenticate(&r, &w, uid, guid);
    return w.buffered().len;
}

test "EXTERNAL handshake" {
    var out: [128]u8 = undefined;
    var guid: [guid_len]u8 = undefined;
    const n = try runAuth("OK 0123456789abcdef0123456789ABCDEF\r\n", 1000, &out, &guid);
    try testing.expectEqualStrings("\x00AUTH EXTERNAL 31303030\r\nBEGIN\r\n", out[0..n]);
    try testing.expectEqualStrings("0123456789abcdef0123456789ABCDEF", &guid);

    const n0 = try runAuth("OK 0123456789abcdef0123456789abcdef\r\n", 0, &out, &guid);
    try testing.expectEqualStrings("\x00AUTH EXTERNAL 30\r\nBEGIN\r\n", out[0..n0]);

    const nmax = try runAuth("OK 0123456789abcdef0123456789abcdef\r\n", std.math.maxInt(u32), &out, &guid);
    try testing.expectEqualStrings("\x00AUTH EXTERNAL 34323934393637323935\r\nBEGIN\r\n", out[0..nmax]);
}

test "EXTERNAL handshake errors" {
    var out: [128]u8 = undefined;
    var guid: [guid_len]u8 = undefined;
    try testing.expectError(error.AuthRejected, runAuth("REJECTED EXTERNAL DBUS_COOKIE_SHA1\r\n", 1, &out, &guid));
    try testing.expectError(error.AuthRejected, runAuth("ERROR\r\n", 1, &out, &guid));
    try testing.expectError(error.Protocol, runAuth("OK 0123\r\n", 1, &out, &guid));
    try testing.expectError(error.Protocol, runAuth("OK 0123456789abcdef0123456789abcdeg\r\n", 1, &out, &guid));
    try testing.expectError(error.Protocol, runAuth("OK 0123456789abcdef0123456789abcdef\n", 1, &out, &guid));
    try testing.expectError(error.Protocol, runAuth("OK 0123456789abcdef", 1, &out, &guid));
    try testing.expectError(error.Protocol, runAuth("", 1, &out, &guid));
    try testing.expectError(error.Protocol, runAuth("DATA\r\n", 1, &out, &guid));
    const long: [max_line_len + 8]u8 = @splat('A');
    try testing.expectError(error.Protocol, runAuth(&long, 1, &out, &guid));
    var tiny: [4]u8 = undefined;
    try testing.expectError(error.WriteFailed, runAuth("OK x\r\n", 1, &tiny, &guid));
}
