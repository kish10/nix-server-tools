{pkgs ? import <nixpgs> {}}:
{
  docker = import ./docker_utilities.nix {inherit pkgs;};
}
