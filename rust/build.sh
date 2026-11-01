#!/bin/sh
# Builds the app page from Rust: the WebAssembly module, then app/index.html. Usage: sh rust/build.sh
set -e
cd "$(dirname "$0")"
cargo build --release -p being-wasm --target wasm32-unknown-unknown
cargo build --release -p being-tools
./target/release/being-tools page
