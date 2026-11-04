use std::{env, path::PathBuf, process::Command};

fn run(command: &mut Command) {
    assert!(
        command.status().expect("run native compiler").success(),
        "native build failed"
    );
}

fn main() {
    assert_eq!(
        env::var("CARGO_CFG_TARGET_OS").unwrap(),
        "macos",
        "This driver targets macOS"
    );
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let sdk = Command::new("xcrun")
        .arg("--show-sdk-path")
        .output()
        .unwrap();
    assert!(sdk.status.success());
    let sdk = String::from_utf8(sdk.stdout).unwrap();
    let arch = match env::var("CARGO_CFG_TARGET_ARCH").unwrap().as_str() {
        "aarch64" => "arm64",
        "x86_64" => "x86_64",
        _ => panic!("unsupported macOS architecture"),
    };
    let sources = [
        "vendor/jbig/jbig.c",
        "vendor/jbig/jbig_ar.c",
        "native/bridge.c",
        "native/scanner.c",
    ];
    let mut objects = Vec::new();
    for (index, source) in sources.iter().enumerate() {
        println!("cargo:rerun-if-changed={source}");
        let object = out.join(format!("native{index}.o"));
        run(Command::new("xcrun")
            .args([
                "clang",
                "-arch",
                arch,
                "-isysroot",
                sdk.trim(),
                "-O2",
                "-fPIC",
                "-Ivendor/jbig",
                "-Wno-deprecated-declarations",
                "-c",
                source,
                "-o",
            ])
            .arg(&object));
        objects.push(object);
    }
    for header in ["vendor/jbig/jbig.h", "vendor/jbig/jbig_ar.h"] {
        println!("cargo:rerun-if-changed={header}");
    }
    run(Command::new("ar")
        .arg("crs")
        .arg(out.join("libm1005native.a"))
        .args(objects));
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=m1005native");
    println!("cargo:rustc-link-lib=cups");
    for framework in ["IOKit", "CoreFoundation", "CoreGraphics", "ImageIO"] {
        println!("cargo:rustc-link-lib=framework={framework}");
    }
}
