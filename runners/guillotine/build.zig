const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the Guillotine dependency
    const guillotine_dep = b.dependency("Guillotine", .{
        .target = target,
        .optimize = optimize,
    });

    // Create the runner executable
    const exe = b.addExecutable(.{
        .name = "guillotine-runner",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Check what's available
    std.debug.print("Guillotine dependency type: {}\n", .{@TypeOf(guillotine_dep)});
    
    // Try to get the root module of Guillotine
    if (guillotine_dep.module("root")) |mod| {
        exe.root_module.addImport("guillotine", mod);
    } else {
        std.debug.print("Warning: Could not find Guillotine root module\n", .{});
    }

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