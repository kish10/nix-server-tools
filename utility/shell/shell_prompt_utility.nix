/**
  Used in the `shellHook` attribute of a `pkgs.mkShell` derivation to set the shell prompt when For example `nix develop .#` is called.

  References:
  - How to fix "wrapping" issue when setting PS1 (see first answer to this answer): https://stackoverflow.com/a/342135

*/

{pkgs ? import <nixpkgs> {}}:
let
  /**
    Sets shell prompt to `[(shell) user@host:directory]$ `.

    Note:
      - The `\[\e[0;32m]\]` & `\[e\[0m\]` set the color of the shell prompt.
        - Note: The `\[` & `\]` are needed to make sure that word wrapping still works properly after the shell prompt is set.
      - The `\"` is to escape the `"` symbol in the nix string.
  */
  setShellPromptWithUserHostDirSh = pkgs.writeScript "set_shell_prompot_with_user_host_dir.sh" ''
    #!/bin/sh

    # - Change bash prompt
    export PS1="\[\e[0;32m\][(shell) \u@\H:\w]\$ \[\e[0m\]"
    '';
in
{
  scripts = {
    inherit setShellPromptWithUserHostDirSh;
  };
}
