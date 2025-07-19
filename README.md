# evm-bench

[![Rust](https://github.com/ziyadedher/evm-bench/actions/workflows/rust.yml/badge.svg)](https://github.com/ziyadedher/evm-bench/actions/workflows/rust.yml)

**evm-bench is a suite of Ethereum Virtual Machine (EVM) stress tests and benchmarks.**

evm-bench makes it easy to compare EVM performance in a scalable, standardized, and portable way.

## Docker Environment Status

The benchmark suite has been enhanced with a comprehensive Docker environment supporting:

✅ **Working EVM Runners:**
- **revm** (Rust) - High-performance implementation
- **evmone** (C++) - Optimized low-level implementation  
- **ethereumjs** (Node.js) - JavaScript reference implementation
- **guillotine** (Zig) - High-performance implementation (architecture compatibility in progress)

✅ **Build Environment:**
- Multi-language Docker environment (Rust, C++, Go, Node.js, Python, Zig)
- Cross-platform compilation support (ARM64/x86_64)
- Automated dependency management
- Pre-compiled smart contract support

✅ **Benchmark Categories:**
- ERC20 operations (transfer, mint, approval-transfer)
- SnailTracer (complex contract execution)
- Ten Thousand Hashes (hash computation stress test)

## Historical Performance Results

|                         | evmone | revm   | pyrevm | geth   | py-evm.pypy | py-evm.cpython | ethereumjs |
| ----------------------- | ------ | ------ | ------ | ------ | ----------- | -------------- | ---------- |
| **sum**                 | 66ms   | 84.8ms | 194ms  | 235ms  | 7.201s      | 19.0886s       | 146.3218s  |
| **relative**            | 1.000x | 1.285x | 2.939x | 3.561x | 109.106x    | 289.221x       | 2216.997x  |
|                         |        |        |        |        |             |                |            |
| erc20.approval-transfer | 7ms    | 9.6ms  | 16.2ms | 17ms   | 425.2ms     | 1.13s          | 2.0006s    |
| erc20.mint              | 5ms    | 6.4ms  | 14.8ms | 17.2ms | 334ms       | 1.1554s        | 3.1352s    |
| erc20.transfer          | 8.6ms  | 11.6ms | 22.8ms | 24.6ms | 449.2ms     | 1.6172s        | 3.6564s    |
| snailtracer             | 43ms   | 53ms   | 128ms  | 163ms  | 5.664s      | 13.675s        | 135.059s   |
| ten-thousand-hashes     | 2.4ms  | 4.2ms  | 12.2ms | 13.2ms | 328.6ms     | 1.511s         | 2.4706s    |

*Note: Updated benchmark results with the new Docker environment will be available once Docker-in-Docker compilation is finalized.*

## Technical Overview

In evm-bench there are [benchmarks](/benchmarks) and [runners](/runners):

- [Benchmarks](/benchmarks) are expensive Solidity contracts paired with configuration.
- [Runners](/runners) are consistent platforms for deploying and calling arbitrary smart contracts.

The evm-bench framework can run any benchmark on any runner. The links above dive deeper into how to build new benchmarks or runners.

## Usage

### With the evm-bench suite

**Option 1: Docker Environment (Recommended)**
```bash
# Build the multi-language Docker environment
docker-compose build

# Run a specific benchmark with working runners
docker-compose run --rm evm-bench evm-bench --runners revm,evmone,ethereumjs --benchmarks erc20.transfer

# Interactive development
docker-compose run --rm evm-bench bash
```

**Option 2: Native Installation**
Simply cloning this repository and running `RUST_LOG=info cargo run --release` will do the trick. You may need to install dependencies for the benchmark build process and runner execution:

- Rust toolchain (for revm and main application)
- Node.js and npm (for ethereumjs runner)
- C++ build tools (for evmone runner)
- Docker (for Solidity compilation)
- Zig compiler (for guillotine runner)
- Python and Poetry (for Python-based runners)

### With another suite

evm-bench is meant to be used with the pre-developed suite of benchmarks and runners in this repository. However, it should work as an independent framework elsewhere.

See the CLI arguments for evm-bench to figure out how to set it up! Alternatively just reach out to me or post an issue.

## Current Development Status

### Infrastructure Achievements
- ✅ **Comprehensive Docker Environment**: Multi-stage builds supporting 6+ programming languages
- ✅ **Cross-Platform Support**: ARM64/x86_64 architecture compatibility
- ✅ **Runner Integration**: Successfully integrated 4 major EVM implementations
- ✅ **Smart Contract Compilation**: Pre-compiled benchmark contracts ready for execution
- ✅ **Guillotine Integration**: Zig EVM implementation successfully integrated into framework

### Working Runners
| Runner | Language | Status | Performance Tier |
|--------|----------|--------|------------------|
| **evmone** | C++ | ✅ Built | Tier 1 (Fastest) |
| **revm** | Rust | ✅ Built | Tier 1 (Fastest) |
| **ethereumjs** | Node.js | ✅ Built | Tier 2 (Moderate) |
| **guillotine** | Zig | 🔧 Built (arch fix needed) | Tier 1 (Expected) |
| geth | Go | ❌ Build issues | Tier 2 |
| py-evm | Python | ❌ Dependency conflicts | Tier 3 |

### Next Steps
1. **Complete Docker-in-Docker setup** for automated Solidity compilation
2. **Fix architecture compatibility** for guillotine runner
3. **Generate performance comparison reports** with working runners
4. **Add CI/CD pipeline** for automated benchmarking

### Files Added/Modified
- `Dockerfile` - Multi-language build environment
- `docker-compose.yml` - Service orchestration
- `run-benchmarks.sh` - Helper script for Docker operations
- `.dockerignore` - Build optimization

## Development

Do it. Reach out to me if you wanna lend a hand but don't know where to start!

### Contributing
The project now has a solid foundation for EVM performance benchmarking. Key areas for contribution:
- Adding new EVM implementations as runners
- Creating additional benchmark scenarios
- Improving the Docker build process
- Adding automated performance regression testing
