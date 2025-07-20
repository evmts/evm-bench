const std = @import("std");

// Enable debug logging
pub const std_options = std.Options{
    .log_level = .debug,
};

pub fn main() void {
    std.log.debug("Entering main function", .{});
    const stderr = std.io.getStdErr().writer();
    stderr.print("In main()...\n", .{}) catch {};
    
    std.log.debug("About to call mainImpl", .{});
    mainImpl() catch |err| {
        std.log.err("mainImpl failed with error: {any}", .{err});
        stderr.print("Error: {any}\n", .{err}) catch {};
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        std.process.exit(1);
    };
    std.log.debug("mainImpl completed successfully", .{});
}

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
            std.debug.print("Error: --contract-code-path is required\n", .{});
            return error.MissingContractCodePath;
        }
        if (calldata == null) {
            std.debug.print("Error: --calldata is required\n", .{});
            return error.MissingCalldata;
        }

        return Args{
            .contract_code_path = try allocator.dupe(u8, contract_code_path.?),
            .calldata = try allocator.dupe(u8, calldata.?),
            .num_runs = num_runs,
        };
    }
};

fn decodeHex(allocator: std.mem.Allocator, hex: []const u8) ![]u8 {
    // Skip 0x prefix if present
    const start: usize = if (std.mem.startsWith(u8, hex, "0x")) 2 else 0;
    const clean_hex = hex[start..];
    
    // Handle odd-length hex strings
    if (clean_hex.len % 2 != 0) {
        return error.InvalidHexLength;
    }
    
    const result = try allocator.alloc(u8, clean_hex.len / 2);
    errdefer allocator.free(result);
    
    _ = try std.fmt.hexToBytes(result, clean_hex);
    
    return result;
}

fn mainImpl() !void {
    std.log.debug("Starting mainImpl", .{});
    std.debug.print("Starting mainImpl...\n", .{});
    
    std.log.debug("Importing evm module", .{});
    std.debug.print("About to import evm module...\n", .{});
    const Evm = @import("evm");
    std.debug.print("Imported evm module...\n", .{});
    
    std.log.debug("Importing primitives module", .{});
    std.debug.print("About to import primitives module...\n", .{});
    const primitives = @import("primitives");
    std.debug.print("Imported primitives module...\n", .{});
    
    std.debug.print("Creating GPA struct...\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    std.debug.print("GPA struct created...\n", .{});
    
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected", .{});
        }
    }
    
    std.debug.print("Getting allocator...\n", .{});
    const allocator = gpa.allocator();
    
    std.debug.print("Allocator created...\n", .{});
    
    // First test if we can create a MemoryDatabase at all
    std.debug.print("Creating MemoryDatabase as a test...\n", .{});
    var test_memory_db = Evm.MemoryDatabase.init(allocator);
    defer test_memory_db.deinit();
    std.debug.print("Test MemoryDatabase created successfully\n", .{});

    std.debug.print("Parsing args...\n", .{});
    const args = try Args.parseArgs(allocator);
    std.debug.print("Args parsed...\n", .{});
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

    // Set up basic context (similar to test setup)
    const tx_origin = primitives.Address.ZERO_ADDRESS;
    const context = Evm.Context.init_with_values(
        tx_origin,
        1000000000, // gas_price: 1 gwei
        10000, // block_number
        1234567890, // block_timestamp
        primitives.Address.ZERO_ADDRESS, // block_coinbase
        1000000, // block_difficulty
        30000000, // block_gas_limit
        1, // chain_id
        100000000, // block_base_fee: 0.1 gwei
        &[_]u256{}, // blob_hashes
        0, // blob_base_fee
    );
    evm_instance.set_context(context);

    // Use a simple contract address
    const CONTRACT_ADDRESS = primitives.Address.from_u256(0x1000);
    
    // Set the contract code in state
    try evm_instance.state.set_code(CONTRACT_ADDRESS, contract_code);

    // Execute the contract multiple times and measure
    var total_time: u64 = 0;
    var i: u32 = 0;
    while (i < args.num_runs) : (i += 1) {
        // Create contract for execution
        var contract = Evm.Contract.init_at_address(
            CONTRACT_ADDRESS, // caller
            CONTRACT_ADDRESS, // address where code executes
            0, // value
            1_000_000_000, // 1 billion gas
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
            std.debug.print("ERROR: Contract execution failed with status: {}\n", .{result.status});
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