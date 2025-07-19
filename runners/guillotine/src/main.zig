const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

// TODO: Guillotine EVM import will be added once we resolve module structure
// const guillotine = @import("guillotine");

const Args = struct {
    contract_code_path: []const u8,
    calldata: []const u8,
    num_runs: u32,

    fn parseArgs(allocator: Allocator) !Args {
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
            .contract_code_path = contract_code_path.?,
            .calldata = calldata.?,
            .num_runs = num_runs,
        };
    }
};

fn hexDecode(allocator: Allocator, hex_str: []const u8) ![]u8 {
    if (hex_str.len % 2 != 0) {
        return error.InvalidHexLength;
    }
    
    const result = try allocator.alloc(u8, hex_str.len / 2);
    
    for (0..result.len) |i| {
        const hex_byte = hex_str[i * 2..i * 2 + 2];
        result[i] = try std.fmt.parseInt(u8, hex_byte, 16);
    }
    
    return result;
}

fn readContractCode(allocator: Allocator, path: []const u8) ![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        print("Error opening contract code file: {}\n", .{err});
        return err;
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(contents);
    
    // Remove any whitespace/newlines
    const trimmed = std.mem.trim(u8, contents, " \t\n\r");
    
    // Decode hex string to bytes
    return hexDecode(allocator, trimmed);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = Args.parseArgs(allocator) catch |err| {
        switch (err) {
            error.MissingContractCodePath => print("Error: --contract-code-path is required\n", .{}),
            error.MissingCalldata => print("Error: --calldata is required\n", .{}), 
            error.MissingNumRuns => print("Error: --num-runs is required\n", .{}),
            else => print("Error parsing arguments: {}\n", .{err}),
        }
        return;
    };

    // Read and decode contract bytecode
    const contract_code = readContractCode(allocator, args.contract_code_path) catch |err| {
        print("Error reading contract code: {}\n", .{err});
        return;
    };
    defer allocator.free(contract_code);

    // Decode calldata
    const calldata = hexDecode(allocator, args.calldata) catch |err| {
        print("Error decoding calldata: {}\n", .{err});
        return;
    };
    defer allocator.free(calldata);

    // TODO: This is a placeholder implementation
    // We need to integrate with the actual Guillotine EVM API
    // For now, we'll output dummy timing data
    print("// Guillotine EVM Runner - WARNING: This is a placeholder implementation\n", .{});
    print("// Contract code length: {} bytes\n", .{contract_code.len});
    print("// Calldata length: {} bytes\n", .{calldata.len});
    print("// Number of runs: {}\n", .{args.num_runs});
    
    // Output timing results (placeholder - should be actual EVM execution timing)
    for (0..args.num_runs) |_| {
        // Simulate execution timing - replace with actual Guillotine EVM calls
        const execution_time_ms: f64 = 1.0 + @as(f64, @floatFromInt(std.crypto.random.int(u32) % 100)) / 100.0;
        print("{d:.3}\n", .{execution_time_ms});
    }
}