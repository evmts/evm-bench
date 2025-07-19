# Multi-stage build for evm-bench with all runner dependencies
FROM ubuntu:22.04 as base

# Install system dependencies and Solidity compiler
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    pkg-config \
    libssl-dev \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    cmake \
    clang \
    llvm \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 18 LTS (required for ethereumjs)
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs

# Install Docker for contract compilation
RUN curl -fsSL https://get.docker.com | sh

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install Go
RUN wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz && \
    rm go1.21.5.linux-amd64.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# Install Zig (latest master build)
RUN curl -s https://ziglang.org/download/index.json | grep -o '"tarball": "[^"]*linux-x86_64[^"]*"' | cut -d'"' -f4 | head -1 | xargs wget -O zig-master.tar.xz && \
    tar -C /usr/local -xf zig-master.tar.xz && \
    mv /usr/local/zig-linux-x86_64-* /usr/local/zig && \
    rm zig-master.tar.xz
ENV PATH="/usr/local/zig:${PATH}"

# Install Poetry for Python dependencies
RUN pip3 install poetry

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Build Rust runners (revm only - akula has private git dependencies)
RUN cd runners/revm && cargo build --release

# Build Zig runner (guillotine) - skip for now due to hash mismatch
# RUN cd runners/guillotine && zig build -Doptimize=ReleaseFast

# Build C++ runner (evmone)
RUN cd runners/evmone && \
    mkdir -p build && \
    cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc)

# Build Go runner (geth) - skip for now due to gcc architecture issues
# RUN cd runners/geth && go build -o geth-runner .

# Install Node.js dependencies for ethereumjs (no build step needed)
RUN cd runners/ethereumjs && npm install

# Skip Python runners for now due to dependency issues
# RUN cd runners/py-evm && poetry install --only main --no-root
# RUN cd runners/pyrevm && poetry install --only main --no-root

# Build main evm-bench binary
RUN cargo build --release

# Create runtime stage
FROM ubuntu:22.04 as runtime

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    python3 \
    python3-pip \
    nodejs \
    npm \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install Poetry for runtime
RUN pip3 install poetry

# Install Solidity compiler via npm (cross-platform)
RUN npm install -g solc@0.8.19 && \
    echo '#!/bin/bash\nexec node -e "const solc = require(\"solc\"); const fs = require(\"fs\"); const input = { language: \"Solidity\", sources: {}, settings: { outputSelection: { \"*\": { \"*\": [\"*\"] } } } }; for (let i = 1; i < process.argv.length; i++) { const file = process.argv[i]; if (file.endsWith(\".sol\")) { input.sources[file] = { content: fs.readFileSync(file, \"utf8\") }; } } const output = JSON.parse(solc.compile(JSON.stringify(input))); console.log(JSON.stringify(output));" \"\$@\"' > /usr/local/bin/solc && \
    chmod +x /usr/local/bin/solc

# Copy built binaries and dependencies
COPY --from=base /app/target/release/evm-bench /usr/local/bin/
COPY --from=base /app/runners /app/runners
COPY --from=base /app/benchmarks /app/benchmarks
COPY --from=base /app/Cargo.toml /app/
COPY --from=base /app/src /app/src

# Set working directory
WORKDIR /app

# Ensure all runner scripts are executable
RUN find runners -name "entry.sh" -exec chmod +x {} \;

# Default command
CMD ["evm-bench", "--help"]