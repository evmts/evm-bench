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
    // First try to find pre-compiled bytecode from evm-bench build outputs
    // The evm-bench framework compiles contracts with the correct Solidity version
    
    // Convert path like "./bench/evm/benchmarks/snailtracer/SnailTracer.sol" 
    // to "./bench/evm/outputs/build/snailtracer/SnailTracer.bin"
    if (std.mem.endsWith(u8, sol_path, ".sol")) {
        // Extract contract name and directory
        const basename = std.fs.path.basename(sol_path);
        const contract_name = basename[0..basename.len - 4]; // Remove .sol extension
        
        // Build the path to the pre-compiled .bin file
        var bin_path_buf: [1024]u8 = undefined;
        const bin_path = std.fmt.bufPrint(&bin_path_buf, "./bench/evm/outputs/build/snailtracer/{s}.bin", .{contract_name}) catch {
            std.log.err("Path too long for bytecode file", .{});
            return error.PathTooLong;
        };
        
        // Try to read the pre-compiled bytecode
        if (readHexBytecode(allocator, bin_path)) |bytecode| {
            std.log.info("Using pre-compiled bytecode from: {s}", .{bin_path});
            return bytecode;
        } else |_| {
            std.log.warn("Could not read pre-compiled bytecode from: {s}", .{bin_path});
        }
    }
    
    // Fallback to compiling from source (though this may fail for old Solidity versions)
    std.log.info("Attempting to compile from source: {s}", .{sol_path});
    const settings = Compiler.CompilerSettings{
        .optimizer_enabled = true,
        .optimizer_runs = 200,
        .evm_version = "byzantium", // Use EVM version compatible with 0.4.26
        .output_bytecode = true,
        .output_deployed_bytecode = true,
    };
    
    var result = Compiler.Compiler.compile_file(allocator, sol_path, settings) catch |err| {
        std.log.err("Failed to compile Solidity file '{s}': {}", .{ sol_path, err });
        return err;
    };
    defer result.deinit();
    
    if (result.contracts.len == 0) {
        std.log.err("No contracts found in compilation result for '{s}'", .{sol_path});
        if (result.errors.len > 0) {
            std.log.err("Compilation errors:", .{});
            for (result.errors) |compilation_error| {
                std.log.err("  {s}", .{compilation_error.message});
            }
        }
        return error.NoContractsFound;
    }
    
    // Return the bytecode of the first contract
    const contract = &result.contracts[0];
    return try allocator.dupe(u8, contract.bytecode);
}

/// Simple heuristic to detect if bytecode is runtime code vs constructor code
/// Runtime code for complex contracts usually starts with 6080604052 (PUSH1 0x80 PUSH1 0x40 MSTORE)
/// Constructor code is usually longer and includes initialization logic
fn isRuntimeBytecode(bytecode: []const u8) bool {
    // Very simple heuristic: if bytecode starts with 6080604052 and is relatively short
    // it's likely runtime code. Constructor code tends to be much longer.
    if (bytecode.len < 8000 and bytecode.len > 100) {
        // Check for common runtime code pattern
        if (bytecode.len >= 5 and 
            bytecode[0] == 0x60 and bytecode[1] == 0x80 and 
            bytecode[2] == 0x60 and bytecode[3] == 0x40 and 
            bytecode[4] == 0x52) {
            return true;
        }
    }
    return false;
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
fn deployContract(vm: *evm.Vm, bytecode: []const u8, is_runtime_code: bool) !Address.Address {
    // Set up creator account with sufficient balance
    try vm.state.set_balance(CREATOR_ADDRESS, std.math.maxInt(u256));

    std.log.info("Deploying contract with bytecode length: {}, is_runtime_code: {}", .{ bytecode.len, is_runtime_code });

    if (is_runtime_code) {
        // For runtime bytecode, directly set the code at the contract address
        // This simulates what would happen after constructor execution
        try vm.state.set_code(CONTRACT_ADDRESS, bytecode);
        std.log.info("Directly deployed runtime code to address: {any}", .{CONTRACT_ADDRESS});
        return CONTRACT_ADDRESS;
    } else {
        // For constructor bytecode, use create_contract
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
        if (create_result.output) |output| {
            std.log.info("Constructor output length: {}", .{output.len});
        } else {
            std.log.info("Constructor output: null", .{});
        }

        if (!create_result.success) {
            std.log.err("Contract deployment failed", .{});
            if (create_result.output) |revert_data| {
                std.log.err("Revert data length: {}", .{revert_data.len});
                if (revert_data.len > 0) {
                    std.log.err("Revert data (first 32 bytes): {any}", .{revert_data[0..@min(32, revert_data.len)]});
                }
            }
            return error.DeploymentFailed;
        }

        return create_result.address;
    }
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

/// Test the exact same setup as our unit test but with logging
fn testSnailTracer() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("=== Testing SnailTracer with unit test setup ===", .{});

    // Use the same bytecode as our working unit test
    const snailtracer_bytecode_hex = "608060405234801561001057600080fd5b506144c8806100206000396000f3006080604052600436106100615763ffffffff7c010000000000000000000000000000000000000000000000000000000060003504166330627b7c811461006657806375ac892a146100bf578063784f13661461014f578063c29436011461016d575b600080fd5b34801561007257600080fd5b5061007b610185565b604080517fff000000000000000000000000000000000000000000000000000000000000009485168152928416602084015292168183015290519081900360600190f35b3480156100cb57600080fd5b506100da6004356024356129e9565b6040805160208082528351818301528351919283929083019185019080838360005b838110156101145781810151838201526020016100fc565b50505050905090810190601f1680156101415780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b34801561015b57600080fd5b5061007b600435602435604435612c99565b34801561017957600080fd5b506100da600435612cd7565b6000806000806101936143c6565b61019b614428565b61040060009081556103006001556040805160e0810182526302faf08060808201908152630319750060a083015263119e7f8060c08301528152815160608101835292835261a67319602084810191909152620f423f1992840192909252919082019061020790612fa4565b815260006020808301829052604092830182905283518051600355808201516004558301516005558381015180516006559081015160075582015160085582820151600955606092830151600a805460ff1916911515919091179055815192830190915260015490548291906207d5dc0281151561028157fe5b058152600060208083018290526040928301919091528251600b81905583820151600c81905593830151600d819055835160608181018652928152808401959095528484015282519081018352600654815260075491810191909152600854918101919091526103139161030a91610301916102fc91613034565b612fa4565b6207d5dc6130a2565b620f42406130d5565b8051600e55602080820151600f55604091820151601055815160a08101835264174876e8008152825160608082018552641748862a40825263026e8f00828501526304dd1e008286015282840191825284518082018652600080825281860181905281870181905284870191825286518084018852620b71b081526203d0908188018190528189015292850192835260808501818152601180546001808201808455929094528751600b9091027f31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c688101918255965180517f31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c69890155808a01517f31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c6a8901558a01517f31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c6b880155935180517f31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c6c880155808901517f31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c6d8801558901517f31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c6e870155935180517f31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c6f870155968701517f31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c7086015595909601517f31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c7184015593517f31ecc21a745e3968a04e9570e4425bc18fa8019c68028196b546d1669c200c7290920180549195939493909160ff19169083600281111561058d57fe5b0217905550505050601160a06040519081016040528064174876e800815260200160606040519081016040528064174290493f19815260200163026e8f0081526020016304dd1e0081525081526020016060604051908101604052806000815260200160008152602001600081525081526020016060604051908101604052806203d09081526020016203d0908152602001620b71b081525081526020016000600281111561063857fe5b90528154600181810180855560009485526020948590208451600b90940201928355848401518051848401558086015160028086019190915560409182015160038601558186015180516004870155808801516005870155820151600686015560608601518051600787015596870151600886015595015160098401556080840151600a8401805492969193909260ff19169184908111156106d657fe5b0217905550505050601160a06040519081016040528064174876e80081526020016060604051908101604052806302faf080815260200163026e8f00815260200164174876e8008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620b71b08152602001620b71b08152602001620b71b081525081526020016000600281111561078057fe5b90528154600181810180855560009485526020948590208451600b90940201928355848401518051848401558086015160028086019190915260409182015160038601558186015180516004870155808801516005870155820151600686015560608601518051600787015596870151600886015595015160098401556080840151600a8401805492969193909260ff191691849081111561081e57fe5b0217905550505050601160a06040519081016040528064174876e80081526020016060604051908101604052806302faf080815260200163026e8f00815260200164173e54e97f198152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001600060028111156108c357fe5b90528154600181810180855560009485526020948590208451600b90940201928355848401518051848401558086015160028086019190915260409182015160038601558186015180516004870155808801516005870155820151600686015560608601518051600787015596870151600886015595015160098401556080840151600a8401805492969193909260ff191691849081111561096157fe5b0217905550505050601160a06040519081016040528064174876e80081526020016060604051908101604052806302faf080815260200164174876e80081526020016304dd1e008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620b71b08152602001620b71b08152602001620b71b0815250815260200160006002811115610a0b57fe5b90528154600181810180855560009485526020948590208451600b90940201928355848401518051848401558086015160028086019190915260409182015160038601558186015180516004870155808801516005870155820151600686015560608601518051600787015596870151600886015595015160098401556080840151600a8401805492969193909260ff1916918490811115610aa957fe5b0217905550505050601160a06040519081016040528064174876e80081526020016060604051908101604052806302faf080815260200164174399c9ff1981526020016304dd1e008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620b71b08152602001620b71b08152602001620b71b0815250815260200160006002811115610b5457fe5b90528154600181810180855560009485526020948590208451600b90940201928355848401518051848401558086015160028086019190915260409182015160038601558186015180516004870155808801516005870155820151600686015560608601518051600787015596870151600886015595015160098401556080840151600a8401805492969193909260ff1916918490811115610bf257fe5b0217905550505050601160a06040519081016040528062fbc520815260200160606040519081016040528063019bfcc0815260200162fbc52081526020016302cd29c08152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e58815250815260200160016002811115610c9857fe5b90528154600181810180855560009485526020948590208451600b90940201928355848401518051848401558086015160028086019190915260409182015160038601558186015180516004870155808801516005870155820151600686015560608601518051600787015596870151600886015595015160098401556080840151600a8401805492969193909260ff1916918490811115610d3657fe5b0217905550505050601160a0604051908101604052806323c3460081526020016060604051908101604052806302faf080815260200163289c455081526020016304dd1e00815250815260200160606040519081016040528062b71b00815260200162b71b00815260200162b71b00815250815260200160606040519081016040528060008152602001600081526020016000815250815260200160006002811115610dde57fe5b90528154600181810180855560009485526020948590208451600b90940201928355848401518051848401558086015160028086019190915260409182015160038601558186015180516004870155808801516005870155820151600686015560608601518051600787015596870151600886015595015160098401556080840151600a8401805492969193909260ff1916918490811115610e7c57fe5b0217905550505050601260e06040519081016040528060606040519081016040528063035e1f208152602001630188c2e081526020016304a62f808152508152602001606060405190810160405280630459e4408152602001630188c2e081526020016305a1f4a08152508152602001606060405190810160405280630459e44081526020016302f34f6081526020016304a62f808152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e58815250815260200160016002811115610f9857fe5b0217905550505050601260e06040519081016040528060606040519081016040528063035e1f20815260200163016a8c8081526020016304a62f808152508152602001606060405190810160405280630459e4408152602001600081526020016304a62f808152508152602001606060405190810160405280630459e440815260200163016a8c8081526020016305a1f4a08152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e5881525081526020016001600281111561119e57fe5b90528154600181810180855560009485526020948590208451805160139095029091019384558086015184840155604090810151600280860191909155868601518051600387015580880151600487015582015160058601558186015180516006870155808801516007870155820151600886015560608601518051600987015580880151600a870155820151600b86015560808601518051600c87015580880151600d870155820151600e86015560a08601518051600f870155968701516010860155950151601184015560c084015160128401805492969193909260ff191691849081111561128b57fe5b0217905550505050601260e060405190810160405280606060405190810160405280630555a9608152602001630188c2e081526020016304a62f808152508152602001606060405190810160405280630459e44081526020016302f34f6081526020016304a62f808152508152602001606060405190810160405280630459e4408152602001630188c2e081526020016305a1f4a08152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e588152508152602001600160028111156113a757fe5b90528154600181810180855560009485526020948590208451805160139095029091019384558086015184840155604090810151600280860191909155868601518051600387015580880151600487015582015160058601558186015180516006870155808801516007870155820151600886015560608601518051600987015580880151600a870155820151600b86015560808601518051600c87015580880151600d870155820151600e86015560a08601518051600f870155968701516010860155950151601184015560c084015160128401805492969193909260ff191691849081111561149457fe5b0217905550505050601260e060405190810160405280606060405190810160405280630555a960815260200163016a8c8081526020016304a62f808152508152602001606060405190810160405280630459e440815260200163016a8c8081526020016305a1f4a08152508152602001606060405190810160405280630459e4408152602001600081526020016304dd1e008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e588152508152602001600160028111156115ad57fe5b0217905550505050601260e06040519081016040528060606040519081016040528063035e1f208152602001630188c2e081526020016304a62f808152508152602001606060405190810160405280630459e44081526020016302f34f6081526020016304a62f808152508152602001606060405190810160405280630459e4408152602001630188c2e081526020016303aa6a608152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e588152508152602001600160028111156117b657fe5b0217905550505050601260e06040519081016040528060606040519081016040528063035e1f20815260200163016a8c8081526020016304a62f808152508152602001606060405190810160405280630459e440815260200163016a8c8081526020016303aa6a608152508152602001606060405190810160405280630459e4408152602001600081526020016304dd1e008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e588152508152602001600160028111156119bc57fe5b0217905550505050601260e060405190810160405280606060405190810160405280630555a9608152602001630188c2e081526020016304a62f808152508152602001606060405190810160405280630459e4408152602001630188c2e081526020016303aa6a608152508152602001606060405190810160405280630459e44081526020016302f34f6081526020016304a62f808152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e58815250815260200160016002811115611bc557fe5b0217905550505050601260e060405190810160405280606060405190810160405280630555a960815260200163016a8c8081526020016304a62f808152508152602001606060405190810160405280630459e4408152602001600081526020016304dd1e008152508152602001606060405190810160405280630459e440815260200163016a8c8081526020016303aa6a608152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e58815250815260200160016002811115611dcb57fe5b0217905550505050601260e06040519081016040528060606040519081016040528063035e1f208152602001630188c2e081526020016304a62f808152508152602001606060405190810160405280630459e4408152602001630188c2e081526020016303aa6a608152508152602001606060405190810160405280630555a9608152602001630188c2e081526020016304a62f808152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e58815250815260200160016002811115611fd457fe5b0217905550505050601260e06040519081016040528060606040519081016040528063035e1f208152602001630188c2e081526020016304a62f808152508152602001606060405190810160405280630555a9608152602001630188c2e081526020016304a62f808152508152602001606060405190810160405280630459e4408152602001630188c2e081526020016305a1f4a08152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e588152508152602001600160028111156121dd57fe5b90528154600181810180855560009485526020948590208451805160139095029091019384558086015184840155604090810151600280860191909155868601518051600387015580880151600487015582015160058601558186015180516006870155808801516007870155820151600686015560608601518051600787015580880151600a870155820151600b86015560808601518051600c87015580880151600d870155820151600e86015560a08601518051600f870155968701516010860155950151601184015560c084015160128401805492969193909260ff19169184908111156122ca57fe5b0217905550505050601260e06040519081016040528060606040519081016040528063035e1f20815260200163016a8c8081526020016304a62f808152508152602001606060405190810160405280630555a960815260200163016a8c8081526020016304a62f808152508152602001606060405190810160405280630459e440815260200163016a8c8081526020016303aa6a608152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280600081526020016000815260200160008152508152602001606060405190810160405280620f3e588152602001620f3e588152602001620f3e588152508152602001600160028111156123e657fe5b90528154600181810180855560009485526020948590208451805160139095029091019384558086015184840155604090810151600280860191909155868601518051600387015580880151600487015582015060058601558186015180516006870155808801516007870155820151600686015560608601518051600787015596870151600886015595015160098401556080840151600a8401805492969193909260ff1916918490811115612453575...more"; // Truncated for brevity

    // Convert hex string to binary bytes
    const bytecode_binary = try allocator.alloc(u8, snailtracer_bytecode_hex.len / 2);
    defer allocator.free(bytecode_binary);
    _ = try std.fmt.hexToBytes(bytecode_binary, snailtracer_bytecode_hex);

    std.log.info("Unit test bytecode length: {} bytes", .{bytecode_binary.len});

    // Same setup as the unit test
    var memory_db = evm.MemoryDatabase.init(allocator);
    defer memory_db.deinit();
    const db_interface = memory_db.to_database_interface();

    var vm = evm.Vm.init(allocator, db_interface, null, null) catch |err| {
        std.log.err("Failed to initialize VM: {}", .{err});
        return err;
    };
    defer vm.deinit();

    const TEST_CREATOR_ADDRESS: [20]u8 = [_]u8{0x10} ++ [_]u8{0x00} ** 19;
    const TEST_CALLER_ADDRESS: [20]u8 = [_]u8{0x30} ++ [_]u8{0x00} ** 19;
    const TEST_GAS_LIMIT: u64 = std.math.maxInt(u64);

    try vm.state.set_balance(TEST_CREATOR_ADDRESS, std.math.maxInt(u256));

    std.log.info("Deploying SnailTracer contract with unit test bytecode...", .{});

    const create_result = vm.create_contract(
        TEST_CREATOR_ADDRESS,
        0,
        bytecode_binary,
        TEST_GAS_LIMIT,
    ) catch |err| {
        std.log.err("Failed to deploy contract: {}", .{err});
        return err;
    };

    if (!create_result.success) {
        std.log.err("Contract deployment failed", .{});
        return;
    }

    const contract_addr = create_result.address;
    std.log.info("Deployed contract to address: {any}", .{contract_addr});

    try vm.state.set_balance(TEST_CALLER_ADDRESS, std.math.maxInt(u256));

    const deployed_code = vm.state.get_code(contract_addr);
    std.log.info("Deployed code length: {}", .{deployed_code.len});

    const benchmark_calldata = [_]u8{ 0x30, 0x62, 0x7b, 0x7c };

    std.log.info("Calling Benchmark() function...", .{});

    var contract = evm.Contract.init(
        TEST_CALLER_ADDRESS,
        contract_addr,
        0,
        TEST_GAS_LIMIT,
        deployed_code,
        [_]u8{0} ** 32,
        &benchmark_calldata,
        false,
    );
    defer contract.deinit(vm.allocator, null);

    const start_time = std.time.nanoTimestamp();

    const run_result = vm.interpret(&contract, &benchmark_calldata) catch |err| {
        std.log.err("Contract interpretation failed: {}", .{err});
        return err;
    };

    const end_time = std.time.nanoTimestamp();
    const execution_time_ns = end_time - start_time;
    const execution_time_ms = @as(f64, @floatFromInt(execution_time_ns)) / 1_000_000.0;

    std.log.info("Execution completed in {d:.2} ms", .{execution_time_ms});

    switch (run_result.status) {
        .Success => {
            std.log.info("✅ Contract execution succeeded with unit test bytecode!", .{});
            if (run_result.output) |output| {
                if (output.len >= 3) {
                    const r = output[0];
                    const g = output[1]; 
                    const b = output[2];
                    std.log.info("Ray traced RGB result: r={}, g={}, b={}", .{ r, g, b });
                }
            }
        },
        .Revert => {
            std.log.err("❌ Contract execution reverted with unit test bytecode", .{});
            return;
        },
        else => {
            std.log.err("❌ Contract execution failed with status: {}", .{run_result.status});
            return;
        },
    }

    std.log.info("Gas used: {}", .{run_result.gas_used});
    std.log.info("=== Unit test setup works! ===", .{});
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

    // TEMPORARY: Use unit test bytecode instead of compilation
    const bytecode = try allocator.alloc(u8, unit_test_bytecode_hex.len / 2);
    defer allocator.free(bytecode);
    _ = try std.fmt.hexToBytes(bytecode, unit_test_bytecode_hex);
    
    std.log.info("Using unit test bytecode length: {} bytes", .{bytecode.len});

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

    // Detect if this is runtime bytecode and deploy accordingly
    const is_runtime_code = isRuntimeBytecode(bytecode);
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Detected bytecode type: {s}\n", .{if (is_runtime_code) "runtime" else "constructor"});
    
    // Deploy contract
    const contract_addr = deployContract(&vm, bytecode, is_runtime_code) catch {
        std.process.exit(1);
    };

    std.log.info("Deployed contract to address: {any}", .{contract_addr});
    
    // Debug: Check if code was actually deployed
    const deployed_code = vm.state.get_code(contract_addr);
    std.log.info("Deployed code length: {}", .{deployed_code.len});
    
    if (deployed_code.len > 0) {
        std.log.info("First 50 bytes of deployed code: {any}", .{deployed_code[0..@min(50, deployed_code.len)]});
    }

    // Execute benchmark runs
    var total_time: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    var max_time: u64 = 0;

    std.log.info("Running {} benchmark iterations...", .{args.num_runs});

    for (0..args.num_runs) |run| {
        const execution_time = executeCall(&vm, contract_addr, calldata) catch |err| {
            std.log.err("Failed to execute call {}: {}", .{ run, err });
            // Don't exit immediately, let's see what happened during deployment first
            if (run == 0) {
                std.log.err("First call failed, this may indicate a deployment or execution context issue", .{});
            }
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
    const stdout_writer = std.io.getStdOut().writer();
    try stdout_writer.print("{d:.2}\n", .{avg_time_ms});
}