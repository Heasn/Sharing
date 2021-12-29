extern crate bindgen;

use serde::Deserialize;
use std::process::Command;

// const MACOS_TARGET_VERSION: &str = "10.14";

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SwiftTargetInfo {
    // triple: String,
// unversioned_triple: String,
// module_triple: String,
// swift_runtime_compatibility_version: String,
// #[serde(rename = "librariesRequireRPath")]
// libraries_require_rpath: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SwiftPaths {
    runtime_library_paths: Vec<String>,
    // runtime_library_import_paths: Vec<String>,
    // runtime_resource_path: String,
}

#[derive(Debug, Deserialize)]
struct SwiftTarget {
    // target: SwiftTargetInfo,
    paths: SwiftPaths,
}

fn main() {
    #[cfg(target_os = "macos")]
    build_mac_os()
}

#[cfg(target_os = "macos")]
fn build_mac_os() {
    Command::new("swift")
        .args(&[
            "build",
            "-c",
            "debug",
            "--package-path",
            "./libs/SharingCore",
        ])
        .spawn()
        .unwrap()
        .wait()
        .expect("failed to build SharingCore");

    let swift_target_info_str = Command::new("swift")
        .args(&[/*"-target", &target,*/ "-print-target-info"])
        .output()
        .unwrap()
        .stdout;
    let swift_target_info: SwiftTarget = serde_json::from_slice(&swift_target_info_str).unwrap();

    swift_target_info
        .paths
        .runtime_library_paths
        .iter()
        .for_each(|path| {
            println!("cargo:rustc-link-search=native={}", path);
        });

    println!("cargo:rustc-link-search=native=./libs/SharingCore/.build/debug/");

    println!("cargo:rustc-link-lib=static=SharingCore");
    println!("cargo:rerun-if-changed=./libs/SharingCore/Sources/*.swift");
}
