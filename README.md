Example reproduction of the [`document-features`](https://lib.rs/crates/document-features) crate not being able to find comments in a dependency's Cargo.toml, when built via [ipetkov/crane](https://github.com/ipetkov/crane)

```
$ cargo new --bin the_bin

$ cd the_bin/

$ cargo add --git https://github.com/danjl1100/example_uses_document_features.git

$ cargo c
+ command cargo c
    Finished dev [unoptimized + debuginfo] target(s) in 0.03s

$ nix build
warning: Git tree '/home/user/the_bin' is dirty
error: builder for '/nix/store/bvizj8r1dbz8941pbvqr1s0s0qpr2w6z-the_bin-deps-0.1.0.drv' failed with exit code 101;
       last 10 log lines:
       >     Checking example_uses_document_features v0.1.0 (https://github.com/danjl1100/example_uses_document_features.git#a1ba56e5)
       > error: Could not find documented features in Cargo.toml
       >  --> /nix/store/680bw6m3wbvjim5qsymmllcbk61pf7v5-vendor-cargo-deps/6324285ea70798e13c0a2ff48894e089c59e1e9b1901e701033e48ef46db6c00/example_uses_document_features-0.1.0/src/lib.rs:2:10
       >   |
       > 2 | #![doc = document_features::document_features!()]
       >   |          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
       >   |
       >   = note: this error originates in the macro `document_features::document_features` (in Nightly builds, run with -Z macro-backtrace for more info)
       >
       > error: could not compile `example_uses_document_features` (lib) due to previous error
       For full logs, run 'nix log /nix/store/bvizj8r1dbz8941pbvqr1s0s0qpr2w6z-the_bin-deps-0.1.0.drv'.
error: 1 dependencies of derivation '/nix/store/x9ww0x9svbvfl7y1l3ni060pds2pf4ck-the_bin-0.1.0.drv' failed to build

$ cat /nix/store/680bw6m3wbvjim5qsymmllcbk61pf7v5-vendor-cargo-deps/6324285ea70798e13c0a2ff48894e089c59e1e9b1901e701033e48ef46db6c00/example_uses_document_features-0.1.0/Cargo.toml
[package]
name = "example_uses_document_features"
version = "0.1.0"
edition = "2021"

[dependencies]
document-features = "0.2.7"

[features]
feature = []

$ cat ~/.cargo/git/checkouts/example_uses_document_features-5fcd98ea203068e9/a1ba56e/Cargo.toml
[package]
name = "example_uses_document_features"
version = "0.1.0"
edition = "2021"

# See more keys and their definitions at https://doc.rust-lang.org/cargo/reference/manifest.html

[dependencies]
document-features = "0.2.7"

[features]
## Documented
feature = []
```
Keen-eyed observers will note the `## Documented` line present in the git checkout (last output), but not in the cleanCargoToml version used internally by `ipetkov/crane` (second-to-last output).

It seems obvious to me that both projects on their own are doing the smart thing:
- `document-features` automates tedious documentation of crate features
- `ipetkov/crane` strips metadata from dependencies' Cargo.toml, for fewer cache misses

They just aren't compatible with each other.. without some extra effort.


The reason I am writing it up, is the high quality [`embassy`]() libraries for embedded device programming make frequent use of `document-features` as a dependency, so my experiment with building embedded via flakes is currently failing.


I have tried fiddling with `overrideScope'` to deactivate `cleanCargoToml` when the crate depends on `document-features`, but have not been successful.
```patch
-      craneLib = crane.lib.${system};
+      craneLib = crane.lib.${system}.overrideScope' (final: prev: {
+          cleanCargoToml = args: let
+            cleaned = prev.cleanCargoToml (pkgs.lib.traceVal args);
+            raw = builtins.readFile args.cargoToml;
+            original = builtins.fromTOML raw;
+            needs_original = pkgs.lib.hasAttr "document-features" cleaned.dependencies;
+          in
+            if needs_original
+            then (builtins.trace "original for ${cleaned.package.name} ITS DEPENDENCIES MATCHED!" original)
+            else (builtins.trace "cleaned for ${cleaned.package.name}" cleaned);
+        });
```
This still errors.  There must be something I'm missing...
