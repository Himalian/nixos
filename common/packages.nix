# Basic packages for system and daily use
{
  config,
  pkgs,
  ...
}:
let
  clice = pkgs.callPackage ../pkgs/clice.nix { };
in
{
  environment.systemPackages = with pkgs; [
    # Flakes 通过 git 命令拉取其依赖项，所以必须先安装好 git
    # you can also use nix-shell -p git during first setup
    # Necessary system packages
    # Note: language specific packages are defined at @languages.nix
    git
    vim
    wget
    gnupg
    age
    chezmoi
    nixfmt
    gnumake

    # Packages for daily use
    just
    fish
    nushell
    clice
    # create and enter a standard FHS environment
    (buildFHSEnv {
      name = "fhs";
      targetPkgs =
        pkgs: with pkgs; [
          bash
          fish
          coreutils
          gnused
          gnugrep
          gawk
          findutils
          diffutils
          git
          curl
          wget
          unzip
          zip
          python3
          pkg-config
          gnumake
          cmake
          ninja
          gcc
          binutils
          glibc.dev
        ];
      multiPkgs =
        pkgs: with pkgs; [
          gcc.cc.lib
          zlib
          openssl
          stdenv.cc.cc.lib
          zlib
          openssl
          ncurses
          libxml2
        ];
      runScript = "fish";
    })

    # lix # nix cli with better experience
  ];
  programs.nix-ld = {
    enable = true;
    libraries = [
      config.hardware.graphics.package
      ## Put here any library that is required when running a package
      ## ...
      ## Uncomment if you want to use the libraries provided by default in the steam distribution
      ## but this is quite far from being exhaustive
      ## https://github.com/NixOS/nixpkgs/issues/354513
      # (pkgs.runCommand "steamrun-lib" {} "mkdir $out; ln -s ${pkgs.steam-run.fhsenv}/usr/lib64 $out/lib")
      pkgs.glibc
      pkgs.nodejs
    ];
  };
  nixpkgs.config.allowUnfree = true;

}
