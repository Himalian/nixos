# languages.nix
# packages for programming languages
{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
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

  ];
  environment.sessionVariables = {
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };
}
