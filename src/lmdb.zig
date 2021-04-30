const std = @import("std");
const crossdb = @import("./main.zig");
const lmdb = @import("lmdb");
const log = std.log.scoped(.crossdb);

const CrossDBError = crossdb.CrossDBError;
const OpenOptions = crossdb.OpenOptions;
const StoreOptions = crossdb.StoreOptions;
const TransactionOptions = crossdb.TransactionOptions;

pub const Database = struct {
    env: lmdb.Environment,
    metaDB: lmdb.Database,

    pub fn open(name: [:0]const u8, options: OpenOptions) CrossDBError!@This() {
        const cwd = std.fs.cwd();
        cwd.makePath(name) catch unreachable;

        // TODO: Patch lmdb-zig to make list of possible errors explicit
        const env = lmdb.Environment.init(name, .{
            .max_num_dbs = 50,
        }) catch unreachable;

        const metaDB = get_metaDB: {
            const txn = env.begin(.{}) catch unreachable;
            errdefer txn.deinit();

            const metaDB = txn.use("__crossdb_meta", .{ .create_if_not_exists = true }) catch unreachable;
            txn.commit() catch unreachable;

            break :get_metaDB metaDB;
        };

        var this = @This(){
            .env = env,
            .metaDB = metaDB,
        };

        const version = get_version: {
            const txn = env.begin(.{ .read_only = true }) catch unreachable;
            defer txn.deinit();

            const version_bytes = txn.get(metaDB, "version") catch |err| switch (err) {
                error.NotFound => break :get_version 0,
                else => |e| unreachable,
            };
            break :get_version std.mem.readIntBig(u32, version_bytes[0..4]);
        };

        if (version < options.version) {
            options.onupgrade(&this, version, options.version) catch return error.UpgradeFailed;

            var version_bytes: [4]u8 = undefined;
            std.mem.writeIntBig(u32, &version_bytes, options.version);

            const txn = env.begin(.{}) catch unreachable;
            defer txn.deinit();
            txn.put(metaDB, "version", &version_bytes, .{}) catch unreachable;
        } else if (version > options.version) {
            log.err("Version number on disk is larger than version provided: {} > {}", .{ version, options.version });
            return error.VersionTooLarge;
        }

        return this;
    }

    pub fn delete(name: []const u8) CrossDBError!void {
        const cwd = std.fs.cwd();
        cwd.deleteTree(name) catch unreachable;
    }

    pub fn begin(this: *@This(), storeNames: []const []const u8, options: TransactionOptions) CrossDBError!Transaction {
        const txn = this.env.begin(.{}) catch unreachable;
        return Transaction{ .env = this.env, .txn = txn };
    }

    pub fn createStore(this: *@This(), storeName: [:0]const u8, options: StoreOptions) CrossDBError!void {
        const txn = this.env.begin(.{}) catch unreachable;
        _ = txn.use(storeName, .{ .create_if_not_exists = true }) catch unreachable;
        txn.commit() catch unreachable;
    }
};

pub const Transaction = struct {
    env: lmdb.Environment,
    txn: lmdb.Transaction,

    pub fn commit(this: *@This()) CrossDBError!void {
        this.txn.commit() catch unreachable;
    }

    pub fn store(this: *@This(), storeName: []const u8) CrossDBError!Store {
        const db = this.txn.use(storeName, .{}) catch |err| switch (err) {
            error.NotFound => return error.UnknownStore,
            else => |e| std.debug.panic("Unknown error: {}", .{e}),
        };
        return Store{ .env = this.env, .txn = this.txn, .db = db };
    }

    pub fn deinit(this: @This()) void {
        this.txn.deinit();
    }
};

pub const Store = struct {
    env: lmdb.Environment,
    txn: lmdb.Transaction,
    db: lmdb.Database,

    /// Remove handle to this store
    pub fn release(this: @This()) void {
        this.db.close(this.env);
    }

    pub fn put(this: *@This(), key: []const u8, value: []const u8) CrossDBError!void {
        this.txn.put(this.db, key, value, .{}) catch unreachable;
    }

    pub fn get(this: *@This(), key: []const u8) CrossDBError!?[]const u8 {
        return this.txn.get(this.db, key) catch |err| switch (err) {
            error.NotFound => return null,
            else => unreachable,
        };
    }
};
