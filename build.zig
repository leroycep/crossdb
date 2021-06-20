const std = @import("std");
const deps = @import("deps.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const native = b.addExecutable("simple", "examples/simple.zig");
    native.setBuildMode(mode);
    native.setTarget(target);
    deps.addAllTo(native);
    native.install();

    const build_native = b.step("native", "Build native example");
    build_native.dependOn(&native.step);

    const native_run = native.run();
    const native_run_step = b.step("run", "Run native binary");
    native_run_step.dependOn(&native_run.step);

    const web = b.addSharedLibrary("simple", "examples/simple.zig", .unversioned);
    web.addPackagePath("crossdb", "src/main.zig");
    web.setBuildMode(mode);
    web.setTarget(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    web.override_dest_dir = .bin;
    web.install();

    const copy_simple_html = b.addInstallBinFile(.{ .path = "examples/simple.html" }, "simple.html");
    const copy_crossdb_js = b.addInstallBinFile(.{ .path = "src/crossdb.js" }, "crossdb.js");

    const build_web = b.step("web", "Build WASM example");
    build_web.dependOn(&web.step);
    build_web.dependOn(&web.install_step.?.step);
    build_web.dependOn(&copy_simple_html.step);
    build_web.dependOn(&copy_crossdb_js.step);
}
