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

    // Import Guillotine module - create directly from source
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("guillotine-source/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add required dependencies for Guillotine
    const primitives_mod = b.createModule(.{
        .root_source_file = b.path("guillotine-source/src/primitives/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const crypto_mod = b.createModule(.{
        .root_source_file = b.path("guillotine-source/src/crypto/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    const evm_mod = b.createModule(.{
        .root_source_file = b.path("guillotine-source/src/evm/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Create build options
    const build_options = b.addOptions();
    build_options.addOption(bool, "no_precompiles", false);
    
    // Wire up dependencies
    evm_mod.addImport("primitives", primitives_mod);
    evm_mod.addImport("crypto", crypto_mod);
    evm_mod.addImport("build_options", build_options.createModule());
    lib_mod.addImport("evm", evm_mod);
    lib_mod.addImport("primitives", primitives_mod);
    lib_mod.addImport("crypto", crypto_mod);
    
    // Add guillotine dependencies to the executable too
    exe.root_module.addImport("guillotine", lib_mod);
    exe.root_module.addImport("evm", evm_mod);
    exe.root_module.addImport("primitives", primitives_mod);

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