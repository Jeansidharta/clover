{
  inputs = {
    utils.url = "github:numtide/flake-utils";
    zig.url = "github:mitchellh/zig-overlay";
  };
  outputs =
    {
      self,
      nixpkgs,
      utils,
      zig,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShell = pkgs.mkShell {
          buildInputs = [
            zig.outputs.packages.${system}.master
            pkgs.xorg.libX11.dev
            pkgs.xorg.libxcb.dev
            pkgs.glibc.dev
            pkgs.pkg-config
          ];
        };
      }
    );
}
