//! git-credential-scm: git credential helper backed by the Secret Service
//! (GNOME login keyring), tagging items with `application=scm-auth`.
//!
//! Usage: git-credential-scm [--tool=<name>] [--apply] [--all] <action>
//! where <action> is get|store|erase (git protocol) or list|retag (admin).

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const build_options = @import("build_options");
const protocol = @import("protocol.zig");
const conn = @import("dbus/conn.zig");
const secret = @import("secret.zig");
const Action = protocol.Action;
const Attr = protocol.Attr;
const ItemInfo = secret.ItemInfo;
const findAttr = protocol.findAttr;

pub const version = build_options.version;
const prog_name = "git-credential-scm";
const usage_text = "usage: " ++ prog_name ++
    " [--tool=<name>] [--apply] [--all] <get|store|erase|list|retag> | --version";

pub const Command = union(enum) {
    action: Action,
    version,
    help,
    /// An action this helper does not know. git's protocol asks helpers to
    /// ignore those silently, like the stock helper does.
    unknown,
};

pub const Cli = struct {
    command: Command,
    tool: []const u8 = protocol.default_tool,
    apply: bool = false,
    all: bool = false,
};

pub const Error = error{
    Usage,
    Protocol,
    /// A keyring secret contains bytes git's protocol cannot carry.
    BadStoredSecret,
} || secret.Error;

/// Parses argv (including argv[0]). Options may appear before or after the
/// single action, so `list --all` == `--all list`; git's
/// `helper = scm --tool=<name>` invocation appends the action last.
pub fn parseArgs(args: []const [:0]const u8) error{Usage}!Cli {
    var cli: Cli = .{ .command = .unknown };
    var action: ?[]const u8 = null;
    var info: ?Command = null;
    const rest = if (args.len > 0) args[1..] else args;
    for (rest) |arg| {
        if (std.mem.startsWith(u8, arg, "--tool=")) {
            cli.tool = arg["--tool=".len..];
            if (!protocol.validTool(cli.tool)) return error.Usage;
        } else if (std.mem.eql(u8, arg, "--apply")) {
            cli.apply = true;
        } else if (std.mem.eql(u8, arg, "--all")) {
            cli.all = true;
        } else if (std.mem.eql(u8, arg, "--version")) {
            info = .version;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            info = .help;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return error.Usage;
        } else {
            if (action != null) return error.Usage;
            action = arg;
        }
    }
    if (info) |command| {
        cli.command = command;
        return cli;
    }
    const name = action orelse return error.Usage;
    if (name.len == 0) return error.Usage;
    cli.command = if (Action.fromString(name)) |a| .{ .action = a } else .unknown;
    if (cli.apply and cli.command != .action) return error.Usage;
    if (cli.apply and cli.command.action != .retag) return error.Usage;
    if (cli.all and (cli.command != .action or cli.command.action != .list)) return error.Usage;
    return cli;
}

/// 0 on success, 2 for usage errors, 1 for everything else.
pub fn exitCode(err: Error) u8 {
    return switch (err) {
        error.Usage => 2,
        else => 1,
    };
}

/// Single-line, secret-free description of `err` for stderr.
pub fn errorMessage(err: Error) []const u8 {
    return switch (err) {
        error.Usage => usage_text,
        error.Protocol => "malformed credential input",
        error.BadStoredSecret => "keyring item holds a secret git cannot accept",
        error.NoSessionBus => "no session bus (DBUS_SESSION_BUS_ADDRESS and XDG_RUNTIME_DIR are unset)",
        error.UnsupportedAddress => "unsupported D-Bus address (only unix:path= is supported)",
        error.InvalidAddress => "invalid D-Bus address",
        error.ConnectFailed => "cannot connect to the session bus",
        error.AuthRejected => "the session bus rejected authentication",
        error.BusProtocol => "malformed message from the session bus",
        error.RemoteError => "Secret Service error",
        error.Disconnected => "the session bus closed the connection",
        error.ReadFailed => "read failed",
        error.WriteFailed => "write failed",
        error.InvalidValue => "invalid D-Bus request",
        error.PromptDismissed => "keyring prompt dismissed",
        error.BadCiphertext => "cannot decrypt the secret from the Secret Service",
        error.InvalidPeerKey => "the Secret Service sent an invalid session key",
        error.EntropyUnavailable => "no secure random numbers available",
        error.OutOfMemory => "out of memory",
    };
}

/// Extra context for error reports: the D-Bus error name of a remote error.
const Diag = struct {
    buf: [conn.max_name_len]u8 = undefined,
    len: usize = 0,

    fn set(d: *Diag, error_name: []const u8) void {
        d.len = @min(error_name.len, d.buf.len);
        @memcpy(d.buf[0..d.len], error_name[0..d.len]);
    }

    fn name(d: *const Diag) []const u8 {
        return d.buf[0..d.len];
    }
};

pub fn main(init: std.process.Init) u8 {
    const io = init.io;
    var diag: Diag = .{};
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch {
        report(io, error.OutOfMemory, &diag);
        return 1;
    };
    const cli = parseArgs(args) catch |err| {
        report(io, err, &diag);
        return exitCode(err);
    };
    run(init.gpa, io, init.environ_map, cli, &diag) catch |err| {
        report(io, err, &diag);
        return exitCode(err);
    };
    return 0;
}

fn report(io: Io, err: Error, diag: *const Diag) void {
    var buf: [512]u8 = undefined;
    const line = if (err == error.RemoteError and diag.len > 0)
        std.fmt.bufPrint(&buf, "{s}: {s}: {s}\n", .{ prog_name, errorMessage(err), diag.name() }) catch return
    else
        std.fmt.bufPrint(&buf, "{s}: {s}\n", .{ prog_name, errorMessage(err) }) catch return;
    Io.File.stderr().writeStreamingAll(io, line) catch {};
}

fn run(gpa: Allocator, io: Io, environ: *const std.process.Environ.Map, cli: Cli, diag: *Diag) Error!void {
    const action = switch (cli.command) {
        .unknown => return,
        .version => return writeStdout(io, prog_name ++ " " ++ version ++ "\n"),
        .help => return writeStdout(io, usage_text ++ "\n"),
        .action => |a| a,
    };

    // The reader buffer sees secrets: it lives here and is wiped.
    var in_buf: [protocol.max_input_len + 1]u8 = undefined;
    defer std.crypto.secureZero(u8, &in_buf);
    var req: protocol.Request = .{};
    defer req.deinit(gpa);
    if (action.readsCredential()) {
        var stdin = Io.File.stdin().readerStreaming(io, &in_buf);
        req = try protocol.Request.parse(gpa, &stdin.interface, protocol.max_input_len);
        const now = Io.Clock.real.now(io).toSeconds();
        const wanted = switch (action) {
            .get => req.lookupable(),
            .store => req.storable(now),
            .erase => req.erasable(),
            .list, .retag => unreachable, // readsCredential() is false for these
        };
        // Requests the stock helper would refuse are a silent no-op.
        if (!wanted) return;
    }

    // The output buffer may hold a password: it is wiped after flushing.
    var out_buf: [4096]u8 = undefined;
    defer std.crypto.secureZero(u8, &out_buf);
    var stdout = Io.File.stdout().writerStreaming(io, &out_buf);
    const job: Job = .{ .action = action, .cli = cli, .req = &req, .out = &stdout.interface };

    const bus = try gpa.create(conn.Bus);
    defer gpa.destroy(bus);
    bus.openSession(gpa, io, environ) catch |err| return secret.mapConn(err);
    defer bus.close();
    withClient(gpa, io, environ, &bus.conn, job) catch |err| {
        if (err == error.RemoteError) diag.set(bus.conn.errorName());
        return err;
    };
    stdout.interface.flush() catch return error.WriteFailed;
}

const Job = struct {
    action: Action,
    cli: Cli,
    req: *const protocol.Request,
    out: *Io.Writer,
};

fn withClient(gpa: Allocator, io: Io, environ: *const std.process.Environ.Map, bus: *conn.Conn, job: Job) Error!void {
    var client = try secret.Client.init(gpa, io, bus, .{ .allow_plain = secret.plainAllowed(environ) });
    defer client.deinit();
    try runAction(gpa, &client, job);
    client.closeSession() catch {};
}

/// Runs a keyring action with any `secret.ClientT` client.
fn runAction(gpa: Allocator, c: anytype, job: Job) Error!void {
    switch (job.action) {
        .get => try doGet(gpa, c, job.req, job.out),
        .store => try doStore(gpa, c, job.req, job.cli.tool),
        .erase => try doErase(gpa, c, job.req),
        .list => try doList(gpa, c, job.cli.all, job.out),
        .retag => try doRetag(gpa, c, job.cli.apply, job.cli.tool, job.out),
    }
}

fn writeStdout(io: Io, bytes: []const u8) error{WriteFailed}!void {
    Io.File.stdout().writeStreamingAll(io, bytes) catch return error.WriteFailed;
}

// ---------------------------------------------------------------- actions

/// The stock attributes that identify a credential. Items whose values for
/// all of them are byte-identical are duplicates.
const stock_keys = [_][]const u8{
    protocol.attr_user,
    protocol.attr_protocol,
    protocol.attr_server,
    protocol.attr_port,
    protocol.attr_object,
};

fn optEql(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null or b == null) return a == null and b == null;
    return std.mem.eql(u8, a.?, b.?);
}

fn optOrder(a: ?[]const u8, b: ?[]const u8) std.math.Order {
    if (a == null or b == null) {
        if (a == null and b == null) return .eq;
        return if (a == null) .lt else .gt;
    }
    return std.mem.order(u8, a.?, b.?);
}

fn sameStock(a: []const Attr, b: []const Attr) bool {
    for (stock_keys) |k| if (!optEql(findAttr(a, k), findAttr(b, k))) return false;
    return true;
}

fn isTagged(attrs: []const Attr) bool {
    return optEql(findAttr(attrs, protocol.attr_application), protocol.application_name);
}

/// Items without a schema (very old helpers) or with the git schema.
fn gitSchema(attrs: []const Attr) bool {
    const s = findAttr(attrs, protocol.attr_schema) orelse return true;
    return std.mem.eql(u8, s, protocol.schema_name);
}

/// Constant-time comparison for passwords.
fn secretEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var diff: u8 = 0;
    for (a, b) |x, y| diff |= x ^ y;
    return diff == 0;
}

/// Metadata of every found item (unlocked ones first), allocated in `a`.
fn collect(a: Allocator, c: anytype, found: secret.Found) Error![]ItemInfo {
    const infos = try a.alloc(ItemInfo, found.count());
    for (found.unlocked, 0..) |p, i| infos[i] = try c.info(a, p);
    for (found.locked, found.unlocked.len..) |p, i| {
        infos[i] = try c.info(a, p);
        infos[i].locked = true;
    }
    return infos;
}

/// `get` preference: tagged items first, then the most recently modified.
fn preferForGet(x: *const ItemInfo, y: *const ItemInfo) bool {
    const tx = isTagged(x.attrs);
    const ty = isTagged(y.attrs);
    if (tx != ty) return tx;
    return x.modified > y.modified;
}

fn doGet(gpa: Allocator, c: anytype, req: *const protocol.Request, out: *Io.Writer) Error!void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const query: protocol.AttrSet = try .init(a, req.target(), .search);
    const infos = try collect(a, c, try c.search(a, query.items));
    if (infos.len == 0) return;
    var best = &infos[0];
    for (infos[1..]) |*x| {
        if (preferForGet(x, best)) best = x;
    }
    if (best.locked) try c.unlock(&.{best.path});
    const text = try c.getSecret(best.path);
    defer protocol.wipeFree(gpa, text);
    var stored = try protocol.decodeSecret(gpa, text);
    defer stored.deinit(gpa);
    protocol.writeCredential(out, .{
        .username = findAttr(best.attrs, protocol.attr_user) orelse req.username,
        .password = stored.password,
        .password_expiry_utc = stored.password_expiry_utc,
        .oauth_refresh_token = stored.oauth_refresh_token,
    }) catch |err| return switch (err) {
        error.Protocol => error.BadStoredSecret,
        error.WriteFailed => error.WriteFailed,
    };
}

fn doStore(gpa: Allocator, c: anytype, req: *const protocol.Request, tool: []const u8) Error!void {
    const password = req.password orelse return;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const t = req.target();
    const attrs: protocol.AttrSet = try .init(a, t, .{ .store = tool });
    const label = try protocol.makeLabel(a, t);
    const text = try protocol.encodeSecret(gpa, password, req.password_expiry_utc, req.oauth_refresh_token);
    defer protocol.wipeFree(gpa, text);
    const created = try c.create(a, label, attrs.items, text);

    // CreateItem only replaces items with all-equal attributes, so legacy
    // items and items of other tools for the same credential remain.
    const query: protocol.AttrSet = try .init(a, t, .search);
    const infos = try collect(a, c, try c.search(a, query.items));
    var doomed: std.ArrayList([]const u8) = .empty;
    var locked: std.ArrayList([]const u8) = .empty;
    for (infos) |*x| {
        if (std.mem.eql(u8, x.path, created)) continue;
        if (!gitSchema(x.attrs) or !sameStock(x.attrs, attrs.items)) continue;
        try doomed.append(a, x.path);
        if (x.locked) try locked.append(a, x.path);
    }
    try c.unlock(locked.items);
    for (doomed.items) |p| try c.delete(p);
}

fn doErase(gpa: Allocator, c: anytype, req: *const protocol.Request) Error!void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const query: protocol.AttrSet = try .init(a, req.target(), .search);
    const found = try c.search(a, query.items);
    if (found.count() == 0) return;
    try c.unlock(found.locked);
    for ([_][]const []const u8{ found.unlocked, found.locked }) |paths| {
        for (paths) |p| {
            // Like the stock helper: with a password, only erase the
            // credential if it is the one git just failed with.
            if (req.password) |pw| {
                const text = try c.getSecret(p);
                defer protocol.wipeFree(gpa, text);
                var stored = try protocol.decodeSecret(gpa, text);
                defer stored.deinit(gpa);
                if (!secretEql(stored.password, pw)) continue;
            }
            try c.delete(p);
        }
    }
}

fn labelLess(_: void, x: ItemInfo, y: ItemInfo) bool {
    return switch (std.mem.order(u8, x.label, y.label)) {
        .lt => true,
        .gt => false,
        .eq => std.mem.lessThan(u8, x.path, y.path),
    };
}

fn attrLess(_: void, x: Attr, y: Attr) bool {
    return std.mem.lessThan(u8, x.key, y.key);
}

fn doList(gpa: Allocator, c: anytype, all: bool, out: *Io.Writer) Error!void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const by_schema = [_]Attr{.{ .key = protocol.attr_schema, .value = protocol.schema_name }};
    const by_app = [_]Attr{.{ .key = protocol.attr_application, .value = protocol.application_name }};
    const infos = try collect(a, c, try c.search(a, if (all) &by_schema else &by_app));
    std.mem.sortUnstable(ItemInfo, infos, {}, labelLess);
    for (infos) |*x| try writeItem(a, out, x);
}

/// `<modified>\t<label>\t<key=value ...>`; never the secret.
fn writeItem(a: Allocator, out: *Io.Writer, x: *const ItemInfo) Error!void {
    const attrs = try a.dupe(Attr, x.attrs);
    std.mem.sortUnstable(Attr, attrs, {}, attrLess);
    try writeTime(out, x.modified);
    try out.writeByte('\t');
    try writeSafe(out, x.label);
    try out.writeByte('\t');
    for (attrs, 0..) |at, i| {
        if (i > 0) try out.writeByte(' ');
        try writeSafe(out, at.key);
        try out.writeByte('=');
        try writeSafe(out, at.value);
    }
    try out.writeByte('\n');
}

/// Writes `bytes` with control characters replaced, so keyring data
/// cannot forge output lines or terminal escapes.
fn writeSafe(out: *Io.Writer, bytes: []const u8) error{WriteFailed}!void {
    for (bytes) |b| try out.writeByte(if (b < 0x20 or b == 0x7f) '?' else b);
}

/// Last second of year 9999; later values are printed as raw numbers.
const max_iso_seconds: u64 = 253402300799;

fn writeTime(out: *Io.Writer, secs: u64) error{WriteFailed}!void {
    if (secs > max_iso_seconds) return out.print("@{d}", .{secs});
    const es: std.time.epoch.EpochSeconds = .{ .secs = secs };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    try out.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        yd.year,
        md.month.numeric(),
        @as(u8, md.day_index) + 1,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
    });
}

const PlanKind = enum { ok, update, delete, skip };

const Plan = struct {
    info: *const ItemInfo,
    kind: PlanKind,
    /// New label (update/ok), or the kept item's new label (delete).
    label: []const u8 = "",
    attrs: []const Attr = &.{},
    tool: []const u8 = "",
};

/// Duplicate groups (equal stock attributes) are adjacent; inside a group
/// the most recently modified item comes first, then tagged ones.
fn groupLess(_: void, x: ItemInfo, y: ItemInfo) bool {
    for (stock_keys) |k| switch (optOrder(findAttr(x.attrs, k), findAttr(y.attrs, k))) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    };
    if (x.modified != y.modified) return x.modified > y.modified;
    const tx = isTagged(x.attrs);
    if (tx != isTagged(y.attrs)) return tx;
    return std.mem.lessThan(u8, x.path, y.path);
}

/// Target state of a kept item: `application=scm-auth`, a `tool` (kept if
/// already valid, `forge` for `forge: ` labels, else `default_tool`) and
/// the scm-auth label derived from its attributes.
fn planKeeper(a: Allocator, x: *const ItemInfo, default_tool: []const u8) Error!Plan {
    const target = protocol.Target.fromAttrs(x.attrs) catch return .{ .info = x, .kind = .skip };
    const tool = blk: {
        if (findAttr(x.attrs, protocol.attr_tool)) |t| if (protocol.validTool(t)) break :blk t;
        const legacy = protocol.toolForLegacyLabel(x.label);
        break :blk if (std.mem.eql(u8, legacy, protocol.default_tool)) default_tool else legacy;
    };
    const label = try protocol.makeLabel(a, target);
    var attrs: std.ArrayList(Attr) = try .initCapacity(a, x.attrs.len + 2);
    for (x.attrs) |at| {
        if (std.mem.eql(u8, at.key, protocol.attr_application) or std.mem.eql(u8, at.key, protocol.attr_tool)) continue;
        attrs.appendAssumeCapacity(at);
    }
    attrs.appendAssumeCapacity(.{ .key = protocol.attr_application, .value = protocol.application_name });
    attrs.appendAssumeCapacity(.{ .key = protocol.attr_tool, .value = tool });
    const unchanged = std.mem.eql(u8, label, x.label) and isTagged(x.attrs) and
        optEql(findAttr(x.attrs, protocol.attr_tool), tool);
    return .{ .info = x, .kind = if (unchanged) .ok else .update, .label = label, .attrs = attrs.items, .tool = tool };
}

fn doRetag(gpa: Allocator, c: anytype, apply: bool, default_tool: []const u8, out: *Io.Writer) Error!void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const by_schema = [_]Attr{.{ .key = protocol.attr_schema, .value = protocol.schema_name }};
    const infos = try collect(a, c, try c.search(a, &by_schema));
    std.mem.sortUnstable(ItemInfo, infos, {}, groupLess);

    const plans = try a.alloc(Plan, infos.len);
    var i: usize = 0;
    while (i < infos.len) {
        plans[i] = try planKeeper(a, &infos[i], default_tool);
        const keeper_label = if (plans[i].kind == .skip) infos[i].label else plans[i].label;
        var j = i + 1;
        while (j < infos.len and sameStock(infos[i].attrs, infos[j].attrs)) : (j += 1) {
            plans[j] = .{ .info = &infos[j], .kind = .delete, .label = keeper_label };
        }
        i = j;
    }

    var counts: std.EnumArray(PlanKind, usize) = .initFill(0);
    for (plans) |*p| {
        counts.getPtr(p.kind).* += 1;
        try writePlan(out, p);
    }
    const changes = counts.get(.update) + counts.get(.delete);
    if (apply) {
        var locked: std.ArrayList([]const u8) = .empty;
        for (plans) |*p| {
            if (p.info.locked and (p.kind == .update or p.kind == .delete)) try locked.append(a, p.info.path);
        }
        try c.unlock(locked.items);
        for (plans) |*p| switch (p.kind) {
            .delete => try c.delete(p.info.path),
            .update => try c.setLabelAndAttrs(p.info.path, p.label, p.attrs),
            .ok, .skip => {},
        };
    }
    const suffix: []const u8 = if (changes == 0)
        ""
    else if (apply)
        " (applied)"
    else
        " (preview; run with --apply to change)";
    try out.print("retag: {d} to update, {d} duplicate(s) to delete, {d} already tagged, {d} skipped{s}\n", .{
        counts.get(.update), counts.get(.delete), counts.get(.ok), counts.get(.skip), suffix,
    });
}

fn writePlan(out: *Io.Writer, p: *const Plan) Error!void {
    switch (p.kind) {
        .ok => {
            try out.writeAll("ok      ");
            try writeSafe(out, p.info.label);
        },
        .update => {
            try out.writeAll("retag   ");
            try writeSafe(out, p.info.label);
            try out.writeAll(" -> ");
            try writeSafe(out, p.label);
            try out.print(" (tool={s})", .{p.tool});
        },
        .delete => {
            try out.writeAll("delete  ");
            try writeSafe(out, p.info.label);
            try out.writeAll(" (older duplicate of ");
            try writeSafe(out, p.label);
            try out.writeAll(")");
        },
        .skip => {
            try out.writeAll("skip    ");
            try writeSafe(out, p.info.label);
            try out.writeAll(" (unparsable port attribute)");
        },
    }
    try out.writeByte('\n');
}

// ---------------------------------------------------------------- tests

const testing = std.testing;
const FakeBus = @import("fake_bus.zig").FakeBus;
const TestClient = secret.ClientT(FakeBus);

test {
    _ = protocol;
    _ = @import("dbus/address.zig");
    _ = @import("dbus/auth.zig");
    _ = @import("dbus/message.zig");
    _ = @import("dbus/conn.zig");
    _ = @import("crypto.zig");
    _ = secret;
}

test "parseArgs actions and options" {
    const get = try parseArgs(&.{ "x", "get" });
    try testing.expectEqual(Action.get, get.command.action);
    try testing.expectEqualStrings("git", get.tool);

    const tool = try parseArgs(&.{ "x", "--tool=forge", "store" });
    try testing.expectEqual(Action.store, tool.command.action);
    try testing.expectEqualStrings("forge", tool.tool);

    const retag = try parseArgs(&.{ "x", "--apply", "--tool=hf", "retag" });
    try testing.expect(retag.apply);
    try testing.expectEqual(Action.retag, retag.command.action);

    const list = try parseArgs(&.{ "x", "--all", "list" });
    try testing.expect(list.all);
}

test "parseArgs options are position independent" {
    const list = try parseArgs(&.{ "x", "list", "--all" });
    try testing.expect(list.all);
    try testing.expectEqual(Action.list, list.command.action);

    const retag = try parseArgs(&.{ "x", "--tool=hf", "retag", "--apply" });
    try testing.expect(retag.apply);
    try testing.expectEqualStrings("hf", retag.tool);
    try testing.expectEqual(Action.retag, retag.command.action);

    const get = try parseArgs(&.{ "x", "get", "--tool=forge" });
    try testing.expectEqual(Action.get, get.command.action);
    try testing.expectEqualStrings("forge", get.tool);

    try testing.expectEqual(Command.version, (try parseArgs(&.{ "x", "--version" })).command);
    try testing.expectEqual(Command.help, (try parseArgs(&.{ "x", "-h" })).command);
    try testing.expectEqual(Command.unknown, (try parseArgs(&.{ "x", "frobnicate" })).command);
}

test "parseArgs rejects bad usage" {
    const bad = [_][]const [:0]const u8{
        &.{"x"},
        &.{},
        &.{ "x", "" },
        &.{ "x", "get", "store" },
        &.{ "x", "list", "--all", "list" },
        &.{ "x", "get", "--tool=" },
        &.{ "x", "list", "--frob" },
        &.{ "x", "retag", "--all" },
        &.{ "x", "--tool=", "get" },
        &.{ "x", "--tool=Bad Tool", "get" },
        &.{ "x", "--frob", "get" },
        &.{ "x", "--apply", "get" },
        &.{ "x", "--apply", "frobnicate" },
        &.{ "x", "--all", "retag" },
    };
    for (bad) |args| try testing.expectError(error.Usage, parseArgs(args));
}

test "exit codes and messages" {
    try testing.expectEqual(2, exitCode(error.Usage));
    try testing.expectEqual(1, exitCode(error.Protocol));
    try testing.expectEqual(1, exitCode(error.PromptDismissed));
    inline for (@typeInfo(Error).error_set.error_names.?) |e| {
        const msg = errorMessage(@field(Error, e));
        try testing.expect(msg.len > 0);
        try testing.expect(std.mem.findScalar(u8, msg, '\n') == null);
    }
}

/// A fake keyring, a DH client on it, and an output buffer.
const Fixture = struct {
    fake: FakeBus,
    client: TestClient,
    out: Io.Writer.Allocating,

    fn init(f: *Fixture) !void {
        f.fake = .init(testing.allocator);
        errdefer f.fake.deinit();
        f.client = try .init(testing.allocator, testing.io, &f.fake, .{});
        f.out = .init(testing.allocator);
    }

    fn deinit(f: *Fixture) void {
        f.out.deinit();
        f.client.deinit();
        f.fake.deinit();
    }

    fn run(f: *Fixture, action: Action, cli: Cli, input: []const u8) !void {
        var r: Io.Reader = .fixed(input);
        var req = try protocol.Request.parse(testing.allocator, &r, protocol.max_input_len);
        defer req.deinit(testing.allocator);
        try runAction(testing.allocator, &f.client, .{ .action = action, .cli = cli, .req = &req, .out = &f.out.writer });
    }

    fn output(f: *Fixture) []const u8 {
        return f.out.written();
    }

    fn reset(f: *Fixture) void {
        f.out.clearRetainingCapacity();
    }

    fn count(f: *Fixture) usize {
        return f.fake.items.items.len;
    }
};

fn cliFor(action: Action) Cli {
    return .{ .command = .{ .action = action } };
}

const legacy_github = [_]Attr{
    .{ .key = "xdg:schema", .value = "org.git.Password" },
    .{ .key = "user", .value = "alice" },
    .{ .key = "protocol", .value = "https" },
    .{ .key = "server", .value = "github.com" },
};

test "get: no match prints nothing" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.run(.get, cliFor(.get), "protocol=https\nhost=github.com\n\n");
    try testing.expectEqualStrings("", f.output());
}

test "get: prefers tagged, then newest; username from the item; unlocks" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    _ = try f.fake.addItem("Git: https://github.com/", &legacy_github, "legacy-newer", 5000, false);
    const tagged = legacy_github ++ [_]Attr{ .{ .key = "application", .value = "scm-auth" }, .{ .key = "tool", .value = "git" } };
    _ = try f.fake.addItem("scm-auth: https://github.com/", &tagged, "tagged-old\npassword_expiry_utc=99\noauth_refresh_token=rt", 10, true);
    _ = try f.fake.addItem("scm-auth: https://github.com/", &tagged, "tagged-older", 5, false);

    try f.run(.get, cliFor(.get), "protocol=https\nhost=github.com\n\n");
    try testing.expectEqualStrings(
        "username=alice\npassword=tagged-old\npassword_expiry_utc=99\noauth_refresh_token=rt\n",
        f.output(),
    );
    try testing.expectEqual(3, f.count());

    // A request username restricts the search like the stock helper.
    f.reset();
    try f.run(.get, cliFor(.get), "protocol=https\nhost=github.com\nusername=bob\n\n");
    try testing.expectEqualStrings("", f.output());
}

test "store: tagged item, legacy duplicates removed, others kept" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    _ = try f.fake.addItem("Git: https://github.com/", &legacy_github, "old", 10, true);
    const other_user = [_]Attr{ legacy_github[0], .{ .key = "user", .value = "bob" }, legacy_github[2], legacy_github[3] };
    _ = try f.fake.addItem("Git: https://github.com/", &other_user, "bob", 10, false);
    const with_object = legacy_github ++ [_]Attr{.{ .key = "object", .value = "o/r.git" }};
    _ = try f.fake.addItem("Git: https://github.com/o/r.git", &with_object, "obj", 10, false);
    const forge_tagged = legacy_github ++ [_]Attr{ .{ .key = "application", .value = "scm-auth" }, .{ .key = "tool", .value = "forge" } };
    _ = try f.fake.addItem("scm-auth: https://github.com/", &forge_tagged, "forge", 10, false);

    try f.run(.store, cliFor(.store), "protocol=https\nhost=github.com\nusername=alice\npassword=new\npassword_expiry_utc=4000000000\n\n");
    try testing.expectEqual(3, f.count());
    const item = &f.fake.items.items[f.count() - 1];
    try testing.expectEqualStrings("scm-auth: https://github.com/", item.label);
    try testing.expectEqualStrings("scm-auth", findAttr(item.attrs.items, "application").?);
    try testing.expectEqualStrings("git", findAttr(item.attrs.items, "tool").?);
    try testing.expectEqualStrings("org.git.Password", findAttr(item.attrs.items, "xdg:schema").?);
    try testing.expectEqualStrings("new\npassword_expiry_utc=4000000000", item.secret);

    // Another port is another credential; the tool and port are recorded.
    var cli = cliFor(.store);
    cli.tool = "forge";
    try f.run(.store, cli, "protocol=https\nhost=github.com:8443\npassword=p2\n\n");
    try testing.expectEqual(4, f.count());
    const ported = &f.fake.items.items[f.count() - 1];
    try testing.expectEqualStrings("scm-auth: https://github.com:8443/", ported.label);
    try testing.expectEqualStrings("8443", findAttr(ported.attrs.items, "port").?);
    try testing.expectEqualStrings("forge", findAttr(ported.attrs.items, "tool").?);
    try testing.expectEqual(null, findAttr(ported.attrs.items, "user"));
}

test "erase: password must match; without password all matches go" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    _ = try f.fake.addItem("Git: https://github.com/", &legacy_github, "pw1", 10, false);
    const tagged = legacy_github ++ [_]Attr{.{ .key = "application", .value = "scm-auth" }};
    _ = try f.fake.addItem("scm-auth: https://github.com/", &tagged, "pw2\noauth_refresh_token=t", 20, true);
    const elsewhere = [_]Attr{ legacy_github[0], legacy_github[2], .{ .key = "server", .value = "gitlab.com" } };
    _ = try f.fake.addItem("Git: https://gitlab.com/", &elsewhere, "pw1", 10, false);

    try f.run(.erase, cliFor(.erase), "protocol=https\nhost=github.com\npassword=nope\n\n");
    try testing.expectEqual(3, f.count());
    try f.run(.erase, cliFor(.erase), "protocol=https\nhost=github.com\npassword=pw2\n\n");
    try testing.expectEqual(2, f.count());
    try testing.expectEqualStrings("pw1", f.fake.items.items[0].secret);
    try f.run(.erase, cliFor(.erase), "protocol=https\nhost=github.com\n\n");
    try testing.expectEqual(1, f.count());
    try testing.expectEqualStrings("Git: https://gitlab.com/", f.fake.items.items[0].label);
    try testing.expectEqualStrings("", f.output());
}

test "list: tagged or all items, never secrets, sanitized" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    _ = try f.fake.addItem("Git: https://github.com/\x1b[31m", &legacy_github, "SECRET-1", 0, false);
    const tagged = legacy_github ++ [_]Attr{ .{ .key = "tool", .value = "git" }, .{ .key = "application", .value = "scm-auth" } };
    _ = try f.fake.addItem("scm-auth: https://github.com/", &tagged, "SECRET-2", 1762358400, true);

    try f.run(.list, cliFor(.list), "");
    try testing.expectEqualStrings(
        "2025-11-05T16:00:00Z\tscm-auth: https://github.com/\tapplication=scm-auth protocol=https server=github.com tool=git user=alice xdg:schema=org.git.Password\n",
        f.output(),
    );
    f.reset();
    var cli = cliFor(.list);
    cli.all = true;
    try f.run(.list, cli, "");
    try testing.expect(std.mem.startsWith(u8, f.output(), "1970-01-01T00:00:00Z\tGit: https://github.com/?[31m\t"));
    try testing.expectEqual(2, std.mem.count(u8, f.output(), "\n"));
    try testing.expect(std.mem.find(u8, f.output(), "SECRET") == null);
}

test "writeTime" {
    var buf: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    try writeTime(&w, 951782400); // leap day
    try writeTime(&w, max_iso_seconds + 1);
    try testing.expectEqualStrings("2000-02-29T00:00:00Z@253402300800", w.buffered());
}

test "retag: preview changes nothing; apply tags, relabels and dedupes" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    _ = try f.fake.addItem("Git: https://github.com/", &legacy_github, "older", 10, false);
    const newest = try f.fake.addItem("Git: https://github.com/", &legacy_github, "newest", 30, true);
    _ = try f.fake.addItem("Git: https://github.com/", &legacy_github, "middle", 20, false);
    const forge_attrs = [_]Attr{ legacy_github[0], legacy_github[2], .{ .key = "server", .value = "codeberg.org" } };
    const forge_item = try f.fake.addItem("forge: codeberg.org", &forge_attrs, "f", 10, false);
    const done_attrs = [_]Attr{ legacy_github[0], legacy_github[2], .{ .key = "server", .value = "h.test" }, .{ .key = "application", .value = "scm-auth" }, .{ .key = "tool", .value = "hf" } };
    _ = try f.fake.addItem("scm-auth: https://h.test/", &done_attrs, "x", 10, false);
    const bad_port = [_]Attr{ legacy_github[0], .{ .key = "port", .value = "http" } };
    _ = try f.fake.addItem("weird", &bad_port, "x", 10, false);
    const foreign = [_]Attr{.{ .key = "xdg:schema", .value = "org.other" }};
    _ = try f.fake.addItem("foreign", &foreign, "x", 10, false);

    try f.run(.retag, cliFor(.retag), "");
    try testing.expectEqual(7, f.count());
    try testing.expectEqual(0, f.fake.deletes);
    try testing.expectEqualStrings("Git: https://github.com/", f.fake.find(newest).?.label);
    const preview = f.output();
    try testing.expect(std.mem.find(u8, preview, "retag   forge: codeberg.org -> scm-auth: https://codeberg.org/ (tool=forge)\n") != null);
    try testing.expect(std.mem.find(u8, preview, "ok      scm-auth: https://h.test/\n") != null);
    try testing.expect(std.mem.find(u8, preview, "skip    weird (unparsable port attribute)\n") != null);
    try testing.expectEqual(2, std.mem.count(u8, preview, "delete  Git: https://github.com/ (older duplicate of scm-auth: https://github.com/)\n"));
    try testing.expect(std.mem.endsWith(u8, preview, "retag: 2 to update, 2 duplicate(s) to delete, 1 already tagged, 1 skipped (preview; run with --apply to change)\n"));
    try testing.expect(std.mem.find(u8, preview, "newest") == null);

    f.reset();
    var cli = cliFor(.retag);
    cli.apply = true;
    try f.run(.retag, cli, "");
    try testing.expectEqual(5, f.count());
    const kept = f.fake.find(newest).?;
    try testing.expectEqualStrings("newest", kept.secret);
    try testing.expectEqualStrings("scm-auth: https://github.com/", kept.label);
    try testing.expectEqualStrings("scm-auth", findAttr(kept.attrs.items, "application").?);
    try testing.expectEqualStrings("git", findAttr(kept.attrs.items, "tool").?);
    try testing.expectEqualStrings("alice", findAttr(kept.attrs.items, "user").?);
    const forge = f.fake.find(forge_item).?;
    try testing.expectEqualStrings("forge", findAttr(forge.attrs.items, "tool").?);
    try testing.expectEqualStrings("scm-auth: https://codeberg.org/", forge.label);

    // A second run has nothing left to do.
    f.reset();
    try f.run(.retag, cli, "");
    try testing.expect(std.mem.endsWith(u8, f.output(), "retag: 0 to update, 0 duplicate(s) to delete, 3 already tagged, 1 skipped\n"));
}

test "actions survive every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, struct {
        fn run(gpa: Allocator) !void {
            var fake: FakeBus = .init(testing.allocator);
            defer fake.deinit();
            fake.msg_gpa = gpa;
            _ = try fake.addItem("Git: https://h/", &.{
                .{ .key = "xdg:schema", .value = "org.git.Password" },
                .{ .key = "protocol", .value = "https" },
                .{ .key = "server", .value = "h" },
            }, "old", 1, false);
            var c = try TestClient.init(gpa, testing.io, &fake, .{ .allow_plain = true });
            defer c.deinit();
            // A fixed writer: Allocating would turn OOM into WriteFailed.
            var out_buf: [4096]u8 = undefined;
            var out: Io.Writer = .fixed(&out_buf);
            var r: Io.Reader = .fixed("protocol=https\nhost=h\npassword=pw\n\n");
            var req = try protocol.Request.parse(gpa, &r, protocol.max_input_len);
            defer req.deinit(gpa);
            const actions = [_]Action{ .store, .get, .list, .retag, .erase };
            for (actions) |action| {
                var cli = cliFor(action);
                cli.apply = action == .retag;
                out.end = 0;
                try runAction(gpa, &c, .{ .action = action, .cli = cli, .req = &req, .out = &out });
            }
            try c.closeSession();
        }
    }.run, .{});
}
