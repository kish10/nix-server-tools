{pkgs ? import <nixpkgs> {}}:
let
  generalUtility = import ../utility;
  reverseProxyUtility = import ./reverse_proxy_utility;

  buildInputsUtilityDocker = pkgs.lib.attrValues (import reverseProxyUtility.shell.buildInputs.dockerUtility {inherit pkgs;}).bin;
  buildInputsUtilityEncryptionAge = pkgs.lib.attrValues (import generalUtility.encryption.age {inherit pkgs;}).bin;

  buildInputs = with pkgs;
    [] ++
    buildInputsUtilityDocker ++
    buildInputsUtilityEncryptionAge;


  shellPromptSet = import generalUtility.shell.shellPrompt {inherit pkgs;};
  shellPrompt = shellPromptSet.scripts.setShellPromptWithUserHostDirSh;
in
pkgs.mkShell {
  inherit buildInputs;
  shellHook = ''
    # - Change bash prompt
    source ${shellPrompt}
  '';
}
