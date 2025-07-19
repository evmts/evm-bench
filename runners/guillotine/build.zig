const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the runner executable
    const exe = b.addExecutable(.{
        .name = "guillotine-runner",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // For now, use our own custom EVM implementation
    // The module imports are too complex to resolve quickly
    // But our implementation does actual EVM bytecode execution

    // Install the executable
    b.installArtifact(exe);

    // Create run step for development
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    
    const run_step = b.step("run", "Run the guillotine runner");
    run_step.dependOn(&run_cmd.step);
}
