#!/bin/bash

set -e

echo "🚀 EVM-Bench Docker Setup"
echo "========================="

# Function to print colored output
print_status() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose >/dev/null 2>&1; then
    print_error "docker-compose is not installed. Please install it and try again."
    exit 1
fi

# Create results directory if it doesn't exist
mkdir -p results

# Function to run a specific benchmark
run_single_benchmark() {
    local runner=$1
    print_status "Running benchmark for $runner..."
    docker-compose run --rm ${runner}-runner || print_warning "Benchmark for $runner failed or had issues"
}

# Function to run all benchmarks
run_all_benchmarks() {
    print_status "Running all benchmarks..."
    docker-compose run --rm full-benchmark || print_warning "Full benchmark run had issues"
}

# Function to test a single runner
test_runner() {
    local runner=$1
    print_status "Testing $runner runner..."
    docker-compose run --rm evm-bench evm-bench --runners $runner --benchmarks erc20.transfer
}

# Parse command line arguments
case "${1:-all}" in
    "build")
        print_status "Building Docker image..."
        docker-compose build
        ;;
    "guillotine"|"zig")
        run_single_benchmark "guillotine"
        ;;
    "revm")
        run_single_benchmark "revm"
        ;;
    "evmone")
        run_single_benchmark "evmone"
        ;;
    "geth")
        run_single_benchmark "geth"
        ;;
    "ethereumjs")
        run_single_benchmark "ethereumjs"
        ;;
    "test-guillotine")
        test_runner "guillotine"
        ;;
    "test-revm")
        test_runner "revm"
        ;;
    "test-evmone")
        test_runner "evmone"
        ;;
    "test-geth")
        test_runner "geth"
        ;;
    "test-ethereumjs")
        test_runner "ethereumjs"
        ;;
    "interactive"|"shell")
        print_status "Starting interactive shell..."
        docker-compose run --rm evm-bench bash
        ;;
    "clean")
        print_status "Cleaning up Docker containers and images..."
        docker-compose down --rmi all --volumes --remove-orphans
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [COMMAND]"
        echo ""
        echo "Commands:"
        echo "  build              Build the Docker image"
        echo "  all                Run all benchmarks (default)"
        echo "  guillotine|zig     Run benchmarks with Zig (guillotine) runner"
        echo "  revm              Run benchmarks with revm runner"
        echo "  evmone            Run benchmarks with evmone runner"
        echo "  geth              Run benchmarks with geth runner"
        echo "  ethereumjs        Run benchmarks with ethereumjs runner"
        echo "  test-[runner]     Test a specific runner with a single benchmark"
        echo "  interactive|shell  Start an interactive shell in the container"
        echo "  clean             Clean up Docker containers and images"
        echo "  help              Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 build           # Build the Docker image"
        echo "  $0 guillotine      # Run Zig benchmarks"
        echo "  $0 test-revm       # Test revm runner"
        echo "  $0 interactive     # Start interactive shell"
        ;;
    "all"|*)
        run_all_benchmarks
        ;;
esac

print_status "Done!"