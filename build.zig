const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const zbit_optimize = b.option(
        std.builtin.OptimizeMode,
        "zencode-optimize",
        "Prioritize performance, safety, or binary size (-O flag), defaults to value of optimize option",
    ) orelse b.standardOptimizeOption(.{});

    const zencode = b.dependency("zencode", .{}).module("zencode");

    const exe = b.addExecutable(.{
        .name = "zbit",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = zbit_optimize,
    });
    b.installArtifact(exe);
    exe.root_module.addImport("zencode", zencode);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/unit_tests.zig"),
        .target = target,
        .optimize = zbit_optimize,
    });
    unit_tests.root_module.addImport("zencode", zencode);

    const run_exe_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
