//! Secret Service transfer encryption: `dh-ietf1024-sha256-aes128-cbc-pkcs7`.
//!
//! As in libsecret/gnome-keyring: Diffie-Hellman over the RFC 2409 1024-bit
//! MODP group (generator 2), public keys as big-endian `ay`; the AES key is
//! HKDF-SHA256(shared secret left-padded to 128 bytes, no salt, no info) cut
//! to 16 bytes; secrets travel as AES-128-CBC with PKCS#7 padding and a
//! random 16-byte IV as the secret's `parameters`.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const ff = std.crypto.ff;
const Aes128 = std.crypto.core.aes.Aes128;
const HkdfSha256 = std.crypto.kdf.hkdf.HkdfSha256;
const secureZero = std.crypto.secureZero;

pub const algorithm = "dh-ietf1024-sha256-aes128-cbc-pkcs7";
pub const public_key_len = 128;
pub const key_len = 16;
pub const block_len = 16;
pub const iv_len = block_len;

pub const Error = error{
    /// The peer's DH public key is out of range or malformed.
    InvalidPeerKey,
    /// IV, ciphertext length or padding is invalid.
    BadCiphertext,
    EntropyUnavailable,
    OutOfMemory,
};

const Modulus = ff.Modulus(8 * public_key_len);
const Fe = Modulus.Fe;

/// RFC 2409 section 6.2, Second Oakley Group (1024-bit MODP).
const prime_hex =
    "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1" ++
    "29024E088A67CC74020BBEA63B139B22514A08798E3404DD" ++
    "EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245" ++
    "E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED" ++
    "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE65381" ++
    "FFFFFFFFFFFFFFFF";

const prime: [public_key_len]u8 = blk: {
    @setEvalBranchQuota(10_000);
    var out: [public_key_len]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, prime_hex) catch @compileError("bad prime");
    break :blk out;
};

fn modulus() Modulus {
    // The prime is a fixed odd 1024-bit constant: this cannot fail (tested).
    return Modulus.fromBytes(&prime, .big) catch unreachable;
}

/// An ephemeral DH key pair. Call `wipe` when done.
pub const KeyPair = struct {
    private: [public_key_len]u8,
    public: [public_key_len]u8,

    pub fn generate(io: Io) Error!KeyPair {
        var kp: KeyPair = undefined;
        while (true) {
            io.randomSecure(&kp.private) catch return error.EntropyUnavailable;
            kp.computePublic() catch continue; // all-zero exponent: draw again
            return kp;
        }
    }

    /// Key pair from a fixed private exponent (tests).
    fn fromPrivate(private: [public_key_len]u8) error{NullExponent}!KeyPair {
        var kp: KeyPair = .{ .private = private, .public = undefined };
        try kp.computePublic();
        return kp;
    }

    fn computePublic(kp: *KeyPair) error{NullExponent}!void {
        const m = modulus();
        const g = Fe.fromPrimitive(u8, m, 2) catch unreachable; // 2 < p
        var y = try m.powWithEncodedExponent(g, &kp.private, .big);
        defer secureZero(u8, std.mem.asBytes(&y));
        y.toBytes(&kp.public, .big) catch unreachable; // y < p fits 128 bytes
    }

    /// Derives the session key from the peer's public key (1..128 bytes,
    /// big-endian, leading zeros optional). Rejects keys outside [2, p-2].
    pub fn deriveKey(kp: *const KeyPair, peer: []const u8) Error![key_len]u8 {
        if (peer.len == 0 or peer.len > public_key_len) return error.InvalidPeerKey;
        var padded: [public_key_len]u8 = @splat(0);
        @memcpy(padded[public_key_len - peer.len ..], peer);
        const m = modulus();
        const y = Fe.fromBytes(m, &padded, .big) catch return error.InvalidPeerKey;
        const p_minus_1 = m.sub(m.zero, m.one());
        if (y.isZero() or y.eql(m.one()) or y.eql(p_minus_1)) return error.InvalidPeerKey;

        var s = m.powWithEncodedExponent(y, &kp.private, .big) catch return error.InvalidPeerKey;
        defer secureZero(u8, std.mem.asBytes(&s));
        var secret: [public_key_len]u8 = undefined;
        defer secureZero(u8, &secret);
        s.toBytes(&secret, .big) catch unreachable; // s < p fits 128 bytes
        return hkdfKey(&secret);
    }

    pub fn wipe(kp: *KeyPair) void {
        secureZero(u8, &kp.private);
    }
};

/// HKDF-SHA256 with empty salt and info, truncated to the AES key size.
fn hkdfKey(ikm: []const u8) [key_len]u8 {
    var prk = HkdfSha256.extract("", ikm);
    defer secureZero(u8, &prk);
    var key: [key_len]u8 = undefined;
    HkdfSha256.expand(&key, "", prk);
    return key;
}

/// In-place AES-128-CBC encryption; `data.len` must be a multiple of 16.
fn cbcEncrypt(key: *const [key_len]u8, iv: *const [iv_len]u8, data: []u8) void {
    std.debug.assert(data.len % block_len == 0);
    var ctx = Aes128.initEnc(key.*);
    defer secureZero(u8, std.mem.asBytes(&ctx));
    var prev: [block_len]u8 = iv.*;
    var i: usize = 0;
    while (i < data.len) : (i += block_len) {
        const blk = data[i..][0..block_len];
        for (blk, prev) |*b, p| b.* ^= p;
        ctx.encrypt(blk, blk);
        prev = blk.*;
    }
}

/// In-place AES-128-CBC decryption; `data.len` must be a multiple of 16.
fn cbcDecrypt(key: *const [key_len]u8, iv: *const [iv_len]u8, data: []u8) void {
    std.debug.assert(data.len % block_len == 0);
    var ctx = Aes128.initDec(key.*);
    defer secureZero(u8, std.mem.asBytes(&ctx));
    var prev: [block_len]u8 = iv.*;
    var i: usize = 0;
    while (i < data.len) : (i += block_len) {
        const blk = data[i..][0..block_len];
        const saved = blk.*;
        ctx.decrypt(blk, blk);
        for (blk, prev) |*b, p| b.* ^= p;
        prev = saved;
    }
}

/// Length of the PKCS#7 padded form of `n` bytes (always adds 1..16 bytes).
fn paddedLen(n: usize) usize {
    return n + (block_len - n % block_len);
}

/// Validates PKCS#7 padding of `data` (non-empty multiple of 16) without
/// data-dependent branches and returns the unpadded length.
fn unpad(data: []const u8) Error!usize {
    if (data.len == 0 or data.len % block_len != 0) return error.BadCiphertext;
    const last = data[data.len - 1];
    var bad: u8 = @intFromBool(last == 0) | @intFromBool(last > block_len);
    for (0..block_len) |i| {
        const b = data[data.len - 1 - i];
        bad |= @intFromBool(i < last) & @intFromBool(b != last);
    }
    if (bad != 0) return error.BadCiphertext;
    return data.len - last;
}

pub const Encrypted = struct {
    iv: [iv_len]u8,
    ciphertext: []u8,

    pub fn deinit(e: *Encrypted, gpa: Allocator) void {
        secureZero(u8, e.ciphertext);
        gpa.free(e.ciphertext);
        e.* = undefined;
    }
};

/// A negotiated transfer key. Call `wipe` when done.
pub const Session = struct {
    key: [key_len]u8,

    /// Encrypts `plaintext` with a fresh random IV.
    pub fn encrypt(s: *const Session, gpa: Allocator, io: Io, plaintext: []const u8) Error!Encrypted {
        var iv: [iv_len]u8 = undefined;
        io.randomSecure(&iv) catch return error.EntropyUnavailable;
        return s.encryptWithIv(gpa, iv, plaintext);
    }

    fn encryptWithIv(s: *const Session, gpa: Allocator, iv: [iv_len]u8, plaintext: []const u8) Error!Encrypted {
        const n = paddedLen(plaintext.len);
        const buf = try gpa.alloc(u8, n);
        @memcpy(buf[0..plaintext.len], plaintext);
        @memset(buf[plaintext.len..], @intCast(n - plaintext.len));
        cbcEncrypt(&s.key, &iv, buf);
        return .{ .iv = iv, .ciphertext = buf };
    }

    /// Decrypts and unpads. Caller owns the result and must wipe it.
    pub fn decrypt(s: *const Session, gpa: Allocator, iv: []const u8, ciphertext: []const u8) Error![]u8 {
        if (iv.len != iv_len) return error.BadCiphertext;
        if (ciphertext.len == 0 or ciphertext.len % block_len != 0) return error.BadCiphertext;
        const buf = try gpa.dupe(u8, ciphertext);
        defer {
            secureZero(u8, buf);
            gpa.free(buf);
        }
        cbcDecrypt(&s.key, iv[0..iv_len], buf);
        const n = try unpad(buf);
        return gpa.dupe(u8, buf[0..n]);
    }

    pub fn wipe(s: *Session) void {
        secureZero(u8, &s.key);
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn hex(comptime s: []const u8) [s.len / 2]u8 {
    return comptime blk: {
        @setEvalBranchQuota(10_000);
        var out: [s.len / 2]u8 = undefined;
        _ = std.fmt.hexToBytes(&out, s) catch @compileError("bad hex");
        break :blk out;
    };
}

test "HKDF-SHA256 RFC 5869 vectors" {
    // Test case 1.
    const ikm: [22]u8 = @splat(0x0b);
    const prk1 = HkdfSha256.extract(&hex("000102030405060708090a0b0c"), &ikm);
    try testing.expectEqualSlices(u8, &hex("077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5"), &prk1);
    var okm1: [42]u8 = undefined;
    HkdfSha256.expand(&okm1, &hex("f0f1f2f3f4f5f6f7f8f9"), prk1);
    try testing.expectEqualSlices(u8, &hex("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"), &okm1);
    // Test case 3: empty salt and info, as the Secret Service uses.
    const prk3 = HkdfSha256.extract("", &ikm);
    try testing.expectEqualSlices(u8, &hex("19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04"), &prk3);
    var okm3: [42]u8 = undefined;
    HkdfSha256.expand(&okm3, "", prk3);
    try testing.expectEqualSlices(u8, &hex("8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"), &okm3);
    try testing.expectEqualSlices(u8, okm3[0..key_len], &hkdfKey(&ikm));
}

const nist_key = hex("2b7e151628aed2a6abf7158809cf4f3c");
const nist_iv = hex("000102030405060708090a0b0c0d0e0f");
const nist_pt = hex("6bc1bee22e409f96e93d7e117393172a" ++ "ae2d8a571e03ac9c9eb76fac45af8e51" ++
    "30c81c46a35ce411e5fbc1191a0a52ef" ++ "f69f2445df4f9b17ad2b417be66c3710");
const nist_ct = hex("7649abac8119b246cee98e9b12e9197d" ++ "5086cb9b507219ee95db113a917678b2" ++
    "73bed6b8e3c1743b7116e69e22229516" ++ "3ff1caa1681fac09120eca307586e1a7");

test "AES-128-CBC NIST SP 800-38A F.2.1/F.2.2" {
    var buf = nist_pt;
    cbcEncrypt(&nist_key, &nist_iv, &buf);
    try testing.expectEqualSlices(u8, &nist_ct, &buf);
    cbcDecrypt(&nist_key, &nist_iv, &buf);
    try testing.expectEqualSlices(u8, &nist_pt, &buf);

    // With PKCS#7 the NIST blocks are a prefix, followed by a full pad block.
    var s: Session = .{ .key = nist_key };
    var enc = try s.encryptWithIv(testing.allocator, nist_iv, &nist_pt);
    defer enc.deinit(testing.allocator);
    try testing.expectEqual(nist_pt.len + block_len, enc.ciphertext.len);
    try testing.expectEqualSlices(u8, &nist_ct, enc.ciphertext[0..nist_ct.len]);
    const dec = try s.decrypt(testing.allocator, &enc.iv, enc.ciphertext);
    defer testing.allocator.free(dec);
    try testing.expectEqualSlices(u8, &nist_pt, dec);
}

test "PKCS#7 padding edge cases" {
    var s: Session = .{ .key = nist_key };
    const msg: [33]u8 = @splat('x');
    for ([_]usize{ 0, 1, 15, 16, 17, 32, 33 }) |n| {
        var enc = try s.encryptWithIv(testing.allocator, nist_iv, msg[0..n]);
        defer enc.deinit(testing.allocator);
        try testing.expectEqual(paddedLen(n), enc.ciphertext.len);
        try testing.expect(enc.ciphertext.len > n and enc.ciphertext.len - n <= block_len);
        const dec = try s.decrypt(testing.allocator, &enc.iv, enc.ciphertext);
        defer testing.allocator.free(dec);
        try testing.expectEqualSlices(u8, msg[0..n], dec);
    }

    try testing.expectEqual(15, try unpad(&(@as([15]u8, @splat('a')) ++ [_]u8{1})));
    try testing.expectEqual(0, try unpad(&@as([16]u8, @splat(16))));
    try testing.expectEqual(12, try unpad(&(@as([12]u8, @splat(0)) ++ [_]u8{ 4, 4, 4, 4 })));
    const bad = [_][16]u8{
        @as([15]u8, @splat('a')) ++ [_]u8{0}, // pad byte 0
        @as([15]u8, @splat('a')) ++ [_]u8{17}, // pad byte > block
        @as([13]u8, @splat('a')) ++ [_]u8{ 4, 4, 4 }, // short run
        @as([12]u8, @splat('a')) ++ [_]u8{ 4, 3, 4, 4 }, // inconsistent run
    };
    for (bad) |b| try testing.expectError(error.BadCiphertext, unpad(&b));
    try testing.expectError(error.BadCiphertext, unpad(""));
    try testing.expectError(error.BadCiphertext, unpad("short"));
}

test "decrypt rejects malformed ciphertext" {
    var s: Session = .{ .key = nist_key };
    try testing.expectError(error.BadCiphertext, s.decrypt(testing.allocator, nist_iv[0..15], &nist_ct));
    try testing.expectError(error.BadCiphertext, s.decrypt(testing.allocator, &nist_iv, ""));
    try testing.expectError(error.BadCiphertext, s.decrypt(testing.allocator, &nist_iv, nist_ct[0..17]));
    // The raw NIST ciphertext decrypts to data without valid padding.
    try testing.expectError(error.BadCiphertext, s.decrypt(testing.allocator, &nist_iv, &nist_ct));

    // CBC malleability: flipping a bit in block 1 garbles plaintext block 1
    // and flips the same bit in block 2, leaving the padding intact.
    const two_blocks = "0123456789abcdefXYZW";
    var enc2 = try s.encryptWithIv(testing.allocator, nist_iv, two_blocks);
    defer enc2.deinit(testing.allocator);
    enc2.ciphertext[0] ^= 0x01;
    const garbled = try s.decrypt(testing.allocator, &enc2.iv, enc2.ciphertext);
    defer testing.allocator.free(garbled);
    try testing.expectEqual(two_blocks.len, garbled.len);
    try testing.expectEqual('X' ^ 0x01, garbled[16]);

    // Tampering with the padding is detected.
    var enc = try s.encryptWithIv(testing.allocator, nist_iv, "secret");
    defer enc.deinit(testing.allocator);
    var iv_bad = enc.iv;
    iv_bad[15] ^= 0x05; // flips the last plaintext byte: padding 0x0a -> 0x0f
    try testing.expectError(error.BadCiphertext, s.decrypt(testing.allocator, &iv_bad, enc.ciphertext));
}

test "encrypt uses fresh IVs" {
    var s: Session = .{ .key = nist_key };
    defer s.wipe();
    var a = try s.encrypt(testing.allocator, testing.io, "pw");
    defer a.deinit(testing.allocator);
    var b = try s.encrypt(testing.allocator, testing.io, "pw");
    defer b.deinit(testing.allocator);
    try testing.expect(!std.mem.eql(u8, &a.iv, &b.iv));
    const dec = try s.decrypt(testing.allocator, &b.iv, b.ciphertext);
    defer testing.allocator.free(dec);
    try testing.expectEqualStrings("pw", dec);
}

test "group constant and generator" {
    const m = modulus();
    try testing.expectEqual(1024, m.bits());
    var one: [public_key_len]u8 = @splat(0);
    one[public_key_len - 1] = 1;
    const kp = try KeyPair.fromPrivate(one);
    var two: [public_key_len]u8 = @splat(0);
    two[public_key_len - 1] = 2;
    try testing.expectEqualSlices(u8, &two, &kp.public);
    // Public keys are always reduced below p.
    var big: [public_key_len]u8 = @splat(0xff);
    const kp2 = try KeyPair.fromPrivate(big);
    try testing.expect(std.mem.order(u8, &kp2.public, &prime) == .lt);
    big = @splat(0);
    try testing.expectError(error.NullExponent, KeyPair.fromPrivate(big));
}

test "DH self-agreement" {
    var a = try KeyPair.generate(testing.io);
    defer a.wipe();
    var b = try KeyPair.generate(testing.io);
    defer b.wipe();
    try testing.expect(!std.mem.eql(u8, &a.public, &b.public));
    const ka = try a.deriveKey(&b.public);
    const kb = try b.deriveKey(&a.public);
    try testing.expectEqualSlices(u8, &ka, &kb);

    // Peer keys with leading zeros stripped (libgcrypt USG export) are
    // the same key as their left-padded form.
    var five: [public_key_len]u8 = @splat(0);
    five[public_key_len - 1] = 5;
    try testing.expectEqualSlices(u8, &(try a.deriveKey(&five)), &(try a.deriveKey("\x05")));
    try testing.expectEqualSlices(u8, &(try a.deriveKey(&five)), &(try a.deriveKey("\x00\x00\x05")));

    var sa: Session = .{ .key = ka };
    const sb: Session = .{ .key = kb };
    var enc = try sa.encrypt(testing.allocator, testing.io, "hunter2\npassword_expiry_utc=1");
    defer enc.deinit(testing.allocator);
    const dec = try sb.decrypt(testing.allocator, &enc.iv, enc.ciphertext);
    defer testing.allocator.free(dec);
    try testing.expectEqualStrings("hunter2\npassword_expiry_utc=1", dec);
    sa.wipe();
}

test "DH rejects invalid peer keys" {
    var a = try KeyPair.generate(testing.io);
    defer a.wipe();
    var p_minus_1 = prime;
    p_minus_1[public_key_len - 1] -= 1;
    var p_minus_255 = prime;
    p_minus_255[public_key_len - 1] = 0; // p ends in 0xff
    const too_long: [public_key_len + 1]u8 = @splat(1);
    const max: [public_key_len]u8 = @splat(0xff);
    const bad = [_][]const u8{ "", "\x00", "\x01", "\x00\x00\x01", &p_minus_1, &prime, &max, &too_long };
    for (bad) |k| try testing.expectError(error.InvalidPeerKey, a.deriveKey(k));
    _ = try a.deriveKey("\x02");
    _ = try a.deriveKey(&p_minus_255);
}
