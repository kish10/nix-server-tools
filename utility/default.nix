{pkgs ? import <nixpkgs> {}}:
{
  encryption = {
    age = import ./encryption/age_utilities.nix {inherit pkgs;};
  };

  shell = {
    shellPrompt = import ./shell/shell_prompt_utility.nix {inherit pkgs;};
  };
}
