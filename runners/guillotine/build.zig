const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build the BN254 Rust library first
    const rust_profile = if (optimize == .Debug) "dev" else "release";
    const rust_target_dir = if (optimize == .Debug) "debug" else "release";
    
    // Build the Rust library
    const rust_build = b.addSystemCommand(&[_][]const u8{
        "cargo", "build", 
        "--manifest-path", "guillotine-source/src/bn254_wrapper/Cargo.toml",
        "--profile", rust_profile,
    });
    
    // Create static library artifact for the Rust BN254 wrapper
    const bn254_lib = b.addStaticLibrary(.{
        .name = "bn254_wrapper",
        .target = target,
        .optimize = optimize,
    });
    
    // Link the compiled Rust library
    const rust_lib_path = b.fmt("guillotine-source/target/{s}/libbn254_wrapper.a", .{rust_target_dir});
    bn254_lib.addObjectFile(.{ .cwd_relative = rust_lib_path });
    bn254_lib.linkLibC();
    
    // Link system libraries needed by Rust
    if (target.result.os.tag == .macos) {
        bn254_lib.linkFramework("Security");
        bn254_lib.linkFramework("CoreFoundation");
    }
    
    // Add include path for C header
    bn254_lib.addIncludePath(b.path("guillotine-source/src/bn254_wrapper"));
    
    // Make the rust build a dependency
    bn254_lib.step.dependOn(&rust_build.step);

    // Create the runner executable
    const exe = b.addExecutable(.{
        .name = "guillotine-runner",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create build options
    const build_options = b.addOptions();
    build_options.addOption(bool, "no_precompiles", false); // Enable precompiles
    
    // Get c-kzg dependency
    const c_kzg_dep = b.dependency("c_kzg_4844", .{
        .target = target,
        .optimize = optimize,
    });
    const c_kzg_lib = c_kzg_dep.artifact("c_kzg_4844");
    
    // Create modules with proper native build setup
    const primitives_mod = b.createModule(.{
        .root_source_file = b.path("guillotine-source/src/primitives/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    primitives_mod.linkLibrary(c_kzg_lib);
    
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
    
    // Wire up dependencies
    crypto_mod.addImport("primitives", primitives_mod);
    evm_mod.addImport("primitives", primitives_mod);
    evm_mod.addImport("crypto", crypto_mod);
    evm_mod.addImport("build_options", build_options.createModule());
    
    // Link BN254 to EVM module
    evm_mod.linkLibrary(bn254_lib);
    evm_mod.addIncludePath(b.path("guillotine-source/src/bn254_wrapper"));
    
    // Link c-kzg to EVM module
    evm_mod.linkLibrary(c_kzg_lib);
    
    // Add imports to the executable
    exe.root_module.addImport("evm", evm_mod);
    exe.root_module.addImport("primitives", primitives_mod);
    
    // Link the BN254 library to the executable as well
    exe.linkLibrary(bn254_lib);
    exe.addIncludePath(b.path("guillotine-source/src/bn254_wrapper"));

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
    
    // Add test imports executable
    const test_exe = b.addExecutable(.{
        .name = "test-imports",
        .root_source_file = b.path("test_imports.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_exe.root_module.addImport("primitives", primitives_mod);
    test_exe.root_module.addImport("evm", evm_mod);
    b.installArtifact(test_exe);
    
    // Add minimal test
    const minimal_exe = b.addExecutable(.{
        .name = "minimal",
        .root_source_file = b.path("src/minimal.zig"),
        .target = target,
        .optimize = optimize,
    });
    minimal_exe.root_module.addImport("primitives", primitives_mod);
    minimal_exe.root_module.addImport("evm", evm_mod);
    b.installArtifact(minimal_exe);
}