{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
  };

  outputs = { self, nixpkgs, ... }: {
    utilities = import ./. {inherit pkgs};
  };
}
