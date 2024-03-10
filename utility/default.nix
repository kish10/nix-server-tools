{pkgs ? import <nixpkgs> {}}:
{
  backup = {
    borgbackup = "";
  };

  email = {
    mailpace = import ./email/mailpace/mailpace_utilities.nix {inherit pkgs;};
  };

  encryption = {
    age = import ./encryption/age_utilities.nix {inherit pkgs;};
  };

  shell = {
    shellPrompt = import ./shell/shell_prompt_utility.nix {inherit pkgs;};
  };
}
