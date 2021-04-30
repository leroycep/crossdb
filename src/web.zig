const std = @import("std");
const crossdb = @import("./main.zig");

const CrossDBError = crossdb.CrossDBError;
const OpenOptions = crossdb.OpenOptions;
const StoreOptions = crossdb.StoreOptions;
const TransactionOptions = crossdb.TransactionOptions;

pub const Database = struct {
    web_db: *bindings.WebDatabase,

    pub fn open(name: []const u8, options: OpenOptions) CrossDBError!@This() {
        var dbhandle: ?*bindings.WebDatabase = null;
        suspend bindings.databaseOpen(name.ptr, name.len, @intCast(u32, options.version), @ptrToInt(@frame()), @ptrToInt(&options), &dbhandle);
        if (dbhandle) |handle| {
            return @This(){
                .web_db = handle,
            };
        } else {
            return error.CannotOpen;
        }
    }

    pub fn delete(name: []const u8) CrossDBError!void {
        // TODO: Listen for errors
        bindings.databaseDelete(name.ptr, name.len);
    }

    pub fn begin(this: *@This(), storeNames: []const []const u8, options: TransactionOptions) CrossDBError!Transaction {
        const store_name_list = bindings.listInit();
        defer bindings.listFree(store_name_list);
        for (storeNames) |storeName| {
            bindings.listAppendString(store_name_list, storeName.ptr, storeName.len);
        }

        const res = bindings.databaseBegin(this.web_db, store_name_list);
        if (res) |txn| {
            return Transaction{ .web_txn = txn };
        } else {
            return error.UnknownStore;
        }
    }

    pub fn createStore(this: *@This(), storeName: []const u8, options: StoreOptions) CrossDBError!void {
        bindings.databaseCreateStore(this.web_db, storeName.ptr, storeName.len);
    }
};

pub const Transaction = struct {
    web_txn: *bindings.WebTransaction,

    pub fn commit(this: *@This()) CrossDBError!void {
        suspend bindings.transactionCommit(this.web_txn, @ptrToInt(@frame()));
    }

    pub fn store(this: *@This(), storeName: []const u8) CrossDBError!Store {
        if (bindings.transactionStore(this.web_txn, storeName.ptr, storeName.len)) |store_handle| {
            return Store{ .web_store = store_handle };
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

    // TODO: Replace with interface that uses allocation
    valOut: [1024]u8 = undefined,

    /// Remove handle to this store
    pub fn release(this: @This()) void {
        bindings.storeRelease(this.web_store);
    }

    pub fn put(this: *@This(), key: []const u8, value: []const u8) CrossDBError!void {
        bindings.storePut(this.web_store, key.ptr, key.len, value.ptr, value.len);
    }

    pub fn get(this: *@This(), key: []const u8) CrossDBError!?[]const u8 {
        var val: ?[]const u8 = undefined;
        suspend bindings.storeGet(this.web_store, @ptrToInt(@frame()), key.ptr, key.len, &val, &this.valOut, this.valOut.len);
        return val;
    }
};

export fn crossdb_upgradeNeeded(userdata: usize, database: *bindings.WebDatabase, oldVersion: u32, newVersion: u32) callconv(.C) void {
    const options = @intToPtr(*const OpenOptions, userdata);
    var db = Database{
        .web_db = database,
    };

    return options.onupgrade(&db, oldVersion, newVersion) catch |err| {
        std.log.err("Error upgrading: {}", .{err});
        unreachable;
    };
}

export fn crossdb_finishOpen(framePtr: usize, userdata: usize, dbout: *?*bindings.WebDatabase, database: ?*bindings.WebDatabase) void {
    dbout.* = database;

    const frame = @intToPtr(anyframe, framePtr);
    resume frame;
}

export fn crossdb_finish_storeGet(framePtr: usize, valout: *?[]const u8, valPtrOpt: ?[*]const u8, valLen: usize) void {
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
    extern "crossdb" fn storeGet(store: *WebStore, framePtr: usize, keyPtr: [*]const u8, keyLen: usize, valOut: *?[]const u8, valPtr: [*]const u8, valLen: usize) void;
};
