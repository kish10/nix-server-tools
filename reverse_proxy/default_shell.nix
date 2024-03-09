{pkgs ? import <nixpkgs> {}}:
let
  generalUtility = import ../utility {inherit pkgs;};
  reverseProxyUtility = import ./reverse_proxy_utility {inherit pkgs;};

  buildInputsUtilityDocker = pkgs.lib.attrValues reverseProxyUtility.docker.bin;
  buildInputsUtilityEncryptionAge = pkgs.lib.attrValues generalUtility.encryption.age.bin;

  buildInputs = with pkgs;
    [] ++
    buildInputsUtilityDocker ++
    buildInputsUtilityEncryptionAge;
in
pkgs.mkShell {
  inherit buildInputs;
  shellHook = ''
    # - Change bash prompt
    source ${generalUtility.shell.shellPrompt.scripts.setShellPromptWithUserHostDirSh}
  '';
}
