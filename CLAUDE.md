# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL: ZERO TOLERANCE FOR FAKE OR PLACEHOLDER BENCHMARKS

**ABSOLUTE PROHIBITION**: Under NO CIRCUMSTANCES are you allowed to implement fake, placeholder, or hardcoded benchmark results. This includes:

- ❌ Outputting hardcoded timing values (e.g., `print("100.0")`)
- ❌ Implementing "temporary" placeholder values
- ❌ Creating mock implementations that don't use real EVM execution
- ❌ Faking benchmark results "just to get it working"
- ❌ Any form of simulated or estimated performance numbers

**WHY THIS IS CRITICAL**:
1. **Trust Destruction**: Publishing fake benchmarks destroys the credibility of the entire project
2. **Community Anger**: Developers rely on accurate benchmarks for critical decisions
3. **Misleading Data**: Fake results can lead to wrong technology choices costing time and money
4. **Reputation Damage**: Once exposed, fake benchmarks permanently damage project reputation
5. **Ethical Violation**: It's fundamentally dishonest and unprofessional

**REQUIRED APPROACH**:
- If you cannot get a runner working with real execution, clearly mark it as "NOT IMPLEMENTED"
- Be honest about implementation status
- Never output fake timing data
- Either implement it correctly or don't implement it at all

**ENFORCEMENT**: Any attempt to create placeholder benchmarks is grounds for immediate termination of assistance.

## Project Overview

evm-bench is a suite of Ethereum Virtual Machine (EVM) stress tests and benchmarks written in Rust. It provides a framework for comparing EVM performance across different implementations in a scalable, standardized, and portable way.

## Architecture

The project follows a modular architecture with two main components:

- **Benchmarks** (`/benchmarks/`): Expensive Solidity contracts with configuration files (`benchmark.evm-bench.json`)
- **Runners** (`/runners/`): Consistent platforms for deploying and calling smart contracts, each with a `runner.evm-bench.json` config

The core Rust application (`/src/`) orchestrates running any benchmark on any runner combination.

### Key Modules
- `main.rs`: CLI argument parsing and orchestration
- `build.rs`: Benchmark compilation logic
- `exec.rs`: Individual benchmark execution on runners
- `run.rs`: Mass execution of benchmarks across runners
- `metadata.rs`: Loading benchmark/runner configurations
- `results.rs`: Result formatting and table generation

## Commands

### Building and Running
```bash
# Build and run all benchmarks on all runners
RUST_LOG=info cargo run --release

# Build only (don't run benchmarks)
cargo run --release -- --build-only

# Skip build step
cargo run --release -- --no-build

# Run specific benchmark
cargo run --release -- --benchmark erc20.transfer

# Run on specific runner
cargo run --release -- --runner revm

# Run specific benchmark on specific runner
cargo run --release -- --benchmark erc20.transfer --runner revm

# Quiet mode (no logging)
cargo run --release -- --quiet
```

### Development
```bash
# Standard Rust development commands
cargo build
cargo test
cargo check
```

## Benchmark Structure

Benchmarks are organized in `/benchmarks/` with:
- Solidity contract files (`.sol`)
- Configuration files (`benchmark.evm-bench.json`)
- Schema validation (`schema.json`)

Current benchmarks include:
- ERC20 operations (mint, transfer, approval-transfer)
- SnailTracer (complex contract execution)
- Ten Thousand Hashes (hash computation stress test)

## Runner Structure  

Runners in `/runners/` implement different EVM backends:
- akula (Rust)
- ethereumjs (TypeScript/Node.js)
- evmone (C++)
- geth (Go)
- py-evm (Python - CPython and PyPy variants)
- pyrevm (Python)
- revm (Rust)

Each runner has:
- Entry script (`entry.sh`)
- Configuration file (`runner.evm-bench.json`)
- Implementation in the runner's native language