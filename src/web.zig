const std = @import("std");
const crossdb = @import("./main.zig");

const CrossDBError = crossdb.CrossDBError;
const OpenOptions = crossdb.OpenOptions;
const StoreOptions = crossdb.StoreOptions;
const TransactionOptions = crossdb.TransactionOptions;

pub const Database = struct {
    allocator: *std.mem.Allocator,
    web_db: *bindings.WebDatabase,
    options: OpenOptions,

    pub fn open(allocator: *std.mem.Allocator, appName: []const u8, name: []const u8, options: OpenOptions) CrossDBError!@This() {
        const db_name = std.fmt.allocPrint(allocator, "{s}_{s}", .{ appName, name }) catch return error.Unknown;
        defer allocator.free(db_name);

        var this = @This(){
            .allocator = allocator,
            .options = options,
            .web_db = undefined,
        };

        var dbhandle: ?*bindings.WebDatabase = null;
        suspend bindings.databaseOpen(db_name.ptr, db_name.len, @intCast(u32, options.version), @ptrToInt(@frame()), @ptrToInt(&this), &dbhandle);
        if (dbhandle) |handle| {
            this.web_db = handle;
            return this;
        } else {
            return error.CannotOpen;
        }
    }

    pub fn delete(allocator: *std.mem.Allocator, appName: []const u8, name: []const u8) CrossDBError!void {
        const db_name = std.fmt.allocPrint(allocator, "{s}_{s}", .{ appName, name }) catch return error.Unknown;
        defer allocator.free(db_name);

        // TODO: Listen for errors
        bindings.databaseDelete(db_name.ptr, db_name.len);
    }

    pub fn begin(this: *@This(), storeNames: []const []const u8, options: TransactionOptions) CrossDBError!Transaction {
        const store_name_list = bindings.listInit();
        defer bindings.listFree(store_name_list);
        for (storeNames) |storeName| {
            bindings.listAppendString(store_name_list, storeName.ptr, storeName.len);
        }

        const res = bindings.databaseBegin(this.web_db, store_name_list);
        if (res) |txn| {
            return Transaction{ .allocator = this.allocator, .web_txn = txn };
        } else {
            return error.UnknownStore;
        }
    }

    pub fn createStore(this: *@This(), storeName: []const u8, options: StoreOptions) CrossDBError!void {
        bindings.databaseCreateStore(this.web_db, storeName.ptr, storeName.len);
    }
};

pub const Transaction = struct {
    allocator: *std.mem.Allocator,
    web_txn: *bindings.WebTransaction,

    pub fn commit(this: *@This()) CrossDBError!void {
        suspend bindings.transactionCommit(this.web_txn, @ptrToInt(@frame()));
    }

    pub fn store(this: *@This(), storeName: []const u8) CrossDBError!Store {
        if (bindings.transactionStore(this.web_txn, storeName.ptr, storeName.len)) |store_handle| {
            return Store{ .allocator = this.allocator, .web_store = store_handle };
        } else {
            return error.UnknownStore;
        }
    }

    pub fn deinit(this: @This()) void {
        bindings.transactionDeinit(this.web_txn);
    }
};

pub const Store = struct {
    web_store: *bindings.WebStore,
    allocator: *std.mem.Allocator,
    val_out: ?[]u8 = null,

    pub fn init(allocator: *std.mem.Allocator, store: *bindings.WebStore) !void {
        return @This(){
            .allocator = allocator,
            .web_store = store,
        };
    }

    /// Remove handle to this store
    pub fn release(this: @This()) void {
        bindings.storeRelease(this.web_store);
        if (this.val_out) |val_out| {
            this.allocator.free(val_out);
        }
    }

    pub fn put(this: *@This(), key: []const u8, value: []const u8) CrossDBError!void {
        bindings.storePut(this.web_store, key.ptr, key.len, value.ptr, value.len);
    }

    pub fn get(this: *@This(), key: []const u8) CrossDBError!?[]const u8 {
        if (this.val_out) |val_out| {
            this.allocator.free(val_out);
        }
        var val: ?[]u8 = undefined;
        suspend bindings.storeGet(this.web_store, @ptrToInt(@frame()), key.ptr, key.len, this.allocator, &val);
        this.val_out = val;
        return val;
    }
};

export fn crossdb_upgradeNeeded(userdata: usize, database: *bindings.WebDatabase, oldVersion: u32, newVersion: u32) callconv(.C) void {
    const db = @intToPtr(*Database, userdata);
    db.web_db = database;

    return db.options.onupgrade(db, oldVersion, newVersion) catch |err| {
        std.log.err("Error upgrading: {}", .{err});
        unreachable;
    };
}

export fn crossdb_finishOpen(framePtr: usize, userdata: usize, dbout: *?*bindings.WebDatabase, database: ?*bindings.WebDatabase) void {
    dbout.* = database;

    const frame = @intToPtr(anyframe, framePtr);
    resume frame;
}

export fn crossdb_alloc(allocator: *std.mem.Allocator, byteLen: usize) ?[*]u8 {
    const slice = allocator.alloc(u8, byteLen) catch return null;
    return slice.ptr;
}

export fn crossdb_finish_storeGet(framePtr: usize, valout: *?[]u8, valPtrOpt: ?[*]u8, valLen: usize) void {
    if (valPtrOpt) |valPtr| {
        valout.* = valPtr[0..valLen];
    } else {
        valout.* = null;
    }

    const frame = @intToPtr(anyframe, framePtr);
    resume frame;
}

export fn crossdb_finish_transactionCommit(framePtr: usize) void {
    const frame = @intToPtr(anyframe, framePtr);
    resume frame;
}

const bindings = struct {
    const WebList = opaque {};
    extern "crossdb" fn listInit() *WebList;
    extern "crossdb" fn listAppendString(*WebList, ptr: [*]const u8, len: usize) void;
    extern "crossdb" fn listFree(*WebList) void;

    const WebDatabase = opaque {};
    extern "crossdb" fn databaseOpen(namePtr: [*]const u8, nameLen: usize, version: u32, frame: usize, userdata: usize, dbout: *?*WebDatabase) void;
    extern "crossdb" fn databaseDelete(namePtr: [*]const u8, nameLen: usize) void;
    extern "crossdb" fn databaseBegin(db: *WebDatabase, storeNameList: *WebList) ?*WebTransaction;
    extern "crossdb" fn databaseCreateStore(db: *WebDatabase, storeNamePtr: [*]const u8, storeNameLen: usize) void;

    const WebTransaction = opaque {};
    extern "crossdb" fn transactionStore(txn: *WebTransaction, storeNamePtr: [*]const u8, storeNameLen: usize) ?*WebStore;
    extern "crossdb" fn transactionDeinit(txn: *WebTransaction) void;
    extern "crossdb" fn transactionCommit(txn: *WebTransaction, framePtr: usize) void;

    const WebStore = opaque {};
    extern "crossdb" fn storeRelease(store: *WebStore) void;
    extern "crossdb" fn storePut(store: *WebStore, keyPtr: [*]const u8, keyLen: usize, valPtr: [*]const u8, valLen: usize) void;
    extern "crossdb" fn storeGet(store: *WebStore, framePtr: usize, keyPtr: [*]const u8, keyLen: usize, allocator: *std.mem.Allocator, valOut: *?[]u8) void;
};
