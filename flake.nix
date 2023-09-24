{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, crane, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        craneLib = crane.lib.${system};

        my-crateSrc = craneLib.cleanCargoSource (craneLib.path ./.);
        my-crateVendoredDepsRaw = craneLib.vendorCargoDeps {
          src = my-crateSrc;
        };
        my-crateVendoredDepsPatched = let
          env = {
            src = my-crateVendoredDepsRaw;
            nativeBuildInputs = [
              pkgs.ripgrep
              pkgs.jq
              pkgs.coreutils # for "tr" and "dirname"
            ];
          };
        in
          pkgs.runCommand "deps-PATCHED" env ''
            # set working directory for ripgrep
            cd $src

            # add a comment line after `[features]` in all "Cargo.toml"s in the source that reference `document-features`
            while read toml_file_relative; do

              src_toml_file="$src/$toml_file_relative"
              toml_file="$out/$toml_file_relative"
              crate_dir="$(dirname "$toml_file")"

              # make parent dirs
              mkdir -p "$crate_dir"

              # backup file
              cp "$src_toml_file" "$toml_file".orig

              echo "patching $toml_file"

              # patch file
              ## NOTE: This relies on one line starting with "[features]", after which it adds a comment to decorate the next feature entry
              sed 's/\(\[features\].*\)$/\1\n## Placeholder comment on first feature/g' \
                <"$src_toml_file" \
                >"$toml_file".patched \
                && mv "$toml_file"{.patched,}

            done < <( \
              rg -L -g Cargo.toml ^document-features --json \
                | jq 'select(.type=="match") | .data.path.text' \
                | tr -d '"'
              )
          '';
        my-crateVendoredDeps = pkgs.buildEnv {
          name = "crateVendoredDeps";
          paths = let
            my-crateVendoredDepsPatchedPrioritized =
              my-crateVendoredDepsPatched
              // {
                meta = {
                  priority = 0; # lower priority overrides all others
                };
              };
          in [
            my-crateVendoredDepsRaw
            my-crateVendoredDepsPatchedPrioritized
          ];

          postBuild = let
            src = my-crateVendoredDepsRaw;
          in ''
            # update paths in config.toml to reference this derivation
            chmod +w "$out"
            cp "${src}/config.toml" "$out/config.toml.orig"
            sed "s|${src}|$out|g" <"$out/config.toml.orig" >"$out/config.toml.patched" && mv "$out/config.toml"{.patched,}
          '';
        };
        my-crateArgs = {
          src = my-crateSrc;
          cargoVendorDir = my-crateVendoredDeps;
          doCheck = false;
        };
        my-crate = craneLib.buildPackage my-crateArgs;
      in
      {
        checks = {
          inherit my-crate;
        };

        packages.default = my-crate;

        apps.default = flake-utils.lib.mkApp {
          drv = my-crate;
        };

        devShells.default = craneLib.devShell {
          # Inherit inputs from checks.
          checks = self.checks.${system};
        };
      });
}

