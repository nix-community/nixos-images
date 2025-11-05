use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-changed=clan-logo.svg");

    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let png_path = out_dir.join("clan-logo.png");
    let raw_path = out_dir.join("clan-logo.rgba");

    // Step 1: Rasterize SVG to PNG
    let status = Command::new("resvg")
        .args(&[
            "clan-logo.svg",
            png_path.to_str().unwrap(),
            "--width",
            "223",
            "--height",
            "89",
        ])
        .status()
        .expect("Failed to run resvg");

    if !status.success() {
        panic!("resvg failed to convert SVG to PNG");
    }

    // Step 2: Convert PNG to raw RGBA
    let status = Command::new("gm")
        .args(&[
            "convert",
            png_path.to_str().unwrap(),
            "-depth",
            "8",
            &format!("rgba:{}", raw_path.display()),
        ])
        .status()
        .expect("Failed to run gm");

    if !status.success() {
        panic!("gm failed to convert PNG to raw bitmap");
    }
}
