const std = @import("std");
const crossdb = @import("crossdb");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(&gpa.allocator);
    defer std.process.argsFree(&gpa.allocator, args);

    const cwd = std.fs.cwd();
    const dir = try cwd.makeOpenPath(args[1], .{});

    try crossdb.installJS(dir);
}
