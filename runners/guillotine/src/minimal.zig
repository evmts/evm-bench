const std = @import("std");
const Evm = @import("evm");
const primitives = @import("primitives");

pub fn main() void {
    mainImpl() catch |err| {
        std.debug.print("Error: {any}\n", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    };
}

fn mainImpl() !void {
    std.debug.print("Starting minimal test...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create memory database
    var memory_db = Evm.MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    
    const db_interface = memory_db.to_database_interface();
    
    // Create EVM instance
    var evm_instance = try Evm.Evm.init(allocator, db_interface);
    defer evm_instance.deinit();
    
    std.debug.print("EVM created successfully\n", .{});
    
    // Simple contract code
    const code = &[_]u8{0x60, 0x80, 0x60, 0x40};
    
    // Set up context
    const context = Evm.Context.init_with_values(
        primitives.Address.ZERO_ADDRESS,
        1000000000,
        10000,
        1234567890,
        primitives.Address.ZERO_ADDRESS,
        1000000,
        30000000,
        1,
        100000000,
        &[_]u256{},
        0,
    );
    evm_instance.set_context(context);
    
    // Create and execute contract
    const CONTRACT_ADDRESS = primitives.Address.from_u256(0x1000);
    try evm_instance.state.set_code(CONTRACT_ADDRESS, code);
    
    var contract = Evm.Contract.init_at_address(
        CONTRACT_ADDRESS,
        CONTRACT_ADDRESS,
        0,
        1_000_000,
        code,
        &[_]u8{},
        false,
    );
    defer contract.deinit(allocator, null);
    
    const result = try evm_instance.interpret(&contract, &[_]u8{});
    defer if (result.output) |output| allocator.free(output);
    
    std.debug.print("Result status: {}\n", .{result.status});
    std.debug.print("Gas used: {}\n", .{result.gas_used});
}