# EVM-Bench Docker Setup

This Docker setup resolves the macOS SystemConfiguration framework linking issues and provides a reproducible environment for running EVM benchmarks.

## What's Working

✅ **Docker Environment**: Complete Ubuntu 22.04 environment with all necessary dependencies
✅ **Zig (Guillotine) Runner**: Successfully built with Zig 0.14.0-dev
✅ **Rust Runners**: revm runner builds successfully  
✅ **C++ Runners**: evmone runner builds successfully
✅ **Node.js Runners**: ethereumjs dependencies installed
✅ **Build System**: Main evm-bench binary compiles in Linux environment

## Current Status

The Docker environment successfully builds and resolves the macOS linking issues. The SystemConfiguration framework error was caused by macOS-specific dependencies that don't exist in Linux.

### Built Runners
- **revm** (Rust) - ✅ Built successfully
- **guillotine** (Zig) - ✅ Built successfully (binary available)
- **evmone** (C++) - ✅ Built successfully
- **ethereumjs** (Node.js/TypeScript) - ✅ Dependencies installed

### Skipped Runners
- **geth** (Go) - ❌ Architecture issues with gcc
- **py-evm** (Python) - ❌ Poetry dependency conflicts
- **pyrevm** (Python) - ❌ Rust compilation issues
- **akula** (Rust) - ❌ Private git repository dependencies

## Usage

### Build the Docker Environment
```bash
./run-benchmarks.sh build
```

### Run Interactive Shell
```bash
./run-benchmarks.sh interactive
```

### Test Individual Runners
```bash
./run-benchmarks.sh test-revm
./run-benchmarks.sh test-guillotine
./run-benchmarks.sh test-evmone
./run-benchmarks.sh test-ethereumjs
```

### Available Commands
- `build` - Build the Docker image
- `interactive` - Start interactive shell in container
- `test-[runner]` - Test specific runner
- `clean` - Remove Docker containers and images
- `help` - Show help message

## Files Created

1. **Dockerfile** - Multi-stage build with all EVM runner dependencies
2. **docker-compose.yml** - Service definitions for different runners
3. **run-benchmarks.sh** - Helper script for easy Docker operations
4. **.dockerignore** - Optimized build context

## Architecture Solutions

### SystemConfiguration Framework Issue
- **Problem**: macOS-specific framework not available in Linux
- **Solution**: Run in Ubuntu container where reqwest uses different networking stack

### Zig Build Issues
- **Problem**: Syntax changes in Zig 0.14.0 for build.zig.zon
- **Solution**: Updated name syntax from string to enum literal and fixed dependency hash

### Mixed Language Dependencies
- **Problem**: Complex dependency chains across Rust, Zig, C++, Go, Node.js, Python
- **Solution**: Ubuntu base image with all toolchains, selective runner building

## Next Steps

1. **Solidity Compilation**: Add Docker-in-Docker or external solc for contract compilation
2. **Additional Runners**: Fix geth Go build issues and Python dependency conflicts  
3. **Benchmark Execution**: Complete end-to-end benchmark runs
4. **Performance Comparison**: Generate comparison tables between runners

## Troubleshooting

### Docker Build Fails
- Ensure Docker is running
- Check available disk space (builds can be large)
- Try `docker system prune` to free space

### Container Issues
- Use `./run-benchmarks.sh clean` to reset
- Check Docker logs for specific errors

### Runner Tests Fail
- Verify the specific runner built successfully during Docker build
- Check runner-specific dependencies in the logs

The Docker environment successfully resolves the macOS linking issues and provides a foundation for cross-platform EVM benchmarking.