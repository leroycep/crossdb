const std = @import("std");
const crossdb = @import("./main.zig");
const lmdb = @import("lmdb");
const log = std.log.scoped(.crossdb);

const CrossDBError = crossdb.CrossDBError;
const OpenOptions = crossdb.OpenOptions;
const StoreOptions = crossdb.StoreOptions;
const TransactionOptions = crossdb.TransactionOptions;
const CursorOptions = crossdb.CursorOptions;
const CursorEntry = crossdb.CursorEntry;

pub const Database = struct {
    allocator: *std.mem.Allocator,
    env: lmdb.Environment,
    metaDB: lmdb.Database,
    databases: std.StringHashMap(lmdb.Database),

    pub fn open(allocator: *std.mem.Allocator, appName: []const u8, name: []const u8, options: OpenOptions) CrossDBError!@This() {
        const app_data_dir = std.fs.getAppDataDir(allocator, appName) catch return error.Unknown;
        defer allocator.free(app_data_dir);

        const path = std.fs.path.join(allocator, &.{ app_data_dir, name }) catch return error.Unknown;
        defer allocator.free(path);

        const cwd = std.fs.cwd();
        cwd.makePath(path) catch return error.CannotOpen;

        // TODO: Patch lmdb-zig to make list of possible errors explicit
        const env = lmdb.Environment.init(path, .{
            .max_num_dbs = 50,
        }) catch return error.CannotOpen;

        const metaDB = get_metaDB: {
            const txn = env.begin(.{}) catch return error.CannotOpen;
            errdefer txn.deinit();

            const metaDB = txn.use("__crossdb_meta", .{ .create_if_not_exists = true }) catch return error.CannotOpen;
            txn.commit() catch unreachable;

            break :get_metaDB metaDB;
        };

        var this = @This(){
            .allocator = allocator,
            .env = env,
            .metaDB = metaDB,
            .databases = std.StringHashMap(lmdb.Database).init(allocator),
        };

        const version = get_version: {
            const txn = env.begin(.{ .read_only = true }) catch return error.CannotOpen;
            defer txn.deinit();

            const version_bytes = txn.get(metaDB, "version") catch |err| switch (err) {
                error.NotFound => break :get_version 0,
                else => return error.CannotOpen,
            };
            break :get_version std.mem.readIntBig(u32, version_bytes[0..4]);
        };

        if (version < options.version) {
            options.onupgrade(&this, version, options.version) catch return error.UpgradeFailed;

            var version_bytes: [4]u8 = undefined;
            std.mem.writeIntBig(u32, &version_bytes, options.version);

            const txn = env.begin(.{}) catch return error.CannotOpen;
            defer txn.deinit();
            txn.put(metaDB, "version", &version_bytes, .{}) catch unreachable;
        } else if (version > options.version) {
            log.err("Version number on disk is larger than version provided: {} > {}", .{ version, options.version });
            return error.VersionTooLarge;
        }

        return this;
    }

    pub fn deinit(this: *@This()) void {
        this.databases.deinit();
        this.env.deinit();
    }

    pub fn delete(allocator: *std.mem.Allocator, appName: []const u8, name: []const u8) CrossDBError!void {
        const app_data_dir = std.fs.getAppDataDir(allocator, appName) catch return error.Unknown;
        defer allocator.free(app_data_dir);

        const path = std.fs.path.join(allocator, &.{ app_data_dir, name }) catch return error.Unknown;
        defer allocator.free(path);

        const cwd = std.fs.cwd();
        cwd.deleteTree(path) catch return error.Unknown;
    }

    pub fn begin(this: *@This(), storeNames: []const []const u8, options: TransactionOptions) CrossDBError!Transaction {
        const txn = this.env.begin(.{}) catch return error.Unknown;
        return Transaction{ .db = this, .txn = txn };
    }

    pub fn createStore(this: *@This(), storeName: [:0]const u8, options: StoreOptions) CrossDBError!void {
        const txn = this.env.begin(.{}) catch return error.Unknown;
        _ = txn.use(storeName, .{ .create_if_not_exists = true }) catch return error.Unknown;
        txn.commit() catch return error.Unknown;
    }
};

pub const Transaction = struct {
    db: *Database,
    txn: lmdb.Transaction,

    pub fn commit(this: *@This()) CrossDBError!void {
        this.txn.commit() catch |e| {
            std.log.err("commit error: {}", .{e});
            return error.Unknown;
        };
    }

    pub fn store(this: *@This(), storeName: []const u8) CrossDBError!Store {
        const gop = this.db.databases.getOrPut(storeName) catch return error.OutOfMemory;

        if (!gop.found_existing) {
            gop.value_ptr.* = this.txn.use(storeName, .{}) catch |err| switch (err) {
                error.NotFound => return error.UnknownStore,
                else => |e| std.debug.panic("Unknown error: {}", .{e}),
            };
        }

        return Store{ .txn = this, .db = gop.value_ptr.* };
    }

    pub fn deinit(this: @This()) void {
        this.txn.deinit();
    }
};

pub const Store = struct {
    txn: *Transaction,
    db: lmdb.Database,

    /// Remove handle to this store
    pub fn release(this: @This()) void {}

    pub fn put(this: *@This(), key: []const u8, value: []const u8) CrossDBError!void {
        this.txn.txn.put(this.db, key, value, .{}) catch return error.Unknown;
    }

    pub fn get(this: *@This(), key: []const u8) CrossDBError!?[]const u8 {
        return this.txn.txn.get(this.db, key) catch |err| switch (err) {
            error.NotFound => return null,
            else => return error.Unknown,
        };
    }

    pub fn cursor(this: *@This(), options: CursorOptions) CrossDBError!Cursor {
        const lmdb_cursor = this.txn.txn.cursor(this.db) catch |err| switch (err) {
            else => return error.Unknown,
        };
        return Cursor{
            .cursor = lmdb_cursor,
            .op = .first,
        };
    }
};

pub const Cursor = struct {
    cursor: lmdb.Cursor,
    op: lmdb.Cursor.Position,

    pub fn next(this: *@This()) CrossDBError!?CursorEntry {
        const res = this.cursor.get(this.op) catch return error.Unknown;
        if (res) |entry| {
            this.op = .next;

            return CursorEntry{
                .key = entry.key,
                .val = entry.val,
            };
        }
        return null;
    }

    pub fn deinit(this: @This()) void {
        this.cursor.deinit();
    }
};
