  # src = fetchFromGitHub {
  #   owner = "kamo104";
  #   repo = "Sunshine";
  #   rev = "072a21a4d58218b0c07e63e1fadfc91937a70841";
  #   hash = "sha256-S8ZmmUMVjF8pMepqFDHavJlex1QTz25azIZ9LXkcSs0=";
  #   fetchSubmodules = true;
  # };

  # # build webui
  # ui = buildNpmPackage {
  #   inherit (finalAttrs) src version;
  #   pname = "sunshine-ui";
  #   npmDepsHash = "sha256-6Wbe50W6s2/E1Xwd/N9ftFh8jo9yidSvWst/RcfgGXE=";
  #   npmDepsFetcherVersion = 2;

  #   # use generated package-lock.json as upstream does not provide one
  #   postPatch = ''
  #     cp ${./package-lock.json} ./package-lock.json
  #   '';

  #   installPhase = ''
  #     runHook preInstall

  #     mkdir -p "$out"
  #     cp -a . "$out"/

  #     runHook postInstall
  #   '';
  # };



{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchzip,
  autoPatchelfHook,
  autoAddDriverRunpath,
  makeWrapper,
  buildNpmPackage,
  nixosTests,
  cmake,
  avahi,
  libevdev,
  libpulseaudio,
  libxtst,
  libxrandr,
  libxi,
  libxfixes,
  libxdmcp,
  libx11,
  libxcb,
  openssl,
  libopus,
  boost,
  pkg-config,
  libdrm,
  wayland,
  wayland-scanner,
  libffi,
  libcap,
  libgbm,
  curl,
  pcre,
  pcre2,
  python3,
  libuuid,
  libselinux,
  libsepol,
  libthai,
  libdatrie,
  libxkbcommon,
  libepoxy,
  libva,
  libvdpau,
  libglvnd,
  numactl,
  amf-headers,
  svt-av1,
  shaderc,
  vulkan-loader,
  libappindicator,
  libnotify,
  pipewire,
  miniupnpc,
  nlohmann_json,
  config,
  coreutils,
  udevCheckHook,
  cudaSupport ? config.cudaSupport,
  cudaPackages ? { },
  apple-sdk_15,
}:
let
  inherit (stdenv.hostPlatform) isDarwin isLinux;
  stdenv' = if cudaSupport then cudaPackages.backendStdenv else stdenv;

  # Upstream's cmake fetches a pre-built ffmpeg from LizardByte/build-deps at
  # configure time. We can't do network I/O during the build, so fetch it via
  # a fixed-output derivation and point cmake at it via FFMPEG_PREPARED_BINARIES.
  # The tag must match the commit of the third-party/build-deps submodule pinned
  # in the Sunshine release.
  buildDepsTag = "v2026.516.30821";
  ffmpegArch =
    {
      x86_64-linux = "Linux-x86_64";
      aarch64-linux = "Linux-aarch64";
    }
    .${stdenv.hostPlatform.system}
      or (throw "sunshine: unsupported system ${stdenv.hostPlatform.system} for prebuilt ffmpeg");
  ffmpegPrebuilt = fetchzip {
    url = "https://github.com/LizardByte/build-deps/releases/download/${buildDepsTag}/${ffmpegArch}-ffmpeg.tar.gz";
    hash =
      {
        x86_64-linux = "sha256-H0VsLwcn/RaVZXH0ewA2ZeIfl9/pH7RFgxLJZiNRC98=";
        aarch64-linux = "sha256-9saIfsuThaI4qYkM3zMkaRzFqzp1O7mrNhJyIQEv5VY=";
      }
      .${stdenv.hostPlatform.system};
    stripRoot = false;
  };
in
stdenv'.mkDerivation (finalAttrs: {
  pname = "sunshine";
  version = "v2026.516.143833";

  src = fetchFromGitHub {
    owner = "kamo104";
    repo = "Sunshine";
    rev = "f8a168dff0195e49910d546570e96b9531a3aacc";
    hash = "sha256-6Rrfms318wKttt7HlpRn7o0Hlbqxsgj1IFzZbhPJy6E=";
    fetchSubmodules = true;
  };

  # build webui
  ui = buildNpmPackage {
    inherit (finalAttrs) src version;
    pname = "sunshine-ui";
    npmDepsHash = "sha256-YnNnuAdj/S5LGNytqIsmCApIec8DTWKF6VIJ7AXUctU=";
    npmDepsFetcherVersion = 2;

    # use generated package-lock.json as upstream does not provide one
    postPatch = ''
      cp ${./package-lock.json} ./package-lock.json
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -a . "$out"/

      runHook postInstall
    '';
  };


  postPatch = # don't look for npm since we build webui separately
  ''
    substituteInPlace cmake/targets/common.cmake \
      --replace-fail 'find_program(NPM npm REQUIRED)' ""
  ''
  # use system boost instead of FetchContent.
  # FETCH_CONTENT_BOOST_USED prevents Simple-Web-Server from re-finding boost
  + ''
    sed -i -E 's/set\(BOOST_VERSION "[^"]*"\)/set(BOOST_VERSION "${boost.version}")/' \
      cmake/dependencies/Boost_Sunshine.cmake
    echo 'set(FETCH_CONTENT_BOOST_USED TRUE)' >> cmake/dependencies/Boost_Sunshine.cmake
  ''
  # remove upstream dependency on systemd and udev
  + lib.optionalString isLinux ''
    substituteInPlace cmake/packaging/linux.cmake \
      --replace-fail 'find_package(Systemd)' "" \
      --replace-fail 'find_package(Udev)' ""

    # The remaining @VAR@ placeholders in the .desktop file (PROJECT_NAME,
    # PROJECT_DESCRIPTION, PROJECT_FQDN, SUNSHINE_DESKTOP_ICON,
    # CMAKE_INSTALL_FULL_DATAROOTDIR) are substituted by cmake's
    # configure_file(... @ONLY) during the build.
    substituteInPlace packaging/linux/dev.lizardbyte.app.Sunshine.desktop \
      --replace-fail '/usr/bin/env systemctl start --u app-@PROJECT_FQDN@' 'sunshine'

    substituteInPlace packaging/linux/app-dev.lizardbyte.app.Sunshine.service.in \
      --replace-fail '/bin/sleep' '${lib.getExe' coreutils "sleep"}'
  '';

  nativeBuildInputs = [
    cmake
    pkg-config
    # glad's generator needs Jinja2 + setuptools at configure time;
    # GLAD_SKIP_PIP_INSTALL=ON tells cmake not to pip-install them.
    (python3.withPackages (ps: [
      ps.jinja2
      ps.setuptools
    ]))
    makeWrapper
  ]
  ++ lib.optionals isLinux [
    wayland-scanner
    shaderc # provides glslc, needed at configure time for shader compilation
    # Avoid fighting upstream's usage of vendored ffmpeg libraries
    autoPatchelfHook
  ]
  ++ lib.optionals cudaSupport [
    autoAddDriverRunpath
    cudaPackages.cuda_nvcc
    (lib.getDev cudaPackages.cuda_cudart)
  ];

  buildInputs = [
    boost
    curl
    miniupnpc
    nlohmann_json
    openssl
    libopus
  ]
  ++ lib.optionals isLinux [
    avahi
    libevdev
    libpulseaudio
    libx11
    libxcb
    libxfixes
    libxrandr
    libxtst
    libxi
    libdrm
    wayland
    libffi
    libevdev
    libcap
    libdrm
    pcre
    pcre2
    libuuid
    libselinux
    libsepol
    libthai
    libdatrie
    libxdmcp
    libxkbcommon
    libepoxy
    libva
    libvdpau
    numactl
    libgbm
    amf-headers
    svt-av1
    vulkan-loader
    pipewire
    libappindicator
    libnotify
  ]
  ++ lib.optionals cudaSupport [
    cudaPackages.cudatoolkit
    cudaPackages.cuda_cudart
  ]
  ++ lib.optionals isDarwin [
    apple-sdk_15
  ];

  runtimeDependencies = lib.optionals isLinux [
    avahi
    libgbm
    libxrandr
    libxcb
    libglvnd
  ];

  cmakeFlags = [
    "-Wno-dev"
    (lib.cmakeBool "BOOST_USE_STATIC" false)
    (lib.cmakeBool "BUILD_DOCS" false)
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_NAME" "nixpkgs")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_WEBSITE" "https://nixos.org")
    (lib.cmakeFeature "SUNSHINE_PUBLISHER_ISSUE_URL" "https://github.com/NixOS/nixpkgs/issues")
  ]
  # upstream tries to use systemd and udev packages to find these directories in FHS; set the paths explicitly instead
  ++ lib.optionals isLinux [
    (lib.cmakeBool "UDEV_FOUND" true)
    (lib.cmakeBool "SYSTEMD_FOUND" true)
    (lib.cmakeFeature "UDEV_RULES_INSTALL_DIR" "lib/udev/rules.d")
    (lib.cmakeFeature "SYSTEMD_USER_UNIT_INSTALL_DIR" "lib/systemd/user")
    (lib.cmakeFeature "SYSTEMD_MODULES_LOAD_DIR" "lib/modules-load.d")
    # used in the generated systemd unit's ExecStart= line
    (lib.cmakeFeature "SUNSHINE_EXECUTABLE_PATH" "${placeholder "out"}/bin/sunshine")
    # avoid cmake's network download of the LizardByte/build-deps ffmpeg tarball
    (lib.cmakeFeature "FFMPEG_PREPARED_BINARIES" "${ffmpegPrebuilt}/ffmpeg")
    # we provide Jinja2/setuptools via python3.withPackages; don't pip-install
    (lib.cmakeBool "GLAD_SKIP_PIP_INSTALL" true)
  ]
  ++ lib.optionals (!cudaSupport) [
    (lib.cmakeBool "SUNSHINE_ENABLE_CUDA" false)
  ]
  ++ lib.optionals isDarwin [
    (lib.cmakeFeature "CMAKE_CXX_STANDARD" "23")
    (lib.cmakeFeature "OPENSSL_ROOT_DIR" "${openssl.dev}")
    (lib.cmakeFeature "SUNSHINE_ASSETS_DIR" "sunshine/assets")
    (lib.cmakeBool "SUNSHINE_BUILD_HOMEBREW" true)
  ];

  env = {
    # needed to trigger CMake version configuration
    BUILD_VERSION = "${finalAttrs.version}";
    BRANCH = "master";
    COMMIT = "";
  };

  # copy webui where it can be picked up by build
  preBuild = ''
    cp -r ${finalAttrs.ui}/build ../
  '';

  buildFlags = [
    "sunshine"
  ];

  # redefine installPhase to avoid attempt to build webui
  installPhase = ''
    runHook preInstall

    cmake --install .

    runHook postInstall
  '';

  # allow Sunshine to find libvulkan
  postFixup = lib.optionalString cudaSupport ''
    wrapProgram $out/bin/sunshine \
      --set LD_LIBRARY_PATH ${lib.makeLibraryPath [ vulkan-loader ]}
  '';

  doInstallCheck = isLinux;

  nativeInstallCheckInputs = lib.optionals isLinux [ udevCheckHook ];

  passthru = {
    tests = lib.optionalAttrs isLinux {
      sunshine = nixosTests.sunshine;
    };
    updateScript = ./updater.sh;
  };

  meta = {
    description = "Game stream host for Moonlight";
    homepage = "https://github.com/LizardByte/Sunshine";
    license = lib.licenses.gpl3Only;
    mainProgram = "sunshine";
    maintainers = with lib.maintainers; [
      devusb
      anish
    ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
