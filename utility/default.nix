{
  backup = {
    borgbackup = ./backup/borgbackup/create-files--for-borg.nix;
  };

  email = {
    mailpace = ./email/mailpace/mailpace_utility.nix ;
  };

  encryption = {
    age = ./encryption/age_utilities.nix;
  };

  shell = {
    shellPrompt = ./shell/shell_prompt_utility.nix;
  };
}
