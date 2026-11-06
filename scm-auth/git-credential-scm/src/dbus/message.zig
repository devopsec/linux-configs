//! D-Bus wire format: signatures, values, message encoding and decoding.
//!
//! Encoding is little-endian only; decoding accepts both byte orders. All
//! lengths and offsets read from the wire are bounds-checked: malformed input
//! yields `error.Protocol`, never a panic. Decoded strings and byte arrays are
//! slices into the message buffer, which `Message.deinit` wipes.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Endian = std.builtin.Endian;

/// Spec limit for a whole message (header, padding and body).
pub const max_message_len: u32 = 128 * 1024 * 1024;
/// Spec limit for the byte length of a single array.
pub const max_array_len: u32 = 64 * 1024 * 1024;
pub const max_signature_len = 255;
/// Combined nesting limit for arrays, structs, dict entries and variants.
pub const max_depth = 32;
/// Upper bound on decoded values per message, to bound memory use.
pub const max_values = 1 << 20;
/// Bytes needed to compute a message's total length (see `messageLength`).
pub const prefix_len = 16;

pub const Error = error{ Protocol, OutOfMemory };
pub const EncodeError = error{ InvalidValue, MessageTooLong, OutOfMemory };

pub const MessageType = enum(u8) {
    method_call = 1,
    method_return = 2,
    error_reply = 3,
    signal = 4,
    _,
};

pub const flag_no_reply_expected: u8 = 0x1;
pub const flag_no_auto_start: u8 = 0x2;
pub const flag_allow_interactive_authorization: u8 = 0x4;

pub const Variant = struct {
    /// A single complete type.
    signature: []const u8,
    value: *const Value,
};

pub const Array = struct {
    /// Element signature (a single complete type, never `y`: see `Value.bytes`).
    signature: []const u8,
    items: []const Value,
};

pub const Value = union(enum) {
    byte: u8,
    boolean: bool,
    int16: i16,
    uint16: u16,
    int32: i32,
    uint32: u32,
    int64: i64,
    uint64: u64,
    double: f64,
    string: []const u8,
    object_path: []const u8,
    signature: []const u8,
    variant: Variant,
    /// `ay`.
    bytes: []const u8,
    /// Any other array, including dicts (`a{..}`).
    array: Array,
    structure: []const Value,
    dict_entry: *const [2]Value,

    pub fn asString(v: Value) ?[]const u8 {
        return switch (v) {
            .string, .object_path, .signature => |s| s,
            else => null,
        };
    }

    pub fn asBytes(v: Value) ?[]const u8 {
        return if (v == .bytes) v.bytes else null;
    }

    pub fn asBool(v: Value) ?bool {
        return if (v == .boolean) v.boolean else null;
    }

    pub fn asU32(v: Value) ?u32 {
        return if (v == .uint32) v.uint32 else null;
    }

    pub fn asU64(v: Value) ?u64 {
        return if (v == .uint64) v.uint64 else null;
    }

    pub fn asArray(v: Value) ?[]const Value {
        return if (v == .array) v.array.items else null;
    }

    pub fn asStruct(v: Value) ?[]const Value {
        return if (v == .structure) v.structure else null;
    }

    /// The contents of a variant (or `v` itself if it is not one).
    pub fn unwrap(v: Value) Value {
        return if (v == .variant) v.variant.value.* else v;
    }

    /// Looks up `key` in a dict with string-like keys (`a{s..}`, `a{o..}`).
    pub fn dictGet(v: Value, key: []const u8) ?Value {
        const items = v.asArray() orelse return null;
        for (items) |item| {
            if (item != .dict_entry) return null;
            const k = item.dict_entry[0].asString() orelse return null;
            if (std.mem.eql(u8, k, key)) return item.dict_entry[1];
        }
        return null;
    }

    /// Deep structural equality (doubles compare by bit pattern).
    pub fn eql(a: Value, b: Value) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .byte => |x| x == b.byte,
            .boolean => |x| x == b.boolean,
            .int16 => |x| x == b.int16,
            .uint16 => |x| x == b.uint16,
            .int32 => |x| x == b.int32,
            .uint32 => |x| x == b.uint32,
            .int64 => |x| x == b.int64,
            .uint64 => |x| x == b.uint64,
            .double => |x| @as(u64, @bitCast(x)) == @as(u64, @bitCast(b.double)),
            .string => |x| std.mem.eql(u8, x, b.string),
            .object_path => |x| std.mem.eql(u8, x, b.object_path),
            .signature => |x| std.mem.eql(u8, x, b.signature),
            .bytes => |x| std.mem.eql(u8, x, b.bytes),
            .variant => |x| std.mem.eql(u8, x.signature, b.variant.signature) and x.value.eql(b.variant.value.*),
            .array => |x| std.mem.eql(u8, x.signature, b.array.signature) and eqlSlice(x.items, b.array.items),
            .structure => |x| eqlSlice(x, b.structure),
            .dict_entry => |x| x[0].eql(b.dict_entry[0]) and x[1].eql(b.dict_entry[1]),
        };
    }

    fn eqlSlice(a: []const Value, b: []const Value) bool {
        if (a.len != b.len) return false;
        for (a, b) |x, y| if (!x.eql(y)) return false;
        return true;
    }
};

// ---------------------------------------------------------------- signatures

fn isBasic(c: u8) bool {
    return switch (c) {
        'y', 'b', 'n', 'q', 'i', 'u', 'x', 't', 'd', 's', 'o', 'g' => true,
        else => false,
    };
}

fn alignOf(c: u8) usize {
    return switch (c) {
        'n', 'q' => 2,
        'b', 'i', 'u', 's', 'o', 'a' => 4,
        'x', 't', 'd', '(', '{' => 8,
        else => 1, // y g v
    };
}

/// Length of the single complete type at the start of `sig`. Unix fds (`h`)
/// are not supported and rejected.
fn typeLen(sig: []const u8, depth: usize, in_array: bool) Error!usize {
    if (sig.len == 0 or depth > max_depth) return error.Protocol;
    switch (sig[0]) {
        'y', 'b', 'n', 'q', 'i', 'u', 'x', 't', 'd', 's', 'o', 'g', 'v' => return 1,
        'a' => return 1 + try typeLen(sig[1..], depth + 1, true),
        '(' => {
            var i: usize = 1;
            while (true) {
                if (i >= sig.len) return error.Protocol;
                if (sig[i] == ')') break;
                i += try typeLen(sig[i..], depth + 1, false);
            }
            if (i == 1) return error.Protocol;
            return i + 1;
        },
        '{' => {
            if (!in_array or sig.len < 2 or !isBasic(sig[1])) return error.Protocol;
            const i = 2 + try typeLen(sig[2..], depth + 1, false);
            if (i >= sig.len or sig[i] != '}') return error.Protocol;
            return i + 1;
        },
        else => return error.Protocol,
    }
}

/// Validates a (possibly empty) sequence of complete types.
pub fn validateSignature(sig: []const u8) Error!void {
    if (sig.len > max_signature_len) return error.Protocol;
    var i: usize = 0;
    while (i < sig.len) i += try typeLen(sig[i..], 0, false);
}

/// True if `sig` is exactly one valid complete type.
pub fn isSingleType(sig: []const u8) bool {
    if (sig.len > max_signature_len) return false;
    const n = typeLen(sig, 0, false) catch return false;
    return n == sig.len;
}

/// Object path syntax: `/` or `/elem(/elem)*` with elements of `[A-Za-z0-9_]+`.
pub fn validObjectPath(p: []const u8) bool {
    if (p.len == 0 or p[0] != '/') return false;
    if (p.len == 1) return true;
    if (p[p.len - 1] == '/') return false;
    var prev_slash = true;
    for (p[1..]) |c| {
        if (c == '/') {
            if (prev_slash) return false;
            prev_slash = true;
        } else if (std.ascii.isAlphanumeric(c) or c == '_') {
            prev_slash = false;
        } else return false;
    }
    return true;
}

// ---------------------------------------------------------------- decoding

const Decoder = struct {
    buf: []const u8,
    pos: usize,
    end: usize,
    endian: Endian,
    arena: Allocator,
    values: usize = 0,

    fn alignTo(d: *Decoder, a: usize) Error!void {
        const padded = std.mem.alignForward(usize, d.pos, a);
        if (padded > d.end) return error.Protocol;
        for (d.buf[d.pos..padded]) |b| if (b != 0) return error.Protocol;
        d.pos = padded;
    }

    fn take(d: *Decoder, n: usize) Error![]const u8 {
        if (n > d.end - d.pos) return error.Protocol;
        const s = d.buf[d.pos..][0..n];
        d.pos += n;
        return s;
    }

    fn int(d: *Decoder, comptime T: type) Error!T {
        const size = @sizeOf(T);
        try d.alignTo(size);
        const s = try d.take(size);
        return std.mem.readInt(T, s[0..size], d.endian);
    }

    fn string(d: *Decoder) Error![]const u8 {
        const len = try d.int(u32);
        const s = try d.take(len);
        if ((try d.take(1))[0] != 0) return error.Protocol;
        if (std.mem.findScalar(u8, s, 0) != null) return error.Protocol;
        return s;
    }

    fn signature(d: *Decoder) Error![]const u8 {
        const len = (try d.take(1))[0];
        const s = try d.take(len);
        if ((try d.take(1))[0] != 0) return error.Protocol;
        try validateSignature(s);
        return s;
    }

    /// Decodes one value of the single complete type `sig`.
    fn value(d: *Decoder, sig: []const u8, depth: usize) Error!Value {
        if (depth > max_depth) return error.Protocol;
        d.values += 1;
        if (d.values > max_values) return error.Protocol;
        return switch (sig[0]) {
            'y' => .{ .byte = (try d.take(1))[0] },
            'b' => switch (try d.int(u32)) {
                0 => .{ .boolean = false },
                1 => .{ .boolean = true },
                else => error.Protocol,
            },
            'n' => .{ .int16 = try d.int(i16) },
            'q' => .{ .uint16 = try d.int(u16) },
            'i' => .{ .int32 = try d.int(i32) },
            'u' => .{ .uint32 = try d.int(u32) },
            'x' => .{ .int64 = try d.int(i64) },
            't' => .{ .uint64 = try d.int(u64) },
            'd' => .{ .double = @bitCast(try d.int(u64)) },
            's' => .{ .string = try d.string() },
            'o' => blk: {
                const p = try d.string();
                if (!validObjectPath(p)) return error.Protocol;
                break :blk .{ .object_path = p };
            },
            'g' => .{ .signature = try d.signature() },
            'v' => blk: {
                const s = try d.signature();
                if ((try typeLen(s, depth + 1, false)) != s.len) return error.Protocol;
                const inner = try d.arena.create(Value);
                inner.* = try d.value(s, depth + 1);
                break :blk .{ .variant = .{ .signature = s, .value = inner } };
            },
            'a' => blk: {
                const elem = sig[1..];
                const len = try d.int(u32);
                if (len > max_array_len) return error.Protocol;
                try d.alignTo(alignOf(elem[0]));
                if (len > d.end - d.pos) return error.Protocol;
                if (elem[0] == 'y') break :blk .{ .bytes = try d.take(len) };
                const saved_end = d.end;
                d.end = d.pos + len;
                var items: std.ArrayList(Value) = .empty;
                while (d.pos < d.end) try items.append(d.arena, try d.value(elem, depth + 1));
                d.end = saved_end;
                break :blk .{ .array = .{ .signature = elem, .items = try items.toOwnedSlice(d.arena) } };
            },
            '(' => blk: {
                try d.alignTo(8);
                var items: std.ArrayList(Value) = .empty;
                var i: usize = 1;
                while (sig[i] != ')') {
                    const n = try typeLen(sig[i..], depth + 1, false);
                    try items.append(d.arena, try d.value(sig[i..][0..n], depth + 1));
                    i += n;
                }
                break :blk .{ .structure = try items.toOwnedSlice(d.arena) };
            },
            '{' => blk: {
                try d.alignTo(8);
                const pair = try d.arena.create([2]Value);
                pair[0] = try d.value(sig[1..2], depth + 1);
                pair[1] = try d.value(sig[2 .. sig.len - 1], depth + 1);
                break :blk .{ .dict_entry = pair };
            },
            else => error.Protocol,
        };
    }

    /// Decodes values for every complete type in the validated `sig`.
    fn values_(d: *Decoder, sig: []const u8) Error![]const Value {
        var items: std.ArrayList(Value) = .empty;
        var i: usize = 0;
        while (i < sig.len) {
            const n = try typeLen(sig[i..], 0, false);
            try items.append(d.arena, try d.value(sig[i..][0..n], 0));
            i += n;
        }
        return items.toOwnedSlice(d.arena);
    }
};

/// Decodes a standalone body (alignment relative to `bytes[0]`), which must be
/// consumed exactly. Values reference `bytes` and `arena`.
pub fn decodeBody(arena: Allocator, sig: []const u8, bytes: []const u8, endian: Endian) Error![]const Value {
    try validateSignature(sig);
    var d: Decoder = .{ .buf = bytes, .pos = 0, .end = bytes.len, .endian = endian, .arena = arena };
    const vals = try d.values_(sig);
    if (d.pos != bytes.len) return error.Protocol;
    return vals;
}

pub const Header = struct {
    type: MessageType,
    flags: u8 = 0,
    serial: u32 = 0,
    path: ?[]const u8 = null,
    interface: ?[]const u8 = null,
    member: ?[]const u8 = null,
    error_name: ?[]const u8 = null,
    reply_serial: ?u32 = null,
    destination: ?[]const u8 = null,
    sender: ?[]const u8 = null,
    /// Body signature.
    signature: []const u8 = "",
};

const Field = enum(u8) {
    path = 1,
    interface = 2,
    member = 3,
    error_name = 4,
    reply_serial = 5,
    destination = 6,
    sender = 7,
    signature = 8,
    unix_fds = 9,
    _,
};

/// A decoded message. Owns `raw` (wiped on deinit) and the value arena.
pub const Message = struct {
    raw: []u8,
    arena: std.heap.ArenaAllocator,
    header: Header,
    body: []const Value,
    /// Offset of the body in `raw`.
    body_offset: usize,

    pub fn deinit(m: *Message, gpa: Allocator) void {
        std.crypto.secureZero(u8, m.raw);
        gpa.free(m.raw);
        m.arena.deinit();
        m.* = undefined;
    }
};

/// Total message length from its first `prefix_len` bytes, after checking the
/// byte order, protocol version and size limits.
pub fn messageLength(prefix: *const [prefix_len]u8) Error!usize {
    const endian = try endianOf(prefix[0]);
    if (prefix[3] != 1) return error.Protocol;
    const body_len = std.mem.readInt(u32, prefix[4..8], endian);
    const fields_len = std.mem.readInt(u32, prefix[12..16], endian);
    if (fields_len > max_array_len or body_len > max_message_len) return error.Protocol;
    const header_len = std.mem.alignForward(usize, prefix_len + @as(usize, fields_len), 8);
    const total = header_len + @as(usize, body_len);
    if (total > max_message_len) return error.Protocol;
    return total;
}

fn endianOf(c: u8) Error!Endian {
    return switch (c) {
        'l' => .little,
        'B' => .big,
        else => error.Protocol,
    };
}

/// Parses a complete message. Takes ownership of `raw` (allocated with `gpa`)
/// in all cases: on error it is wiped and freed.
pub fn parse(gpa: Allocator, raw: []u8) Error!Message {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    errdefer {
        arena.deinit();
        std.crypto.secureZero(u8, raw);
        gpa.free(raw);
    }
    if (raw.len < prefix_len) return error.Protocol;
    if (try messageLength(raw[0..prefix_len]) != raw.len) return error.Protocol;
    const endian = try endianOf(raw[0]);
    const fields_len = std.mem.readInt(u32, raw[12..16], endian);
    var h: Header = .{
        .type = @fromBackingInt(@intCast(raw[1])),
        .flags = raw[2],
        .serial = std.mem.readInt(u32, raw[8..12], endian),
    };
    if (h.serial == 0) return error.Protocol;

    var d: Decoder = .{
        .buf = raw,
        .pos = prefix_len,
        .end = prefix_len + @as(usize, fields_len),
        .endian = endian,
        .arena = arena.allocator(),
    };
    while (d.pos < d.end) {
        try d.alignTo(8);
        const code: Field = @fromBackingInt(@intCast((try d.take(1))[0]));
        const sig = try d.signature();
        if (!isSingleType(sig)) return error.Protocol;
        const v = try d.value(sig, 1);
        switch (code) {
            .path => h.path = if (v == .object_path) v.object_path else return error.Protocol,
            .interface => h.interface = if (v == .string) v.string else return error.Protocol,
            .member => h.member = if (v == .string) v.string else return error.Protocol,
            .error_name => h.error_name = if (v == .string) v.string else return error.Protocol,
            .destination => h.destination = if (v == .string) v.string else return error.Protocol,
            .sender => h.sender = if (v == .string) v.string else return error.Protocol,
            .signature => h.signature = if (v == .signature) v.signature else return error.Protocol,
            .reply_serial => {
                const s = v.asU32() orelse return error.Protocol;
                if (s == 0) return error.Protocol;
                h.reply_serial = s;
            },
            // No fd passing: a message announcing fds cannot be handled.
            .unix_fds => if ((v.asU32() orelse return error.Protocol) != 0) return error.Protocol,
            _ => if (@backingInt(code) == 0) return error.Protocol,
        }
    }
    d.end = std.mem.alignForward(usize, d.pos, 8);
    try d.alignTo(8);

    switch (h.type) {
        .method_call => if (h.path == null or h.member == null) return error.Protocol,
        .signal => if (h.path == null or h.interface == null or h.member == null) return error.Protocol,
        .error_reply => if (h.error_name == null or h.reply_serial == null) return error.Protocol,
        .method_return => if (h.reply_serial == null) return error.Protocol,
        _ => {},
    }

    const body_offset = d.pos;
    d.end = raw.len;
    if (h.signature.len == 0 and body_offset != raw.len) return error.Protocol;
    const body = try d.values_(h.signature);
    if (d.pos != raw.len) return error.Protocol;
    return .{ .raw = raw, .arena = arena, .header = h, .body = body, .body_offset = body_offset };
}

// ---------------------------------------------------------------- encoding

/// Two-pass encoder: with `out == null` it only measures, so the real buffer
/// can be allocated at its exact size (no reallocation copies of secrets).
const Encoder = struct {
    out: ?[]u8 = null,
    pos: usize = 0,

    fn pad(e: *Encoder, a: usize) void {
        const p = std.mem.alignForward(usize, e.pos, a);
        if (e.out) |o| @memset(o[e.pos..p], 0);
        e.pos = p;
    }

    fn bytes(e: *Encoder, b: []const u8) EncodeError!void {
        if (b.len > max_message_len - @min(e.pos, max_message_len)) return error.MessageTooLong;
        if (e.out) |o| @memcpy(o[e.pos..][0..b.len], b);
        e.pos += b.len;
    }

    fn int(e: *Encoder, comptime T: type, v: T) EncodeError!void {
        e.pad(@sizeOf(T));
        var tmp: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &tmp, v, .little);
        try e.bytes(&tmp);
    }

    fn patchU32(e: *Encoder, at: usize, v: u32) void {
        if (e.out) |o| std.mem.writeInt(u32, o[at..][0..4], v, .little);
    }

    fn string(e: *Encoder, s: []const u8) EncodeError!void {
        if (s.len > max_message_len or std.mem.findScalar(u8, s, 0) != null) return error.InvalidValue;
        try e.int(u32, @intCast(s.len));
        try e.bytes(s);
        try e.bytes("\x00");
    }

    fn signature(e: *Encoder, s: []const u8) EncodeError!void {
        validateSignature(s) catch return error.InvalidValue;
        try e.bytes(&.{@intCast(s.len)});
        try e.bytes(s);
        try e.bytes("\x00");
    }

    fn value(e: *Encoder, sig: []const u8, v: Value, depth: usize) EncodeError!void {
        if (depth > max_depth) return error.InvalidValue;
        switch (sig[0]) {
            'y' => try e.bytes(&.{if (v == .byte) v.byte else return error.InvalidValue}),
            'b' => try e.int(u32, @intFromBool(if (v == .boolean) v.boolean else return error.InvalidValue)),
            'n' => try e.int(i16, if (v == .int16) v.int16 else return error.InvalidValue),
            'q' => try e.int(u16, if (v == .uint16) v.uint16 else return error.InvalidValue),
            'i' => try e.int(i32, if (v == .int32) v.int32 else return error.InvalidValue),
            'u' => try e.int(u32, if (v == .uint32) v.uint32 else return error.InvalidValue),
            'x' => try e.int(i64, if (v == .int64) v.int64 else return error.InvalidValue),
            't' => try e.int(u64, if (v == .uint64) v.uint64 else return error.InvalidValue),
            'd' => try e.int(u64, @bitCast(if (v == .double) v.double else return error.InvalidValue)),
            's' => try e.string(if (v == .string) v.string else return error.InvalidValue),
            'o' => {
                if (v != .object_path or !validObjectPath(v.object_path)) return error.InvalidValue;
                try e.string(v.object_path);
            },
            'g' => try e.signature(if (v == .signature) v.signature else return error.InvalidValue),
            'v' => {
                if (v != .variant or !isSingleType(v.variant.signature)) return error.InvalidValue;
                try e.signature(v.variant.signature);
                try e.value(v.variant.signature, v.variant.value.*, depth + 1);
            },
            'a' => {
                const elem = sig[1..];
                if (elem[0] == 'y') {
                    if (v != .bytes or v.bytes.len > max_array_len) return error.InvalidValue;
                    try e.int(u32, @intCast(v.bytes.len));
                    try e.bytes(v.bytes);
                    return;
                }
                if (v != .array or !std.mem.eql(u8, v.array.signature, elem)) return error.InvalidValue;
                try e.int(u32, 0);
                const len_at = e.pos - 4;
                e.pad(alignOf(elem[0]));
                const start = e.pos;
                for (v.array.items) |item| try e.value(elem, item, depth + 1);
                const len = e.pos - start;
                if (len > max_array_len) return error.MessageTooLong;
                e.patchU32(len_at, @intCast(len));
            },
            '(' => {
                if (v != .structure) return error.InvalidValue;
                e.pad(8);
                var i: usize = 1;
                var n_items: usize = 0;
                while (sig[i] != ')') : (n_items += 1) {
                    const n = typeLen(sig[i..], 0, false) catch return error.InvalidValue;
                    if (n_items >= v.structure.len) return error.InvalidValue;
                    try e.value(sig[i..][0..n], v.structure[n_items], depth + 1);
                    i += n;
                }
                if (n_items != v.structure.len) return error.InvalidValue;
            },
            '{' => {
                if (v != .dict_entry) return error.InvalidValue;
                e.pad(8);
                try e.value(sig[1..2], v.dict_entry[0], depth + 1);
                try e.value(sig[2 .. sig.len - 1], v.dict_entry[1], depth + 1);
            },
            else => return error.InvalidValue,
        }
    }

    fn values_(e: *Encoder, sig: []const u8, vals: []const Value) EncodeError!void {
        validateSignature(sig) catch return error.InvalidValue;
        var i: usize = 0;
        var k: usize = 0;
        while (i < sig.len) : (k += 1) {
            const n = typeLen(sig[i..], 0, false) catch return error.InvalidValue;
            if (k >= vals.len) return error.InvalidValue;
            try e.value(sig[i..][0..n], vals[k], 0);
            i += n;
        }
        if (k != vals.len) return error.InvalidValue;
    }

    fn field(e: *Encoder, code: Field, sig: u8, v: Value) EncodeError!void {
        e.pad(8);
        try e.bytes(&.{ @backingInt(code), 1, sig, 0 });
        try e.value(&.{sig}, v, 1);
    }

    fn message(e: *Encoder, h: Header, body_len: usize, body: []const Value) EncodeError!usize {
        try e.bytes(&.{ 'l', @backingInt(h.type), h.flags, 1 });
        try e.int(u32, @intCast(@min(body_len, max_message_len)));
        try e.int(u32, h.serial);
        try e.int(u32, 0);
        if (h.path) |p| try e.field(.path, 'o', .{ .object_path = p });
        if (h.interface) |s| try e.field(.interface, 's', .{ .string = s });
        if (h.member) |s| try e.field(.member, 's', .{ .string = s });
        if (h.error_name) |s| try e.field(.error_name, 's', .{ .string = s });
        if (h.reply_serial) |s| try e.field(.reply_serial, 'u', .{ .uint32 = s });
        if (h.destination) |s| try e.field(.destination, 's', .{ .string = s });
        if (h.sender) |s| try e.field(.sender, 's', .{ .string = s });
        if (h.signature.len > 0) try e.field(.signature, 'g', .{ .signature = h.signature });
        e.patchU32(12, @intCast(e.pos - prefix_len));
        e.pad(8);
        const header_len = e.pos;
        try e.values_(h.signature, body);
        return header_len;
    }
};

/// Encodes a standalone body. Caller owns the result (wipe it if it may
/// hold secrets).
pub fn encodeBody(gpa: Allocator, sig: []const u8, vals: []const Value) EncodeError![]u8 {
    var measure: Encoder = .{};
    try measure.values_(sig, vals);
    const out = try gpa.alloc(u8, measure.pos);
    var e: Encoder = .{ .out = out };
    e.values_(sig, vals) catch unreachable; // same input as the measuring pass
    return out;
}

/// Encodes a little-endian message. Caller owns the result (wipe it if it
/// may hold secrets).
pub fn encodeMessage(gpa: Allocator, h: Header, body: []const Value) EncodeError![]u8 {
    if (h.serial == 0) return error.InvalidValue;
    switch (h.type) {
        .method_call => if (h.path == null or h.member == null) return error.InvalidValue,
        .signal => if (h.path == null or h.interface == null or h.member == null) return error.InvalidValue,
        .error_reply => if (h.error_name == null or h.reply_serial == null) return error.InvalidValue,
        .method_return => if (h.reply_serial == null) return error.InvalidValue,
        _ => return error.InvalidValue,
    }
    var measure: Encoder = .{};
    const header_len = try measure.message(h, 0, body);
    const total = measure.pos;
    if (total > max_message_len) return error.MessageTooLong;
    const out = try gpa.alloc(u8, total);
    var e: Encoder = .{ .out = out };
    _ = e.message(h, total - header_len, body) catch unreachable; // same input as the measuring pass
    return out;
}

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "signature validation" {
    const good = [_][]const u8{ "", "y", "b", "u", "s", "o", "g", "v", "ay", "as", "ao", "a{ss}", "a{sv}", "(oayays)", "a{o(oayays)}", "a(yv)", "ssa{sv}", "aay", "tx", "(i(ii))" };
    for (good) |s| try validateSignature(s);
    const bad = [_][]const u8{ "a", "(", ")", "()", "{ss}", "a{vs}", "a{s}", "a{sss}", "(s", "z", "h", "a{ss", "ay)", "a{(s)s}" };
    for (bad) |s| try testing.expectError(error.Protocol, validateSignature(s));
    try testing.expect(isSingleType("a{sv}"));
    try testing.expect(!isSingleType("ss"));
    try testing.expect(!isSingleType(""));
    const deep_ok: [32]u8 = @splat('a');
    const deep_y = deep_ok ++ "y".*;
    try testing.expectError(error.Protocol, validateSignature(&deep_ok)); // no element type
    try validateSignature(&deep_y);
    const too_deep = @as([33]u8, @splat('a')) ++ "y".*;
    try testing.expectError(error.Protocol, validateSignature(&too_deep));
    const long: [256]u8 = @splat('y');
    try testing.expectError(error.Protocol, validateSignature(&long));
}

test "object path syntax" {
    for ([_][]const u8{ "/", "/org/freedesktop/secrets", "/a_1/B" }) |p| try testing.expect(validObjectPath(p));
    for ([_][]const u8{ "", "a", "//", "/a/", "/a//b", "/a-b", "/a.b" }) |p| try testing.expect(!validObjectPath(p));
}

fn expectBodyRoundTrip(sig: []const u8, vals: []const Value) !void {
    const enc = try encodeBody(testing.allocator, sig, vals);
    defer testing.allocator.free(enc);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const dec = try decodeBody(arena.allocator(), sig, enc, .little);
    try testing.expectEqual(vals.len, dec.len);
    for (vals, dec) |a, b| try testing.expect(a.eql(b));
}

const str_v: Value = .{ .string = "hello" };
const secret_struct: Value = .{ .structure = &.{
    .{ .object_path = "/org/freedesktop/secrets/session/s1" },
    .{ .bytes = "0123456789abcdef" },
    .{ .bytes = "\x01\x02\x03" },
    .{ .string = "text/plain" },
} };

test "body round trips for every signature in use" {
    try expectBodyRoundTrip("y", &.{.{ .byte = 0xab }});
    try expectBodyRoundTrip("b", &.{.{ .boolean = true }});
    try expectBodyRoundTrip("u", &.{.{ .uint32 = 0xdeadbeef }});
    try expectBodyRoundTrip("s", &.{str_v});
    try expectBodyRoundTrip("s", &.{.{ .string = "" }});
    try expectBodyRoundTrip("o", &.{.{ .object_path = "/org/freedesktop/secrets" }});
    try expectBodyRoundTrip("g", &.{.{ .signature = "a{sv}" }});
    try expectBodyRoundTrip("v", &.{.{ .variant = .{ .signature = "s", .value = &str_v } }});
    try expectBodyRoundTrip("ay", &.{.{ .bytes = "\x00\x01\xff" }});
    try expectBodyRoundTrip("ay", &.{.{ .bytes = "" }});
    try expectBodyRoundTrip("as", &.{.{ .array = .{ .signature = "s", .items = &.{ str_v, .{ .string = "x" } } } }});
    try expectBodyRoundTrip("ao", &.{.{ .array = .{ .signature = "o", .items = &.{ .{ .object_path = "/a" }, .{ .object_path = "/b/c" } } } }});
    try expectBodyRoundTrip("ao", &.{.{ .array = .{ .signature = "o", .items = &.{} } }});
    try expectBodyRoundTrip("a{ss}", &.{.{ .array = .{ .signature = "{ss}", .items = &.{
        .{ .dict_entry = &.{ .{ .string = "protocol" }, .{ .string = "https" } } },
        .{ .dict_entry = &.{ .{ .string = "server" }, .{ .string = "example.test" } } },
    } } }});
    try expectBodyRoundTrip("a{sv}", &.{.{ .array = .{ .signature = "{sv}", .items = &.{
        .{ .dict_entry = &.{ .{ .string = "org.freedesktop.Secret.Item.Label" }, .{ .variant = .{ .signature = "s", .value = &str_v } } } },
        .{ .dict_entry = &.{ .{ .string = "Modified" }, .{ .variant = .{ .signature = "t", .value = &.{ .uint64 = 1700000000 } } } } },
    } } }});
    try expectBodyRoundTrip("(oayays)", &.{secret_struct});
    try expectBodyRoundTrip("a{o(oayays)}", &.{.{ .array = .{ .signature = "{o(oayays)}", .items = &.{
        .{ .dict_entry = &.{ .{ .object_path = "/org/freedesktop/secrets/collection/login/1" }, secret_struct } },
    } } }});
    try expectBodyRoundTrip("a(yv)", &.{.{ .array = .{ .signature = "(yv)", .items = &.{
        .{ .structure = &.{ .{ .byte = 1 }, .{ .variant = .{ .signature = "o", .value = &.{ .object_path = "/" } } } } },
    } } }});
    try expectBodyRoundTrip("ybnqiuxtd", &.{
        .{ .byte = 1 },     .{ .boolean = false }, .{ .int16 = -2 }, .{ .uint16 = 3 },
        .{ .int32 = -4 },   .{ .uint32 = 5 },      .{ .int64 = -6 }, .{ .uint64 = 7 },
        .{ .double = 0.5 },
    });
    try expectBodyRoundTrip("v", &.{.{ .variant = .{ .signature = "ay", .value = &.{ .bytes = "pk" } } }});
}

test "body encoding layout" {
    const dict: Value = .{ .array = .{ .signature = "{ss}", .items = &.{
        .{ .dict_entry = &.{ .{ .string = "a" }, .{ .string = "bc" } } },
    } } };
    const enc = try encodeBody(testing.allocator, "a{ss}", &.{dict});
    defer testing.allocator.free(enc);
    const expected = "\x0f\x00\x00\x00" ++ // array len 15, excluding the padding
        "\x00\x00\x00\x00" ++ // pad to 8 for the dict entry
        "\x01\x00\x00\x00a\x00" ++ "\x00\x00" ++ "\x02\x00\x00\x00bc\x00";
    try testing.expectEqualSlices(u8, expected, enc);

    const enc2 = try encodeBody(testing.allocator, "ya{ss}", &.{ .{ .byte = 7 }, dict });
    defer testing.allocator.free(enc2);
    try testing.expectEqualSlices(u8, "\x07\x00\x00\x00" ++ "\x0f\x00\x00\x00" ++ expected[8..], enc2);
}

test "encode rejects mismatched values" {
    const gpa = testing.allocator;
    try testing.expectError(error.InvalidValue, encodeBody(gpa, "s", &.{.{ .uint32 = 1 }}));
    try testing.expectError(error.InvalidValue, encodeBody(gpa, "s", &.{}));
    try testing.expectError(error.InvalidValue, encodeBody(gpa, "", &.{str_v}));
    try testing.expectError(error.InvalidValue, encodeBody(gpa, "s", &.{.{ .string = "a\x00b" }}));
    try testing.expectError(error.InvalidValue, encodeBody(gpa, "o", &.{.{ .object_path = "bad" }}));
    try testing.expectError(error.InvalidValue, encodeBody(gpa, "ay", &.{.{ .array = .{ .signature = "y", .items = &.{} } }}));
    try testing.expectError(error.InvalidValue, encodeBody(gpa, "as", &.{.{ .array = .{ .signature = "o", .items = &.{} } }}));
    try testing.expectError(error.InvalidValue, encodeBody(gpa, "(ss)", &.{.{ .structure = &.{str_v} }}));
    try testing.expectError(error.InvalidValue, encodeBody(gpa, "v", &.{.{ .variant = .{ .signature = "ss", .value = &str_v } }}));
    try testing.expectError(error.InvalidValue, encodeBody(gpa, "a", &.{}));
}

/// Hello method call as encoded by `encodeMessage` (field order 1,2,3,6).
const hello_call = "l\x01\x00\x01" ++ "\x00\x00\x00\x00" ++ "\x01\x00\x00\x00" ++ "\x6d\x00\x00\x00" ++
    "\x01\x01o\x00" ++ "\x15\x00\x00\x00/org/freedesktop/DBus\x00" ++ "\x00\x00" ++
    "\x02\x01s\x00" ++ "\x14\x00\x00\x00org.freedesktop.DBus\x00" ++ "\x00\x00\x00" ++
    "\x03\x01s\x00" ++ "\x05\x00\x00\x00Hello\x00" ++ "\x00\x00" ++
    "\x06\x01s\x00" ++ "\x14\x00\x00\x00org.freedesktop.DBus\x00" ++ "\x00\x00\x00";

/// Hello reply, hand-built per the spec in dbus-daemon's field order
/// (6,5,8,7), with serial 0xffffffff and body `s`.
const hello_reply = "l\x02\x01\x01" ++ "\x0b\x00\x00\x00" ++ "\xff\xff\xff\xff" ++ "\x3d\x00\x00\x00" ++
    "\x06\x01s\x00" ++ "\x06\x00\x00\x00:1.234\x00" ++ "\x00" ++
    "\x05\x01u\x00" ++ "\x01\x00\x00\x00" ++
    "\x08\x01g\x00" ++ "\x01s\x00" ++ "\x00" ++
    "\x07\x01s\x00" ++ "\x14\x00\x00\x00org.freedesktop.DBus\x00" ++ "\x00\x00\x00" ++
    "\x06\x00\x00\x00:1.234\x00";

fn parseFixture(bytes: []const u8) Error!Message {
    return parse(testing.allocator, try testing.allocator.dupe(u8, bytes));
}

test "encode Hello matches fixture and parses back" {
    const h: Header = .{
        .type = .method_call,
        .serial = 1,
        .path = "/org/freedesktop/DBus",
        .interface = "org.freedesktop.DBus",
        .member = "Hello",
        .destination = "org.freedesktop.DBus",
    };
    const enc = try encodeMessage(testing.allocator, h, &.{});
    defer testing.allocator.free(enc);
    try testing.expectEqualSlices(u8, hello_call, enc);
    try testing.expectEqual(enc.len, try messageLength(enc[0..prefix_len]));

    var m = try parseFixture(enc);
    defer m.deinit(testing.allocator);
    try testing.expectEqual(MessageType.method_call, m.header.type);
    try testing.expectEqual(1, m.header.serial);
    try testing.expectEqualStrings("Hello", m.header.member.?);
    try testing.expectEqualStrings("/org/freedesktop/DBus", m.header.path.?);
    try testing.expectEqual(0, m.body.len);
}

test "parse dbus-daemon Hello reply" {
    var m = try parseFixture(hello_reply);
    defer m.deinit(testing.allocator);
    try testing.expectEqual(MessageType.method_return, m.header.type);
    try testing.expectEqual(1, m.header.reply_serial.?);
    try testing.expectEqual(0xffffffff, m.header.serial);
    try testing.expectEqualStrings(":1.234", m.header.destination.?);
    try testing.expectEqualStrings("org.freedesktop.DBus", m.header.sender.?);
    try testing.expectEqualStrings("s", m.header.signature);
    try testing.expectEqualStrings(":1.234", m.body[0].asString().?);
}

test "message round trip with secret-service body" {
    const body = [_]Value{
        .{ .array = .{ .signature = "{sv}", .items = &.{
            .{ .dict_entry = &.{ .{ .string = "org.freedesktop.Secret.Item.Label" }, .{ .variant = .{ .signature = "s", .value = &str_v } } } },
        } } },
        secret_struct,
        .{ .boolean = true },
    };
    const h: Header = .{
        .type = .method_call,
        .serial = 7,
        .flags = flag_allow_interactive_authorization,
        .path = "/org/freedesktop/secrets/aliases/default",
        .interface = "org.freedesktop.Secret.Collection",
        .member = "CreateItem",
        .destination = "org.freedesktop.secrets",
        .signature = "a{sv}(oayays)b",
    };
    const enc = try encodeMessage(testing.allocator, h, &body);
    defer testing.allocator.free(enc);
    var m = try parseFixture(enc);
    defer m.deinit(testing.allocator);
    try testing.expectEqual(flag_allow_interactive_authorization, m.header.flags);
    try testing.expectEqualStrings(h.signature, m.header.signature);
    try testing.expectEqual(body.len, m.body.len);
    for (body, m.body) |a, b| try testing.expect(a.eql(b));
    try testing.expectEqualStrings("hello", m.body[0].dictGet("org.freedesktop.Secret.Item.Label").?.unwrap().asString().?);
    try testing.expect(m.body[0].dictGet("nope") == null);
}

test "parse big-endian message" {
    // Signal /a org.x.I.M, body u = 0x01020304.
    const be = "B\x04\x00\x01" ++ "\x00\x00\x00\x04" ++ "\x00\x00\x00\x09" ++ "\x00\x00\x00\x37" ++
        "\x01\x01o\x00" ++ "\x00\x00\x00\x02/a\x00" ++ "\x00\x00\x00\x00\x00" ++
        "\x02\x01s\x00" ++ "\x00\x00\x00\x07org.x.I\x00" ++
        "\x03\x01s\x00" ++ "\x00\x00\x00\x01M\x00" ++ "\x00\x00\x00\x00\x00\x00" ++
        "\x08\x01g\x00" ++ "\x01u\x00" ++ "\x00" ++
        "\x01\x02\x03\x04";
    var m = try parseFixture(be);
    defer m.deinit(testing.allocator);
    try testing.expectEqual(MessageType.signal, m.header.type);
    try testing.expectEqual(0x01020304, m.body[0].asU32().?);
}

test "parse rejects malformed messages" {
    // Every strict prefix of a valid message is truncated.
    for (0..hello_reply.len) |n| try testing.expectError(error.Protocol, parseFixture(hello_reply[0..n]));

    var buf: [hello_reply.len]u8 = hello_reply.*;
    const cases = [_]struct { at: usize, byte: u8 }{
        .{ .at = 0, .byte = 'x' }, // byte order
        .{ .at = 3, .byte = 2 }, // protocol version
        .{ .at = 4, .byte = 0x0c }, // body length mismatch
        .{ .at = 12, .byte = 0x3e }, // fields length mismatch
        .{ .at = 31, .byte = 1 }, // nonzero padding
        .{ .at = 30, .byte = 'x' }, // missing string NUL
        .{ .at = 18, .byte = 'u' }, // destination with wrong type
        .{ .at = 16, .byte = 0 }, // invalid field code 0
        .{ .at = 36, .byte = 0 }, // reply serial 0
        .{ .at = 45, .byte = 'z' }, // invalid body signature
        .{ .at = 45, .byte = 'u' }, // body does not match signature
    };
    for (cases) |c| {
        buf = hello_reply.*;
        buf[c.at] = c.byte;
        try testing.expectError(error.Protocol, parseFixture(&buf));
    }
    // Serial 0.
    buf = hello_reply.*;
    @memset(buf[8..12], 0);
    try testing.expectError(error.Protocol, parseFixture(&buf));
    // Method return without reply serial.
    try testing.expectError(error.Protocol, parseFixture("l\x02\x00\x01" ++ "\x00\x00\x00\x00" ++ "\x01\x00\x00\x00" ++ "\x00\x00\x00\x00"));
    // Unix fds announced.
    try testing.expectError(error.Protocol, parseFixture("l\x02\x00\x01" ++ "\x00\x00\x00\x00" ++ "\x01\x00\x00\x00" ++ "\x10\x00\x00\x00" ++
        "\x05\x01u\x00\x01\x00\x00\x00" ++ "\x09\x01u\x00\x01\x00\x00\x00"));
}

test "messageLength enforces limits" {
    var p: [prefix_len]u8 = @splat(0);
    @memcpy(p[0..4], "l\x01\x00\x01");
    try testing.expectEqual(16, try messageLength(&p));
    std.mem.writeInt(u32, p[4..8], max_message_len, .little);
    try testing.expectError(error.Protocol, messageLength(&p));
    std.mem.writeInt(u32, p[4..8], 0, .little);
    std.mem.writeInt(u32, p[12..16], max_array_len + 1, .little);
    try testing.expectError(error.Protocol, messageLength(&p));
    std.mem.writeInt(u32, p[12..16], 0xffffffff, .little);
    std.mem.writeInt(u32, p[4..8], 0xffffffff, .little);
    try testing.expectError(error.Protocol, messageLength(&p));
}

test "decodeBody rejects malformed bodies" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectError(error.Protocol, decodeBody(a, "b", "\x02\x00\x00\x00", .little));
    try testing.expectError(error.Protocol, decodeBody(a, "s", "\x01\x00\x00\x00a", .little));
    try testing.expectError(error.Protocol, decodeBody(a, "s", "\xff\xff\xff\xffa\x00", .little));
    try testing.expectError(error.Protocol, decodeBody(a, "s", "\x03\x00\x00\x00a\x00b\x00", .little));
    try testing.expectError(error.Protocol, decodeBody(a, "u", "\x01\x00\x00\x00\x00", .little)); // trailing
    try testing.expectError(error.Protocol, decodeBody(a, "ay", "\x05\x00\x00\x00abc", .little));
    try testing.expectError(error.Protocol, decodeBody(a, "ay", "\x00\x00\x00\x05abc", .little));
    try testing.expectError(error.Protocol, decodeBody(a, "ay", "\x01\x00\x00\x04", .little)); // > 64 MiB
    try testing.expectError(error.Protocol, decodeBody(a, "au", "\x02\x00\x00\x00\x01\x00\x00\x00", .little)); // element overruns array
    try testing.expectError(error.Protocol, decodeBody(a, "v", "\x02ss\x00", .little)); // not a single type
    try testing.expectError(error.Protocol, decodeBody(a, "g", "\x01z\x00", .little));
    try testing.expectError(error.Protocol, decodeBody(a, "(u)", "\x00\x00\x00", .little));
    try testing.expectError(error.Protocol, decodeBody(a, "v", "\x00\x00", .little)); // empty variant signature
    try testing.expectError(error.Protocol, decodeBody(a, "yu", "\x01\x01\x00\x00\x05\x00\x00\x00", .little)); // nonzero pad
    try testing.expectError(error.Protocol, decodeBody(a, "o", "\x02\x00\x00\x00ab\x00", .little));
}

test "decode limits variant nesting depth" {
    // 40 nested variants "v" ... ending in a byte.
    var buf: [40 * 3 + 4]u8 = undefined;
    for (0..40) |i| @memcpy(buf[i * 3 ..][0..3], "\x01v\x00");
    @memcpy(buf[120..123], "\x01y\x00");
    buf[123] = 7;
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(error.Protocol, decodeBody(arena.allocator(), "v", &buf, .little));
    // A shallow nesting is fine.
    _ = try decodeBody(arena.allocator(), "v", "\x01v\x00\x01y\x00\x07", .little);
}

fn parseHelloAlloc(gpa: Allocator) !void {
    var m = try parse(gpa, try gpa.dupe(u8, hello_reply));
    m.deinit(gpa);
    const enc = try encodeMessage(gpa, .{ .type = .method_call, .serial = 2, .path = "/", .member = "M", .signature = "a{ss}" }, &.{.{
        .array = .{ .signature = "{ss}", .items = &.{.{ .dict_entry = &.{ .{ .string = "k" }, .{ .string = "v" } } }} },
    }});
    defer gpa.free(enc);
    var m2 = try parse(gpa, try gpa.dupe(u8, enc));
    m2.deinit(gpa);
}

test "parse and encode survive allocation failures" {
    try testing.checkAllAllocationFailures(testing.allocator, parseHelloAlloc, .{});
}

test "fuzz message parse" {
    try testing.fuzz({}, fuzzParse, .{ .corpus = &.{ hello_call, hello_reply, hello_reply[0..40] } });
}

fn fuzzParse(_: void, smith: *testing.Smith) anyerror!void {
    var buf: [2048]u8 = undefined;
    const len = smith.slice(&buf);
    try checkParse(buf[0..len]);
}

test "message parse survives random mutations" {
    // Deterministic stand-in for continuous fuzzing: mutate valid messages
    // (byte flips, length-field edits, truncation) and parse them.
    const gpa = testing.allocator;
    const big = try encodeMessage(gpa, .{
        .type = .method_return,
        .serial = 3,
        .reply_serial = 2,
        .signature = "a{o(oayays)}a{sv}",
    }, &.{
        .{ .array = .{ .signature = "{o(oayays)}", .items = &.{
            .{ .dict_entry = &.{ .{ .object_path = "/org/freedesktop/secrets/collection/login/1" }, secret_struct } },
        } } },
        .{ .array = .{ .signature = "{sv}", .items = &.{
            .{ .dict_entry = &.{ .{ .string = "Modified" }, .{ .variant = .{ .signature = "t", .value = &.{ .uint64 = 1 } } } } },
        } } },
    });
    defer gpa.free(big);
    const seeds = [_][]const u8{ hello_call, hello_reply, big };
    var prng: std.Random.DefaultPrng = .init(0x5c3a_d8b5);
    const rnd = prng.random();
    var buf: [512]u8 = undefined;
    for (0..20_000) |_| {
        const seed = seeds[rnd.uintLessThan(usize, seeds.len)];
        @memcpy(buf[0..seed.len], seed);
        var len = seed.len;
        for (0..rnd.intRangeAtMost(usize, 1, 4)) |_| {
            const at = rnd.uintLessThan(usize, len);
            switch (rnd.uintLessThan(u8, 4)) {
                0 => buf[at] = rnd.int(u8),
                1 => buf[at] ^= @as(u8, 1) << rnd.int(u3),
                2 => buf[at] = if (rnd.boolean()) 0 else 0xff,
                else => len = at + 1,
            }
        }
        try checkParse(buf[0..len]);
    }
}

fn checkParse(input: []const u8) !void {
    const gpa = testing.allocator;
    var m = parse(gpa, try gpa.dupe(u8, input)) catch return;
    defer m.deinit(gpa);
    // Wire encoding is canonical, so re-encoding a little-endian body must
    // reproduce it byte for byte.
    if (m.raw[0] != 'l') return;
    const enc = try encodeBody(gpa, m.header.signature, m.body);
    defer gpa.free(enc);
    try testing.expectEqualSlices(u8, m.raw[m.body_offset..], enc);
}
