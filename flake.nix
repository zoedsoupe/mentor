{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11-small";
  };

  outputs = {nixpkgs, ...}: let
    inherit (nixpkgs) lib;
    inherit (nixpkgs.lib.systems) flakeExposed;
    forAllSystems = f: lib.genAttrs flakeExposed (system: f (import nixpkgs {inherit system;}));
  in {
    devShells = forAllSystems (pkgs: let
      inherit (pkgs) mkShell;
      inherit (pkgs.beam.interpreters) erlang_27;
      inherit (pkgs.beam) packagesWith;

      beam = packagesWith erlang_27;

      elixir_1_18 = beam.elixir.override {
        version = "1.18.1";
        minimumOTPVersion = "27";

        src = pkgs.fetchFromGitHub {
          owner = "elixir-lang";
          repo = "elixir";
          rev = "v1.18.1";
          sha256 = "sha256-zJNAoyqSj/KdJ1Cqau90QCJihjwHA+HO7nnD1Ugd768=";
        };
      };
    in {
      default = mkShell {
        name = "mentor";
        packages = [elixir_1_18 erlang_27];
      };
    });
  };
}
