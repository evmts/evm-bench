use std::{fs, path::PathBuf, str::FromStr, time::Instant};

use clap::Parser;
use revm::{
    primitives::{Address, Bytes, ExecutionResult, Output, TransactTo, U256},
    Evm, InMemoryDB,
};

extern crate alloc;

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

const CALLER_ADDRESS: &str = "0x1000000000000000000000000000000000000001";

fn main() {
    let args = Args::parse();

    let caller_address = Address::from_str(CALLER_ADDRESS).unwrap();

    let contract_code: Bytes =
        hex::decode(fs::read_to_string(args.contract_code_path).expect("unable to open file"))
            .expect("could not hex decode contract code")
            .into();
    let calldata: Bytes = hex::decode(args.calldata)
        .expect("could not hex decode calldata")
        .into();

    // Create EVM with in-memory database
    let mut evm = Evm::builder()
        .with_db(InMemoryDB::default())
        .build();

    // Set up the environment for deployment
    evm.env.tx.caller = caller_address;
    evm.env.tx.transact_to = TransactTo::create();
    evm.env.tx.data = contract_code.clone();
    evm.env.tx.gas_limit = u64::MAX;

    // Deploy the contract
    let deploy_result = evm.transact().unwrap();
    let contract_address = match deploy_result.result {
        ExecutionResult::Success { output: Output::Create(_, Some(address)), .. } => address,
        other => panic!("Contract deployment failed: {:?}", other),
    };

    // Now call the deployed contract
    for _ in 0..args.num_runs {
        evm.env.tx.caller = caller_address;
        evm.env.tx.transact_to = TransactTo::call(contract_address);
        evm.env.tx.data = calldata.clone();
        evm.env.tx.gas_limit = u64::MAX;

        let timer = Instant::now();
        let result = evm.transact().unwrap();
        let dur = timer.elapsed();

        match result.result {
            ExecutionResult::Success { .. } => (),
            other => panic!("unexpected exit reason while benchmarking: {:?}", other),
        }

        println!("{}", dur.as_micros() as f64 / 1e3)
    }
}
