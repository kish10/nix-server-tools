{
  description = ''
    `nix-server-tools` to conveniently deploy applications to a server.
  '';

  inputs = {
    nixpkgs.url = "github:Nixos/nixpkgs";
  };

  outputs = {self, nixpkgs}: import ./.;
}
