const std = @import("std");
const zbench = @import("zbench");
const Memory = @import("evm").Memory;

// Benchmark Memory initialization
fn benchmarkMemoryInit(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();
    std.mem.doNotOptimizeAway(&mem);
}

// Benchmark Memory initialization with custom capacity
fn benchmarkMemoryInitLarge(allocator: std.mem.Allocator) void {
    var mem = Memory.init(allocator, 1024 * 1024, Memory.DefaultMemoryLimit) catch return; // 1MB
    defer mem.deinit();
    mem.finalize_root();
    std.mem.doNotOptimizeAway(&mem);
}

// Benchmark Memory initialization with limit
fn benchmarkMemoryInitWithLimit(allocator: std.mem.Allocator) void {
    var mem = Memory.init(allocator, 4 * 1024, 1024 * 1024 * 10) catch return; // 10MB limit
    defer mem.deinit();
    mem.finalize_root();
    std.mem.doNotOptimizeAway(&mem);
}

// Benchmark memory capacity expansion
fn benchmarkMemoryExpansion(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();

    // Expand memory in 10 steps
    for (0..10) |i| {
        const size = (i + 1) * 1024; // 1KB each step
        _ = mem.ensure_context_capacity(size) catch return;
    }
}

// Benchmark memory slice operations
fn benchmarkMemorySliceOps(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();

    // Create data and read slices
    const data = [_]u8{0xAA} ** 256;
    mem.set_data(0, &data) catch return;
    
    for (0..10) |i| {
        const offset = i * 16;
        const slice = mem.get_slice(offset, 32) catch return;
        std.mem.doNotOptimizeAway(slice);
    }
}

// Benchmark U256 read/write operations
fn benchmarkU256Operations(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();

    // Write and read U256 values
    const value: u256 = 0xDEADBEEF_CAFEBABE_12345678_9ABCDEF0_11111111_22222222_33333333_44444444;
    
    for (0..16) |i| {
        const offset = i * 32;
        mem.set_u256(offset, value) catch return;
        const read_value = mem.get_u256(offset) catch return;
        std.mem.doNotOptimizeAway(read_value);
    }
}

// Benchmark single byte read/write operations
fn benchmarkByteOperations(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();

    // Write and read 100 bytes using set_data and get_byte
    for (0..100) |i| {
        const byte_data = [_]u8{@truncate(i)};
        mem.set_data(i, &byte_data) catch return;
        const byte = mem.get_byte(i) catch return;
        std.mem.doNotOptimizeAway(byte);
    }
}

// Benchmark 32-byte word operations
fn benchmarkWordOperations(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();

    const word: [32]u8 = [_]u8{0xFF} ** 32;

    // Write and read 32 words using set_data and get_slice
    for (0..32) |i| {
        const offset = i * 32;
        mem.set_data(offset, &word) catch return;
        const read_word = mem.get_slice(offset, 32) catch return;
        std.mem.doNotOptimizeAway(read_word);
    }
}

// Benchmark large data operations
fn benchmarkLargeDataOps(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();

    // Create 1KB of data
    var data: [1024]u8 = undefined;
    for (&data, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }

    // Copy to memory 10 times at different offsets
    for (0..10) |i| {
        const offset = i * 1024;
        mem.set_data(offset, &data) catch return;
        const read_data = mem.get_slice(offset, 1024) catch return;
        std.mem.doNotOptimizeAway(read_data);
    }
}

// Benchmark memory expansion tracking
fn benchmarkMemoryExpansionTracking(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();

    // Expand memory in steps and track word additions
    for (0..10) |i| {
        const size = (i + 1) * 1024; // Expand by 1KB each iteration
        const new_words = mem.ensure_context_capacity(size) catch return;
        std.mem.doNotOptimizeAway(new_words);
        std.mem.doNotOptimizeAway(mem.context_size());
    }
}

// Benchmark bounded data operations
fn benchmarkBoundedDataOps(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();

    // Source data
    var data: [512]u8 = undefined;
    for (&data, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }

    // Test various bounded copies
    for (0..20) |i| {
        const memory_offset = i * 64;
        const data_offset = i * 16;
        const len = 128;
        mem.set_data_bounded(memory_offset, &data, data_offset, len) catch return;
    }
}

// Benchmark memory copy operations (simulated MCOPY)
fn benchmarkMemoryCopy(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();

    // Initialize some data
    var data: [256]u8 = undefined;
    for (&data, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }
    mem.set_data(0, &data) catch return;

    // Simulate memory copy by reading and writing slices
    for (0..10) |i| {
        const src = i * 32;
        const dest = i * 48;
        const copy_data = mem.get_slice(src, 128) catch return;
        mem.set_data(dest, copy_data) catch return;
    }
}

// Benchmark slice reading operations
fn benchmarkSliceReading(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();

    // Initialize 4KB of data
    _ = mem.ensure_context_capacity(4096) catch return;

    // Read various slices
    for (0..100) |i| {
        const offset = i * 32;
        const len = 64;
        const slice = mem.get_slice(offset, len) catch return;
        std.mem.doNotOptimizeAway(slice);
    }
}

// Benchmark memory stress test with various patterns
fn benchmarkMemoryStressTest(allocator: std.mem.Allocator) void {
    var mem = Memory.init_default(allocator) catch return;
    defer mem.deinit();
    mem.finalize_root();

    // Mixed operations: U256, bytes, slices
    for (0..50) |i| {
        // Write U256 value
        const u256_offset = i * 64;
        const value = @as(u256, i) * 0x123456789ABCDEF;
        mem.set_u256(u256_offset, value) catch return;
        
        // Write byte data
        const byte_offset = i * 64 + 32;
        const byte_data = [_]u8{@truncate(i)};
        mem.set_data(byte_offset, &byte_data) catch return;
        
        // Read back
        const read_value = mem.get_u256(u256_offset) catch return;
        const read_byte = mem.get_byte(byte_offset) catch return;
        
        std.mem.doNotOptimizeAway(read_value);
        std.mem.doNotOptimizeAway(read_byte);
    }
}

// Benchmark memory limit enforcement
fn benchmarkMemoryLimitEnforcement(allocator: std.mem.Allocator) void {
    var mem = Memory.init(allocator, 4 * 1024, 1024 * 64) catch return; // 64KB limit
    defer mem.deinit();
    mem.finalize_root();

    // Try to expand within limit
    for (0..10) |i| {
        const size = (i + 1) * 1024; // 1KB increments
        _ = mem.ensure_context_capacity(size) catch {
            // Expected to fail after 64KB
            break;
        };
    }
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Memory Benchmarks\n", .{});
    try stdout.print("=======================\n\n", .{});

    var bench = zbench.Benchmark.init(std.heap.page_allocator, .{});
    defer bench.deinit();

    // Register benchmarks
    try bench.add("Memory Init (4KB)", benchmarkMemoryInit, .{});
    try bench.add("Memory Init (1MB)", benchmarkMemoryInitLarge, .{});
    try bench.add("Memory Init With Limit", benchmarkMemoryInitWithLimit, .{});
    try bench.add("Memory Expansion", benchmarkMemoryExpansion, .{});
    try bench.add("Memory Slice Operations", benchmarkMemorySliceOps, .{});
    try bench.add("U256 Operations", benchmarkU256Operations, .{});
    try bench.add("Byte Operations", benchmarkByteOperations, .{});
    try bench.add("Word Operations", benchmarkWordOperations, .{});
    try bench.add("Large Data Operations", benchmarkLargeDataOps, .{});
    try bench.add("Memory Expansion Tracking", benchmarkMemoryExpansionTracking, .{});
    try bench.add("Bounded Data Operations", benchmarkBoundedDataOps, .{});
    try bench.add("Memory Copy Operations", benchmarkMemoryCopy, .{});
    try bench.add("Slice Reading", benchmarkSliceReading, .{});
    try bench.add("Memory Stress Test", benchmarkMemoryStressTest, .{});
    try bench.add("Memory Limit Enforcement", benchmarkMemoryLimitEnforcement, .{});

    // Run benchmarks
    try stdout.print("Running benchmarks...\n\n", .{});
    try bench.run(stdout);
}
