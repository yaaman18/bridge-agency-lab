//! The being of the app: the circuit, the life loop, the saved record and the drawing. no_std + alloc, so the same
//! code runs in the browser (WebAssembly) and later on dedicated hardware.
#![no_std]
extern crate alloc;

pub mod circuit;
pub mod json;
pub mod life;
pub mod draw;
pub mod view;
// S49: one life with death (copy of core/one_life.jl), not used by the app. Left out of the WebAssembly build so that
// the app's module stays byte for byte the one app/index.html embeds (core/check/app_embed.js).
#[cfg(not(target_arch = "wasm32"))]
pub mod fdexp;
#[cfg(not(target_arch = "wasm32"))]
pub mod matter;
#[cfg(not(target_arch = "wasm32"))]
pub mod onelife;
#[cfg(not(target_arch = "wasm32"))]
pub mod sha256;
