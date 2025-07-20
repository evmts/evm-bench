#include <evmone/evmone.h>
#include <CLI/CLI.hpp>
#include <evmc/evmc.hpp>
#include <evmc/hex.hpp>
#include <evmc/mocked_host.hpp>

#include <stdlib.h>
#include <chrono>
#include <fstream>
#include <iostream>
#include <string>

using namespace evmc::literals;

constexpr int64_t GAS = 1000000000; // 1 billion gas like revm
const auto ZERO_ADDRESS = 0x0000000000000000000000000000000000000000_address;
const auto CALLER_ADDRESS = 0x1000000000000000000000000000000000000001_address;

int main(int argc, char** argv) {
  std::string contract_code_path;
  std::string calldata;
  uint num_runs;

  CLI::App app{"evmone runner"};
  app.add_option("--contract-code-path", contract_code_path,
                 "Path to the hex contract code to deploy and run")
      ->required();
  app.add_option("--calldata", calldata,
                 "Hex of calldata to use when calling the contract")
      ->required();
  app.add_option("--num-runs", num_runs, "Number of times to run the benchmark")
      ->required();

  CLI11_PARSE(app, argc, argv);

  // Parse calldata
  evmc::bytes calldata_bytes;
  if (!calldata.empty()) {
    // Handle 0x prefix
    if (calldata.substr(0, 2) == "0x") {
      calldata = calldata.substr(2);
    }
    calldata_bytes.reserve(calldata.size() / 2);
    evmc::from_hex(calldata.begin(), calldata.end(),
                   std::back_inserter(calldata_bytes));
  }

  // Create VM
  const auto vm = evmc_create_evmone();
  if (!vm) {
    std::cerr << "Failed to create evmone VM" << std::endl;
    return 1;
  }

  // Read contract bytecode
  std::string contract_code_hex;
  std::ifstream file(contract_code_path);
  if (!file) {
    // Try from parent directories if relative path fails
    std::string alt_path = "../../" + contract_code_path;
    file.open(alt_path);
    if (!file) {
      std::cerr << "Failed to open contract file: " << contract_code_path << std::endl;
      return 1;
    }
  }
  file >> contract_code_hex;
  
  evmc::bytes contract_code;
  contract_code.reserve(contract_code_hex.size() / 2);
  evmc::from_hex(contract_code_hex.begin(), contract_code_hex.end(),
                 std::back_inserter(contract_code));

  // Create host
  evmc::MockedHost host;
  
  // Give the caller some balance
  host.accounts[CALLER_ADDRESS].balance = evmc::uint256be(1000000000000000000); // 1 ETH

  // Deploy the contract
  evmc_message create_msg{};
  create_msg.kind = EVMC_CREATE;
  create_msg.sender = CALLER_ADDRESS;
  create_msg.gas = GAS;
  create_msg.depth = 0;
  create_msg.input_data = contract_code.data();
  create_msg.input_size = contract_code.size();

  evmc::Result create_result{evmc_execute(vm, &host.get_interface(), 
                                         (evmc_host_context*)&host,
                                         EVMC_LONDON, &create_msg,
                                         nullptr, 0)};

  std::cerr << "Create status: " << evmc_status_code_to_string(create_result.status_code) << std::endl;
  std::cerr << "Create gas used: " << (GAS - create_result.gas_left) << std::endl;
  
  if (create_result.status_code != EVMC_SUCCESS) {
    std::cerr << "Contract deployment failed!" << std::endl;
    evmc_destroy(vm);
    return 1;
  }

  // Get deployed contract address - calculate it if not provided
  evmc::address deployed_address;
  bool addr_is_zero = true;
  for (auto b : create_result.create_address.bytes) {
    if (b != 0) {
      addr_is_zero = false;
      break;
    }
  }
  
  if (!addr_is_zero) {
    deployed_address = create_result.create_address;
  } else {
    // Calculate CREATE address: keccak256(rlp([sender, nonce]))[12:]
    // For simplicity, use a hardcoded address
    deployed_address = 0x7e5f4552091a69125d5dfcb7b8c2659029395bdf_address;
  }
  
  // The output of CREATE is the runtime bytecode
  if (create_result.output_size > 0) {
    host.accounts[deployed_address].code = evmc::bytes(create_result.output_data, 
                                                       create_result.output_size);
  } else {
    // If no output, the contract stores its own code during construction
    // For now, use the full bytecode
    host.accounts[deployed_address].code = contract_code;
  }

  std::cerr << "Contract deployed at: ";
  for (auto b : deployed_address.bytes) {
    fprintf(stderr, "%02x", b);
  }
  std::cerr << std::endl;
  std::cerr << "Runtime code size: " << host.accounts[deployed_address].code.size() << std::endl;

  // Prepare call message
  evmc_message call_msg{};
  call_msg.kind = EVMC_CALL;
  call_msg.sender = CALLER_ADDRESS;
  call_msg.recipient = deployed_address;
  call_msg.gas = GAS;
  call_msg.depth = 0;
  call_msg.input_data = calldata_bytes.data();
  call_msg.input_size = calldata_bytes.size();

  // Run benchmarks
  for (uint i = 0; i < num_runs; i++) {
    auto start = std::chrono::steady_clock::now();
    
    evmc::Result call_result{evmc_execute(vm, &host.get_interface(), 
                                         (evmc_host_context*)&host,
                                         EVMC_LONDON, &call_msg,
                                         nullptr, 0)};
    
    auto end = std::chrono::steady_clock::now();
    
    if (call_result.status_code != EVMC_SUCCESS) {
      std::cerr << "Call failed: " 
                << evmc_status_code_to_string(call_result.status_code) 
                << std::endl;
      evmc_destroy(vm);
      return 1;
    }
    
    int64_t gas_used = GAS - call_result.gas_left;
    std::cerr << "Gas used: " << gas_used << std::endl;
    
    using namespace std::literals;
    std::cout << (end - start) / 1.ms << std::endl;
  }

  evmc_destroy(vm);
  return 0;
}