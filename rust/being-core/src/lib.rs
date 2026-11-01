//! The being of the app: the circuit, the life loop, the saved record and the drawing. no_std + alloc, so the same
//! code runs in the browser (WebAssembly) and later on dedicated hardware.
#![no_std]
extern crate alloc;

pub mod circuit;
pub mod json;
pub mod life;
pub mod draw;
pub mod view;
