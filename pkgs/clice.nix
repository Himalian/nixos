{
  lib,
  stdenv,
  buildBazelPackage,
  bazel_9,
  fetchFromGitHub,
  autoPatchelfHook,
  patchelf,
  file,
  python3,
  git,
  nodejs,
  zlib,
  ncurses,
}:

let
  system = stdenv.hostPlatform.system;

  # Wrap nixpkgs bazel_9 so buildBazelPackage's `(bazel.override { enableNixHacks = true; })` works.
  bazelPkg = lib.makeOverridable (
    {
      enableNixHacks ? false,
    }:
    bazel_9
  ) { };

  depsHash =
    {
      x86_64-linux = "sha256-UajWclXKUGMh4MrFW+A7+RD+Yk748c9If8m44NYzFnQ=";
    }
    .${system} or (throw "Unsupported system: ${system}");

  runtimeLibs = lib.makeLibraryPath [
    stdenv.cc.cc.lib
    zlib
    ncurses
  ];
in
buildBazelPackage rec {
  pname = "clice";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "clice-project";
    repo = "clice";
    tag = "v${version}";
    # run nix run nixpkgs#nix-prefetch-github -- clice-project clice --rev <tag> to get hash
    hash = "sha256-z7BvAJp6C+8JyqoFcNZRPvFxatPMqDz9ajdpIBZZ8I0=";
  };

  bazel = bazelPkg;

  postPatch = ''
    rm -f .bazelversion
    substituteInPlace bazel/clice.bazelrc \
      --replace-fail "/var/tmp/xclang-thinlto" "/tmp/xclang-thinlto"
  '';

  # 保留 clice 自身的 Bzlmod 规则与 LLVM/Clang 工具链配置
  removeRulesCC = false;
  removeLocalConfigCc = false;
  dontAddBazelOpts = true;

  nativeBuildInputs = [
    python3
    git
    nodejs
    file
    patchelf
    autoPatchelfHook
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    zlib
    ncurses
  ];

  bazelFlags = [
    "--noincompatible_strict_action_env"
    "--action_env=PATH"
    "--host_action_env=PATH"
  ];

  bazelTargets = [ "//:package" ];

  bazelBuildFlags = [
    "--spawn_strategy=standalone"
    "--verbose_failures"
  ];

  # 1: fetch and prepare deps
  fetchAttrs = {
    hash = depsHash;

    buildPhase = ''
      runHook preBuild

      concatTo bazelFlagsArray bazelFlags
      BAZEL_USE_CPP_ONLY_TOOLCHAIN=1 \
      USER=homeless-shelter \
      bazel \
        --batch \
        --output_base="$bazelOut" \
        --output_user_root="$bazelUserRoot" \
        vendor \
        --curses=no \
        --vendor_dir="$bazelOut/external/vendor" \
        --loading_phase_threads=1 \
        --jobs="$NIX_BUILD_CORES" \
        "''${bazelFlagsArray[@]}" \
        ${lib.strings.concatStringsSep " " bazelTargets}

      runHook postBuild
    '';

    preInstall = ''
      chmod -R u+w $bazelOut/external

      # Keep only vendor/ and MODULE.bazel.lock in $bazelOut/external to avoid stray store paths.
      cp MODULE.bazel.lock $bazelOut/external/MODULE.bazel.lock
      find $bazelOut/external -mindepth 1 -maxdepth 1 ! -name vendor ! -name MODULE.bazel.lock -exec rm -rf {} +

      rm -f $bazelOut/external/vendor/bazel-external
      rm -rf $bazelOut/external/vendor/*local_config* $bazelOut/external/vendor/@*local_config*
      rm -rf $bazelOut/external/vendor/*local_jdk* $bazelOut/external/vendor/@*local_jdk*
      rm -rf $bazelOut/external/vendor/*_host $bazelOut/external/vendor/@*_host*

      # Preserve vendored marker files across buildBazelPackage's marker clearing,
      # and scrub store paths (e.g. coreutils chmod) recorded in markers.
      find $bazelOut/external/vendor -maxdepth 1 -name '*.marker' -exec sh -c 'for m; do mv "$m" "$m.nixkeep"; done' _ {} +
      sed -i "s|${builtins.storeDir}/[^/]*/bin/chmod|__NIX_CHMOD__|g" $bazelOut/external/vendor/*.marker.nixkeep

      # Remove non-deterministic Python bytecode.
      find $bazelOut -name '*.pyc' -delete

      if grep -rn "${builtins.storeDir}" $bazelOut/external; then
        echo "ERROR: Found store references in $bazelOut/external" >&2
        exit 1
      fi
    '';
  };

  # 2: build and install
  buildAttrs = {
    preConfigure = ''
      mkdir -p /tmp/xclang-thinlto

      cp $bazelOut/external/MODULE.bazel.lock MODULE.bazel.lock
      find $bazelOut/external/vendor -maxdepth 1 -name '*.marker.nixkeep' -exec sh -c 'for m; do mv "$m" "''${m%.nixkeep}"; done' _ {} +
      sed -i "s|__NIX_CHMOD__|$(type -p chmod)|g" $bazelOut/external/vendor/*.marker

      echo "common --vendor_dir=\"$bazelOut/external/vendor\"" >> .bazelrc
      echo "common --repository_disable_download" >> .bazelrc
      echo "common --lockfile_mode=error" >> .bazelrc

      # Replace /usr/bin/env in vendored rules_python templates for Nix sandbox compatibility.
      find $bazelOut/external/vendor/rules_python+ -type f \( -name '*.sh' -o -name '*.bzl' \) \
        -exec sed -i "s|/usr/bin/env|$(type -p env)|g" {} +

      # Patch ELF interpreters (when present) and rpaths for vendored toolchain binaries/libraries.
      find $bazelOut/external/vendor -type f \( -executable -o -name '*.so*' \) | while read -r elf; do
        file "$elf" | grep -q ': ELF .*, dynamically linked,' || continue
        if patchelf --print-interpreter "$elf" >/dev/null 2>&1; then
          patchelf --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" "$elf" || echo "patchelf interp skipped: $elf"
        fi
        patchelf --add-rpath "${runtimeLibs}" "$elf" || echo "patchelf rpath skipped: $elf"
      done
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      if [ -f build/RelWithDebInfo/bin/clice.tar.gz ]; then
        tar -xzf build/RelWithDebInfo/bin/clice.tar.gz --strip-components=1 -C $out
      elif [ -d bazel-bin/package ]; then
        cp -r bazel-bin/package/* $out/
      elif [ -f bazel-bin/package.tar ]; then
        tar -xf bazel-bin/package.tar -C $out
      else
        install -Dm0755 build/RelWithDebInfo/bin/bin/clice "$out/bin/clice"
      fi

      runHook postInstall
    '';
  };

  strictDeps = true;
  __structuredAttrs = true;

  meta = {
    description = "A modern C++ language server supporting C++20/23 modules";
    homepage = "https://github.com/clice-project/clice";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "clice";
  };
}
