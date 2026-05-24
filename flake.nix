{
  description = "Sunshine game streaming host — development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # -------------------------------------------------------------------
        # 1. Pre-built ffmpeg (extracted & patched for the host platform)
        # -------------------------------------------------------------------
        buildDepsTag = "v2026.516.30821";
        ffmpegArch = {
          x86_64-linux  = "Linux-x86_64";
          aarch64-linux = "Linux-aarch64";
        }.${system} or (throw "sunshine: unsupported system ${system} for prebuilt ffmpeg");

        ffmpegPrebuilt = pkgs.fetchzip {
          url = "https://github.com/LizardByte/build-deps/releases/download/${buildDepsTag}/${ffmpegArch}-ffmpeg.tar.gz";
          hash = {
            x86_64-linux  = "sha256-H0VsLwcn/RaVZXH0ewA2ZeIfl9/pH7RFgxLJZiNRC98=";
            aarch64-linux = "sha256-9saIfsuThaI4qYkM3zMkaRzFqzp1O7mrNhJyIQEv5VY=";
          }.${system};
          stripRoot = false;
        };

        # A small derivation that unpacks the pre-built ffmpeg, patches its
        # binaries to find dynamic libraries, and then installs everything into
        # a standard location.
        patchedFfmpeg = pkgs.stdenv.mkDerivation {
          name = "sunshine-ffmpeg-patched";
          src = ffmpegPrebuilt;

          nativeBuildInputs = [ pkgs.autoPatchelfHook ];

          # The libraries required by the pre-built ffmpeg (same as the
          # runtimeDependencies of the Sunshine package). We list them here
          # so autoPatchelf can find and link them.
          buildInputs = sunshine.buildInputs ++ sunshine.runtimeDependencies;

          # We simply copy the whole extracted tree; autoPatchelf will fix the
          # binaries in place during the installPhase.
          installPhase = ''
            mkdir -p $out/ffmpeg
            cp -r . $out/ffmpeg/
          '';
        };

        # -------------------------------------------------------------------
        # 2. The Sunshine package itself (with CUDA disabled by default)
        # -------------------------------------------------------------------
        sunshine = pkgs.callPackage ./package.nix {
          cudaSupport = false;
          # Pass the patched ffmpeg so it can be used at runtime via the
          # FFMPEG_PREPARED_BINARIES cmake flag – this will still be set by the
          # original derivation.
        };

      in
      {
        packages = {
          default   = sunshine;
          sunshine  = sunshine;
          ffmpeg    = patchedFfmpeg;        # also available as a flake output
        };

        devShells.default = pkgs.mkShell {
          # Inherit all build inputs from Sunshine (libraries & headers)
          inputsFrom = [ sunshine ];

          # Extra tools & the patched ffmpeg
          packages = with pkgs; [
            # Patched ffmpeg binaries – now directly usable (e.g., `ffmpeg -version`)
            patchedFfmpeg

            # Development tools
            gdb
            cmake-language-server
            clang-tools
            nixpkgs-fmt
            nil
            git
            nodejs_24
            udev
          ];

          # Add the patched ffmpeg binary directory to PATH
          shellHook = ''
            export PATH="${patchedFfmpeg}/ffmpeg/bin${"$"}{PATH:+:}$PATH"
            export FFMPEG_PREPARED_BINARIES="${patchedFfmpeg}/ffmpeg"
            echo "Sunshine development environment"
            echo " → ffmpeg (patched) available: $(which ffmpeg)"
            echo "Run 'sunshine' to start the host (if built)"
          '';
        };
      }
    );
}
