{
  applications = import ./applications;
  servers = import ./servers;
  devShells.default = ./default_shell.nix;
}
