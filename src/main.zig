const std = @import("std");
const builtin = @import("builtin");

pub const CrossDBError = error{
    Unknown,
    CannotOpen,
    VersionTooLarge,
    UpgradeFailed,
    UnknownStore,
    OutOfMemory,
};

pub const OpenOptions = struct {
    version: u32,
    onupgrade: fn (db: *Database, oldVersion: u32, newVersion: u32) anyerror!void,
};

pub const StoreOptions = struct {};

pub const TransactionOptions = struct {
    readonly: bool = false,
};

pub const CursorOptions = struct {};

pub const CursorEntry = struct {
    key: []const u8,
    val: []const u8,
};

const system = if (builtin.cpu.arch == .wasm32) @import("./web.zig") else @import("./lmdb.zig");

pub const Database = system.Database;
pub const Transaction = system.Transaction;

pub fn installJS(dir: std.fs.Dir) !void {
    try dir.writeFile("crossdb.js", @embedFile("crossdb.js"));
}
