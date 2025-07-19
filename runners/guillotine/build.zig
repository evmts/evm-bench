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

    // TODO: Add Guillotine as a dependency once we understand its module structure
    // For now, we'll create a placeholder implementation

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
