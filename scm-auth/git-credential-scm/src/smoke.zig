//! Developer smoke test against a real Secret Service: connects to the
//! session bus, negotiates the DH session through `secret.Client`, prints
//! the bus and service names, and closes the session. Reads no keyring
//! items, so it is safe on the live keyring. Not installed; run with
//! `zig build smoke`.

const std = @import("std");
const conn = @import("dbus/conn.zig");
const secret = @import("secret.zig");

pub fn main(init: std.process.Init) u8 {
    run(init) catch |err| {
        std.debug.print("smoke: {s}\n", .{@errorName(err)});
        return 1;
    };
    return 0;
}

fn run(init: std.process.Init) !void {
    const gpa = init.gpa;
    const bus = try gpa.create(conn.Bus);
    defer gpa.destroy(bus);
    try bus.openSession(gpa, init.io, init.environ_map);
    defer bus.close();
    std.debug.print("unique name: {s}\n", .{bus.conn.uniqueName()});

    var client = try secret.Client.init(gpa, init.io, &bus.conn, .{ .allow_plain = secret.plainAllowed(init.environ_map) });
    defer client.deinit();
    std.debug.print("{s} owner: {s}\n", .{ secret.service_name, client.owner() });
    std.debug.print("session: {s} ({s})\n", .{ client.session_path, @tagName(client.transfer) });
    try client.closeSession();
    std.debug.print("session closed\n", .{});
}
