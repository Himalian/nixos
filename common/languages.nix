# languages.nix
# packages for programming languages
{
  inputs,
  pkgs,
  pkgs-unstable,
  ...
}:
{
  environment.systemPackages =
    with pkgs;
    [
      bun
      nodejs
      # deno
      # pnpm
      nil

      pixi
      uv
      cargo
      rustc
      clippy
      rust-analyzer
      rustfmt
      # rustup
      python3
      gcc
      clang
      clang-tools

    ]
    ++ [
      pkgs-unstable.pixi
      inputs.mcpp.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
  environment.sessionVariables = {
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };
}
