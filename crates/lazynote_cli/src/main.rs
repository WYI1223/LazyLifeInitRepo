//! CLI smoke entry point.
//!
//! # Responsibility
//! - Provide a minimal executable to verify `lazynote_core` linkage.
//! - Keep output deterministic for quick local sanity checks.

fn main() {
    // Why: keep a tiny CLI probe to validate core crate wiring independently
    // from Flutter/FFI runtime setup.
    println!("lazynote_core ping={}", lazynote_core::ping());
    println!("lazynote_core version={}", lazynote_core::core_version());
}
