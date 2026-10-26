//! Builds the Z# library (../stats/stats.zs) for the chip with `zs build --lib --target
//! cortex-m4`, an archive with the Z# runtime and no startup (the firmware's is cortex-m-rt's),
//! links it, and gives the linker memory.x: zs on PATH, or the compiler named by $ZS.
use std::{env, fs, path::PathBuf, process::Command};

fn main() {
    let out = PathBuf::from(env::var("OUT_DIR").unwrap());
    let zs = env::var("ZS").unwrap_or_else(|_| "zs".to_string());
    let status = Command::new(&zs)
        .args(["build", "../stats/stats.zs", "--lib", "--target", "cortex-m4", "--release", "-o"])
        .arg(out.join("libzstats.a"))
        .status()
        .unwrap_or_else(|e| panic!("can't run {zs} ({e}): put zs on PATH, or name it in $ZS"));
    assert!(status.success(), "zs build failed");
    fs::copy("memory.x", out.join("memory.x")).unwrap();
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=zstats");
    println!("cargo:rerun-if-changed=../stats/stats.zs");
    println!("cargo:rerun-if-changed=memory.x");
    println!("cargo:rerun-if-env-changed=ZS");
}
