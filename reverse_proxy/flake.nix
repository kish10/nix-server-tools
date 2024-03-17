{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, ... }:
    let
      # TODO: Make more dynamic, such as using `https://github.com/numtide/flake-utils`
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      applications = import ./applications;
      utility = import ./reverse_proxy_utility;
      servers = import ./applications;

      devShells.${system}.default = import ./default_shell.nix {inherit pkgs;};
    };
}
