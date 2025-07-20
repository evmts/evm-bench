use std::{fs, path::PathBuf, time::Instant};

use clap::Parser;
use revm::{
    context::{Context, TxEnv},
    context_interface::result::{ExecutionResult, Output},
    database::CacheDB,
    database_interface::EmptyDB,
    primitives::{address, Bytes, TxKind},
    ExecuteCommitEvm, MainBuilder, MainContext,
};

/// Revolutionary EVM (revm) runner interface
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Path to the hex contract code to deploy and run
    #[arg(long)]
    contract_code_path: PathBuf,

    /// Hex of calldata to use when calling the contract
    #[arg(long)]
    calldata: String,

    /// Number of times to run the benchmark
    #[arg(short, long, default_value_t = 1)]
    num_runs: u8,
}

fn main() {
    let args = Args::parse();

    let caller_address = address!("1000000000000000000000000000000000000001");

    // Read contract bytecode
    let contract_hex = fs::read_to_string(args.contract_code_path).expect("unable to open file");
    let contract_code = hex::decode(&contract_hex.trim()).expect("could not hex decode contract code");
    
    // Handle calldata - support both "0x" prefix and raw hex
    let calldata_str = if args.calldata.starts_with("0x") {
        &args.calldata[2..]
    } else {
        &args.calldata
    };
    let calldata = if calldata_str.is_empty() {
        Vec::new()
    } else {
        hex::decode(calldata_str).expect("could not hex decode calldata")
    };

    // Create EVM context with database
    let ctx = Context::mainnet().with_db(CacheDB::<EmptyDB>::default());
    let mut evm = ctx.build_mainnet();
    
    // Deploy the contract
    let deploy_result = evm.transact_commit(
        TxEnv::builder()
            .caller(caller_address)
            .kind(TxKind::Create)
            .data(Bytes::from(contract_code))
            .gas_limit(10_000_000)
            .build()
            .unwrap(),
    ).expect("Deploy failed");
    
    let ExecutionResult::Success {
        output: Output::Create(_, Some(contract_address)),
        ..
    } = deploy_result else {
        panic!("Failed to create contract: {deploy_result:#?}");
    };
    
    // Run the benchmark
    for i in 0..args.num_runs {
        let timer = Instant::now();
        
        // Execute the transaction
        let result = evm.transact_commit(
            TxEnv::builder()
                .caller(caller_address)
                .kind(TxKind::Call(contract_address))
                .data(Bytes::from(calldata.clone()))
                .gas_limit(1_000_000_000)
                .nonce(1 + i as u64)  // Increment nonce for each transaction
                .build()
                .unwrap(),
        ).expect("Transaction execution failed");
        
        let dur = timer.elapsed();
        
        
        println!("{}", dur.as_micros() as f64 / 1e3)
    }
}