const std = @import("std");
const crossdb = @import("./main.zig");

const CrossDBError = crossdb.CrossDBError;
const OpenOptions = crossdb.OpenOptions;
const StoreOptions = crossdb.StoreOptions;
const TransactionOptions = crossdb.TransactionOptions;

pub const Database = struct {
    pub fn open(allocator: *std.mem.Allocator, appName: []const u8, name: []const u8, options: OpenOptions) CrossDBError!@This() {
        unreachable;
    }

    pub fn delete(name: []const u8) CrossDBError!void {
        unreachable;
    }

    pub fn begin(this: *@This(), storeNames: []const []const u8, options: TransactionOptions) CrossDBError!Transaction {
        unreachable;
    }

    pub fn createStore(this: *@This(), storeName: []const u8, options: StoreOptions) CrossDBError!void {
        unreachable;
    }
};

pub const Transaction = struct {
    pub fn commit(this: *@This()) CrossDBError!void {
        unreachable;
    }

    pub fn store(this: *@This(), storeName: []const u8) CrossDBError!Store {
        unreachable;
    }

    pub fn deinit(this: @This()) void {
        unreachable;
    }
};

pub const Store = struct {
    /// Remove handle to this store
    pub fn release(this: @This()) void {
        unreachable;
    }

    pub fn put(this: *@This(), key: []const u8, value: []const u8) CrossDBError!void {
        unreachable;
    }

    pub fn get(this: *@This(), key: []const u8) CrossDBError!?[]const u8 {
        unreachable;
    }
};
