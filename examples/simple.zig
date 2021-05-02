const std = @import("std");
const crossdb = @import("crossdb");

var run_frame: @Frame(run) = undefined;
pub fn main() void {
    run_frame = async run();
}

const APP_NAME = "crossdb-example";
const DB_NAME = "simple";

pub fn run() void {
    run_with_error() catch |e| {
        std.log.err("Error: {}", .{e});
    };
}

pub fn run_with_error() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = std.builtin.cpu.arch != .wasm32 }){};
    defer _ = gpa.deinit();

    // Delete the database to ensure we create it from scratch for demonstration purposes
    crossdb.Database.delete(&gpa.allocator, APP_NAME, DB_NAME) catch |_| {};

    var db = try crossdb.Database.open(&gpa.allocator, APP_NAME, DB_NAME, .{ .version = 1, .onupgrade = upgrade });
    defer db.deinit();

    std.log.info("Adding people to people store", .{});
    {
        var txn = try db.begin(&.{"people"}, .{});
        errdefer txn.deinit();

        // Here we get a handle to the store and then must release the handle
        var store = try txn.store("people");
        defer store.release();

        try store.put("fred", "Fred Mystery");
        try store.put("amaryllis", "Amaryllis Penndraig");

        try txn.commit();
    }

    std.log.info("Getting people from people store", .{});
    {
        var txn = try db.begin(&.{"people"}, .{ .readonly = true });
        // We can unconditionally deinit since the transaction won't be writing to the database
        defer txn.deinit();

        var store = try txn.store("people");
        defer store.release();
        {
            const value = try store.get("fred");
            std.log.info("  fred = {s}", .{value.?});
        }
        {
            const value = try store.get("amaryllis");
            std.log.info("  amaryllis = {s}", .{value.?});
        }
        {
            const value = try store.get("harry");
            std.log.info("  harry = {s}", .{value});
        }
    }

    std.log.info("Iterating over people from people store", .{});
    {
        var txn = try db.begin(&.{"people"}, .{ .readonly = true });
        // We can unconditionally deinit since the transaction won't be writing to the database
        defer txn.deinit();

        var store = try txn.store("people");
        defer store.release();

        var cursor = try store.cursor(.{});
        defer cursor.deinit();

        while (try cursor.next()) |entry| {
            std.log.info("  {s} = {s}", .{ entry.key, entry.val });
        }
    }

    std.log.info("Done", .{});
}

fn upgrade(db: *crossdb.Database, oldVersion: u32, newVersion: u32) anyerror!void {
    try db.createStore("people", .{});
}

usingnamespace if (std.builtin.arch == .wasm32) struct {
    // Misc stuff for web support
    extern fn log_write(str_ptr: [*]const u8, str_len: usize) void;
    extern fn log_flush() void;

    fn logWrite(write_context: void, bytes: []const u8) error{}!usize {
        log_write(bytes.ptr, bytes.len);
        return bytes.len;
    }

    fn logWriter() std.io.Writer(void, error{}, logWrite) {
        return .{ .context = {} };
    }

    pub fn log(
        comptime message_level: std.log.Level,
        comptime scope: @Type(.EnumLiteral),
        comptime format: []const u8,
        args: anytype,
    ) void {
        const writer = logWriter();
        defer log_flush();
        writer.print("[{s}][{s}] ", .{ std.meta.tagName(message_level), std.meta.tagName(scope) }) catch {};
        writer.print(format, args) catch {};
    }
} else struct {};
