const std = @import("std");
const primitives = @import("primitives");
const Evm = @import("evm");

pub fn main() !void {
    std.debug.print("Testing imports...\n", .{});
    std.debug.print("ZERO_ADDRESS: {any}\n", .{primitives.Address.ZERO_ADDRESS});
    std.debug.print("Evm module loaded\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Creating MemoryDatabase...\n", .{});
    var memory_db = Evm.MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    std.debug.print("MemoryDatabase created successfully\n", .{});
}