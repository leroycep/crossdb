const std = @import("std");
const builtin = @import("builtin");

pub const CrossDBError = error{
    Unimplemented,
    CannotOpen,
    VersionTooLarge,
    UpgradeFailed,
    UnknownStore,
};

pub const OpenOptions = struct {
    version: u32,
    onupgrade: fn (db: *Database, oldVersion: u32, newVersion: u32) anyerror!void,
};

pub const StoreOptions = struct {};

pub const TransactionOptions = struct {
    readonly: bool = false,
};

const system = if (builtin.arch == .wasm32) @import("./web.zig") else @import("./lmdb.zig");

pub const Database = system.Database;
pub const Transaction = system.Transaction;
