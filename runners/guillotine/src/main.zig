const std = @import("std");

// Disable debug logging for performance
pub const std_options = std.Options{
    .log_level = .err,
};

pub fn main() void {
    mainImpl() catch {
        std.process.exit(1);
    };
}

const Args = struct {
    contract_code_path: []const u8,
    calldata: []const u8,
    num_runs: u32,

    fn parseArgs(allocator: std.mem.Allocator) !Args {
        const argv = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, argv);

        var result = Args{
            .contract_code_path = undefined,
            .calldata = undefined,
            .num_runs = 1,
        };

        var i: usize = 1;
        while (i < argv.len) : (i += 1) {
            if (std.mem.eql(u8, argv[i], "--contract-code-path")) {
                if (i + 1 >= argv.len) {
                    return error.MissingArgument;
                }
                result.contract_code_path = try allocator.dupe(u8, argv[i + 1]);
                i += 1;
            } else if (std.mem.eql(u8, argv[i], "--calldata")) {
                if (i + 1 >= argv.len) {
                    return error.MissingArgument;
                }
                result.calldata = try allocator.dupe(u8, argv[i + 1]);
                i += 1;
            } else if (std.mem.eql(u8, argv[i], "--num-runs")) {
                if (i + 1 >= argv.len) {
                    return error.MissingArgument;
                }
                result.num_runs = try std.fmt.parseInt(u32, argv[i + 1], 10);
                i += 1;
            }
        }

        if (!@hasField(@TypeOf(result), "contract_code_path") or result.contract_code_path.len == 0) {
            return error.MissingContractCodePath;
        }
        if (!@hasField(@TypeOf(result), "calldata") or result.calldata.len == 0) {
            return error.MissingCalldata;
        }

        return result;
    }
};

fn decodeHex(allocator: std.mem.Allocator, hex: []const u8) ![]u8 {
    const cleaned_hex = if (std.mem.startsWith(u8, hex, "0x")) hex[2..] else hex;
    
    if (cleaned_hex.len == 0) {
        return allocator.alloc(u8, 0);
    }
    
    const result = try allocator.alloc(u8, cleaned_hex.len / 2);
    _ = try std.fmt.hexToBytes(result, cleaned_hex);
    
    return result;
}

fn mainImpl() !void {
    const Evm = @import("evm");
    const primitives = @import("primitives");
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            // Memory leak detected
        }
    }
    
    const allocator = gpa.allocator();
    
    // Test memory database creation
    var test_memory_db = Evm.MemoryDatabase.init(allocator);
    defer test_memory_db.deinit();

    const args = try Args.parseArgs(allocator);
    defer allocator.free(args.contract_code_path);
    defer allocator.free(args.calldata);

    // Read contract bytecode from file
    var contract_code_file = std.fs.cwd().openFile(args.contract_code_path, .{}) catch |err| blk: {
        if (err == error.FileNotFound) {
            // Try from parent directories if relative path fails
            const alt_path = try std.fmt.allocPrint(allocator, "../../{s}", .{args.contract_code_path});
            defer allocator.free(alt_path);
            break :blk try std.fs.cwd().openFile(alt_path, .{});
        }
        return err;
    };
    defer contract_code_file.close();
    
    const contract_code_hex = try contract_code_file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(contract_code_hex);
    
    // Decode hex
    const contract_code = try decodeHex(allocator, std.mem.trim(u8, contract_code_hex, " \n\r\t"));
    defer allocator.free(contract_code);
    
    const calldata = try decodeHex(allocator, args.calldata);
    defer allocator.free(calldata);

    // Create memory database (using same pattern as benchmark)
    var memory_db = try allocator.create(Evm.MemoryDatabase);
    defer allocator.destroy(memory_db);
    
    memory_db.* = Evm.MemoryDatabase.init(allocator);
    defer memory_db.deinit();

    const db_interface = memory_db.to_database_interface();
    
    // Create EVM instance (using same pattern as benchmark)
    var evm_instance = try allocator.create(Evm.Evm);
    defer allocator.destroy(evm_instance);
    
    evm_instance.* = try Evm.Evm.init(allocator, db_interface);
    defer evm_instance.deinit();

    // Context is managed internally by the VM

    // Set code on the contract address (1000)
    const contract_address = primitives.Address.from_u256(0x1000);
    try evm_instance.state.set_code(contract_address, contract_code);
    
    // Give the caller some balance
    const caller_address = primitives.Address.from_u256(0x1001);
    try evm_instance.state.set_balance(caller_address, 1000000 * 1e18); // 1M ETH
    
    // Run the benchmark multiple times
    var i: u32 = 0;
    var total_time: u64 = 0;
    while (i < args.num_runs) : (i += 1) {
        // Create contract for each run (like test)
        var contract = Evm.Contract.init_at_address(
            contract_address,
            caller_address,
            0, // value
            1_000_000_000, // gas (1B like others)
            contract_code,
            calldata,
            false, // not static
        );
        defer contract.deinit(allocator, null);

        const start = std.time.nanoTimestamp();
        const result = try evm_instance.*.interpret(&contract, calldata);
        const end = std.time.nanoTimestamp();
        
        defer if (result.output) |output| allocator.free(output);
        
        if (result.status != .Success) {
            return error.ExecutionFailed;
        }
        
        total_time += @intCast(end - start);
    }
    
    const avg_time_ns = total_time / args.num_runs;
    const avg_time_ms = @as(f64, @floatFromInt(avg_time_ns)) / 1_000_000.0;
    
    // Output to stdout
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{d:.6}\n", .{avg_time_ms});
}