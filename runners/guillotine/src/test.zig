const std = @import("std");
const primitives = @import("primitives");

pub fn main() !void {
    std.debug.print("Hello from test program\n", .{});
    const addr = primitives.Address.from_u256(0x1234);
    std.debug.print("Created address: {}\n", .{addr});
}