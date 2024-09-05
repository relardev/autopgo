{
  description = "Development environment";

  inputs = {
    nixpkgs = { url = "github:NixOS/nixpkgs/nixpkgs-unstable"; };
    flake-utils = { url = "github:numtide/flake-utils"; };
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        inherit (nixpkgs.lib) optional;
        pkgs = import nixpkgs { inherit system; };
        elixir = pkgs.beam.packages.erlang_26.elixir_1_17;
        elixir-ls = pkgs.elixir-ls;
        locales = pkgs.glibcLocales;
      in
      {
        devShell = pkgs.mkShell
        {
          buildInputs = [
            elixir
            locales
            elixir-ls
          ];
        };
      }
    );
}
