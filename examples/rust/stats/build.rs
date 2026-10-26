//! Builds the Z# library (stats.zs) with `zs build --lib`, a static library and its header in
//! OUT_DIR, and links it: zs on PATH, or the compiler named by $ZS.
use std::{env, path::PathBuf, process::Command};

fn main() {
    let out = PathBuf::from(env::var("OUT_DIR").unwrap());
    let zs = env::var("ZS").unwrap_or_else(|_| "zs".to_string());
    let status = Command::new(&zs)
        .args(["build", "stats.zs", "--lib", "--release", "-o"])
        .arg(out.join("libzstats.a"))
        .status()
        .unwrap_or_else(|e| panic!("can't run {zs} ({e}): put zs on PATH, or name it in $ZS"));
    assert!(status.success(), "zs build failed");
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=zstats");
    println!("cargo:rerun-if-changed=stats.zs");
    println!("cargo:rerun-if-env-changed=ZS");
}
