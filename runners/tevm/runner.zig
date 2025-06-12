const std = @import("std");
const evm = @import("evm");
const Address = @import("Address");
const Compiler = @import("Compiler");

/// Tevm EVM benchmark runner
///
/// This runner implements the evm-bench interface for the Tevm EVM implementation.
/// It deploys and executes smart contracts while measuring execution time.

const Args = struct {
    contract_code_path: []const u8,
    calldata: []const u8,
    num_runs: u32,
};

const CREATOR_ADDRESS: [20]u8 = [_]u8{0x10} ++ [_]u8{0x00} ** 19;
const CONTRACT_ADDRESS: [20]u8 = [_]u8{0x20} ++ [_]u8{0x00} ** 19;
const CALLER_ADDRESS: [20]u8 = [_]u8{0x30} ++ [_]u8{0x00} ** 19;
const GAS_LIMIT: u64 = std.math.maxInt(u64);

/// Parse command line arguments
fn parseArgs(allocator: std.mem.Allocator) !Args {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 7) {
        std.log.err("Usage: {s} --contract-code-path <path> --calldata <hex> --num-runs <n>", .{args[0]});
        return error.InvalidArgs;
    }

    var contract_code_path: ?[]const u8 = null;
    var calldata: ?[]const u8 = null;
    var num_runs: ?u32 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 2) {
        if (std.mem.eql(u8, args[i], "--contract-code-path")) {
            if (i + 1 >= args.len) return error.InvalidArgs;
            contract_code_path = try allocator.dupe(u8, args[i + 1]);
        } else if (std.mem.eql(u8, args[i], "--calldata")) {
            if (i + 1 >= args.len) return error.InvalidArgs;
            calldata = try allocator.dupe(u8, args[i + 1]);
        } else if (std.mem.eql(u8, args[i], "--num-runs")) {
            if (i + 1 >= args.len) return error.InvalidArgs;
            num_runs = try std.fmt.parseInt(u32, args[i + 1], 10);
        } else {
            std.log.err("Unknown argument: {s}", .{args[i]});
            return error.InvalidArgs;
        }
    }

    return Args{
        .contract_code_path = contract_code_path orelse return error.InvalidArgs,
        .calldata = calldata orelse return error.InvalidArgs,
        .num_runs = num_runs orelse return error.InvalidArgs,
    };
}

/// Compile Solidity contract and return deployment bytecode
fn compileContract(allocator: std.mem.Allocator, sol_path: []const u8) ![]u8 {
    // For now, just use pre-compiled bytecode approach 
    // TODO: Add Solidity compilation once we confirm basic functionality
    return readHexBytecode(allocator, sol_path);
}

/// Read and decode hex contract code from file (for .bin files)
fn readHexBytecode(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.log.err("Failed to open contract code file '{s}': {}", .{ path, err });
        return err;
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB limit
    defer allocator.free(contents);

    // Remove any whitespace/newlines
    const trimmed = std.mem.trim(u8, contents, " \t\n\r");

    // Decode hex
    const bytecode = try allocator.alloc(u8, trimmed.len / 2);
    _ = std.fmt.hexToBytes(bytecode, trimmed) catch |err| {
        std.log.err("Failed to decode hex contract code: {}", .{err});
        return err;
    };

    return bytecode;
}

/// Decode hex calldata
fn decodeCalldata(allocator: std.mem.Allocator, hex_calldata: []const u8) ![]u8 {
    if (hex_calldata.len == 0) {
        return try allocator.alloc(u8, 0);
    }

    const calldata = try allocator.alloc(u8, hex_calldata.len / 2);
    _ = std.fmt.hexToBytes(calldata, hex_calldata) catch |err| {
        std.log.err("Failed to decode hex calldata: {}", .{err});
        return err;
    };

    return calldata;
}

/// Deploy contract and return the deployed contract address
fn deployContract(vm: *evm.Vm, bytecode: []const u8) !Address.Address {
    // Set up creator account with sufficient balance
    try vm.state.set_balance(CREATOR_ADDRESS, std.math.maxInt(u256));

    std.log.info("Deploying contract with bytecode length: {}", .{bytecode.len});

    // Deploy the contract
    const create_result = vm.create_contract(
        CREATOR_ADDRESS, // creator
        0, // value
        bytecode, // init code
        GAS_LIMIT, // gas
    ) catch |err| {
        std.log.err("Failed to deploy contract: {}", .{err});
        return err;
    };

    std.log.info("Create result: success={}", .{create_result.success});

    if (!create_result.success) {
        std.log.err("Contract deployment failed", .{});
        return error.DeploymentFailed;
    }

    return create_result.address;
}

/// Execute contract call and measure timing
fn executeCall(vm: *evm.Vm, contract_addr: Address.Address, calldata: []const u8) !u64 {
    // Set up caller account
    try vm.state.set_balance(CALLER_ADDRESS, std.math.maxInt(u256));

    // Get the deployed contract code
    const code = vm.state.get_code(contract_addr);
    if (code.len == 0) {
        std.log.err("No code found at contract address", .{});
        return error.NoCodeAtAddress;
    }

    // Create a contract instance for execution
    var contract = evm.Contract.init(
        CALLER_ADDRESS, // caller
        contract_addr, // address
        0, // value
        GAS_LIMIT, // gas
        code, // code
        [_]u8{0} ** 32, // code_hash (not used for execution)
        calldata, // input
        false, // is_static
    );
    defer contract.deinit(vm.allocator, null);

    const start_time = std.time.nanoTimestamp();

    const run_result = vm.interpret(&contract, calldata) catch |err| {
        std.log.err("Contract interpretation failed: {}", .{err});
        return err;
    };

    const end_time = std.time.nanoTimestamp();

    // Check if execution was successful (returned normally)
    switch (run_result.status) {
        .Success => {}, // Good, continue
        .Revert => {
            std.log.err("Contract execution reverted", .{});
            return error.ExecutionReverted;
        },
        else => {
            std.log.err("Contract execution failed with status: {}", .{run_result.status});
            return error.ExecutionFailed;
        },
    }

    return @intCast(end_time - start_time);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse arguments
    const args = parseArgs(allocator) catch {
        std.process.exit(1);
    };
    defer {
        allocator.free(args.contract_code_path);
        allocator.free(args.calldata);
    }

    // Compile contract and get bytecode
    const bytecode = compileContract(allocator, args.contract_code_path) catch {
        std.process.exit(1);
    };
    defer allocator.free(bytecode);

    // Decode calldata
    const calldata = decodeCalldata(allocator, args.calldata) catch {
        std.process.exit(1);
    };
    defer allocator.free(calldata);

    // Initialize memory database
    var memory_db = evm.MemoryDatabase.init(allocator);
    defer memory_db.deinit();

    const db_interface = memory_db.to_database_interface();

    // Initialize VM
    var vm = evm.Vm.init(allocator, db_interface, null, null) catch |err| {
        std.log.err("Failed to initialize VM: {}", .{err});
        std.process.exit(1);
    };
    defer vm.deinit();

    // Deploy contract
    const contract_addr = deployContract(&vm, bytecode) catch {
        std.process.exit(1);
    };

    std.log.info("Deployed contract to address: {any}", .{contract_addr});
    
    // Debug: Check if code was actually deployed
    const deployed_code = vm.state.get_code(contract_addr);
    std.log.info("Deployed code length: {}", .{deployed_code.len});

    // Execute benchmark runs
    var total_time: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    var max_time: u64 = 0;

    std.log.info("Running {} benchmark iterations...", .{args.num_runs});

    for (0..args.num_runs) |run| {
        const execution_time = executeCall(&vm, contract_addr, calldata) catch |err| {
            std.log.err("Failed to execute call {}: {}", .{ run, err });
            std.process.exit(1);
        };

        total_time += execution_time;
        min_time = @min(min_time, execution_time);
        max_time = @max(max_time, execution_time);

        // Log progress for long-running benchmarks
        if (args.num_runs >= 10 and (run + 1) % (args.num_runs / 10) == 0) {
            std.log.info("Completed {}/{} runs", .{ run + 1, args.num_runs });
        }
    }

    // Calculate statistics
    const avg_time_ns = total_time / args.num_runs;
    const avg_time_ms = @as(f64, @floatFromInt(avg_time_ns)) / 1_000_000.0;
    const min_time_ms = @as(f64, @floatFromInt(min_time)) / 1_000_000.0;
    const max_time_ms = @as(f64, @floatFromInt(max_time)) / 1_000_000.0;

    // Output results in the format expected by evm-bench
    std.log.info("Benchmark completed:", .{});
    std.log.info("  Runs: {}", .{args.num_runs});
    std.log.info("  Average: {d:.2} ms", .{avg_time_ms});
    std.log.info("  Min: {d:.2} ms", .{min_time_ms});
    std.log.info("  Max: {d:.2} ms", .{max_time_ms});

    // For compatibility with evm-bench tooling, output the main result
    const stdout = std.io.getStdOut().writer();
    try stdout.print("{d:.2}\n", .{avg_time_ms});
}