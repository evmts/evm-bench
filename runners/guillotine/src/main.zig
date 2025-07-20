const std = @import("std");
const guillotine = @import("guillotine");

const Args = struct {
    contract_code_path: []const u8,
    calldata: []const u8,
    num_runs: u32,

    fn parseArgs(allocator: std.mem.Allocator) !Args {
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        var contract_code_path: ?[]const u8 = null;
        var calldata: ?[]const u8 = null;
        var num_runs: u32 = 1;

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--contract-code-path")) {
                if (i + 1 >= args.len) {
                    return error.MissingContractCodePath;
                }
                i += 1;
                contract_code_path = args[i];
            } else if (std.mem.eql(u8, args[i], "--calldata")) {
                if (i + 1 >= args.len) {
                    return error.MissingCalldata;
                }
                i += 1;
                calldata = args[i];
            } else if (std.mem.eql(u8, args[i], "--num-runs")) {
                if (i + 1 >= args.len) {
                    return error.MissingNumRuns;
                }
                i += 1;
                num_runs = try std.fmt.parseInt(u32, args[i], 10);
            }
        }

        if (contract_code_path == null) {
            return error.MissingContractCodePath;
        }
        if (calldata == null) {
            return error.MissingCalldata;
        }

        return Args{
            .contract_code_path = try allocator.dupe(u8, contract_code_path.?),
            .calldata = try allocator.dupe(u8, calldata.?),
            .num_runs = num_runs,
        };
    }
};

fn hexDecode(allocator: std.mem.Allocator, hex_str: []const u8) ![]u8 {
    var actual_hex = hex_str;
    if (hex_str.len >= 2 and hex_str[0] == '0' and hex_str[1] == 'x') {
        actual_hex = hex_str[2..];
    }
    
    if (actual_hex.len == 0) {
        return try allocator.alloc(u8, 0);
    }
    
    if (actual_hex.len % 2 != 0) {
        return error.InvalidHexLength;
    }
    
    const result = try allocator.alloc(u8, actual_hex.len / 2);
    
    for (0..result.len) |i| {
        const hex_byte = actual_hex[i * 2..i * 2 + 2];
        result[i] = try std.fmt.parseInt(u8, hex_byte, 16);
    }
    
    return result;
}

fn readContractCode(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(contents);
    
    const trimmed = std.mem.trim(u8, contents, " \t\n\r");
    return hexDecode(allocator, trimmed);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try Args.parseArgs(allocator);
    defer allocator.free(args.contract_code_path);
    defer allocator.free(args.calldata);

    // Read and decode contract bytecode
    const contract_code = try readContractCode(allocator, args.contract_code_path);
    defer allocator.free(contract_code);

    // Decode calldata
    const calldata = try hexDecode(allocator, args.calldata);
    defer allocator.free(calldata);

    // For now, just print a placeholder message
    std.debug.print("Guillotine runner not fully implemented yet\n", .{});
    std.debug.print("Would run contract with {} bytes of code and {} bytes of calldata\n", .{ contract_code.len, calldata.len });
    
    // Output fake timings for now
    for (0..args.num_runs) |_| {
        std.debug.print("100.0\n", .{});
    }
}