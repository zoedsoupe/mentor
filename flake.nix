{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05-small";
    elixir-overlay.url = "github:zoedsoupe/elixir-overlay";
  };

  outputs = {
    nixpkgs,
    elixir-overlay,
    ...
  }: let
    inherit (nixpkgs) lib;
    inherit (nixpkgs.lib.systems) flakeExposed;
    forAllSystems = f:
      lib.genAttrs flakeExposed (system:
        f (import nixpkgs {
          inherit system;
          overlays = [elixir-overlay.overlays.default];
        }));
  in {
    devShells = forAllSystems (pkgs: let
      inherit (pkgs) mkShell;
      inherit (pkgs.beam.interpreters) erlang_28;
    in {
      default = mkShell {
        name = "mentor";
        packages = with pkgs; [(elixir-with-otp erlang_28)."1.18.4" erlang_28];
      };
    });
  };
}
