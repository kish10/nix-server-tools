/**
  Used to create a `cloud-config.yaml` to initialize a server on VPS provider.

  References:
    - [Clound-init documentation](https://cloudinit.readthedocs.io/en/latest/index.html)
*/
{pkgs ? import <nixpkgs> {}, config ? {}}:
let
  options = rec {
    changePasswordAtFirstLogin = true;
    hostname = "host";
    users = [
      {
        name = "user";
        groups = [];
        # Create a hashedPasswd with `mkpasswd --method=SHA-512 --rounds=500000`
        hashedPasswd = "$6$rounds=500000$LUuqvo4/xJdT.PKy$4Z73yHvvOcg1Klkl4XC9RuOntxhBjMGg3OOYOrt4Yy9z9HzPjtwPQdyOUHurITu9e72nIcexrxhBdUaEa0wKV1";
        lockPasswd = true;
        shell = "/bin/bash";
        sshAuthorizedKeys = [];
        sudoRule = "ALL=(ALL) PASSWD:ALL";
      }
    ];
    initialSetupScripts = [
      {
        sourceFile = ../scripts/install_age.sh;
        destination = "/initial_setup/install_age.sh";
        owner = "root:root";
        runType = "manual";
      }
      {
        sourceFile = ../scripts/install_convenience_programs.sh;
        destination = "/initial_setup/install_convenience_programs.sh";
        owner = "root:root";
        runType = "manual";
      }
      {
        sourceFile = ../scripts/install_docker.sh;
        destination = "/initial_setup/install_docker.sh";
        owner = "root:root";
        runType = "manual";
      }
      {
        sourceFile = ../scripts/install_nix.sh;
        destination = "/initial_setup/install_nix.sh";
        owner = "root:root";
        runType = "manual";
      }
      {
        sourceFile = ../scripts/secure_image.sh;
        destination = "/initial_setup/secure_image.sh";
        owner = "root:root";
        runType = "runcmd";
      }
    ];
    runcmd = [];
    timezone = "Greenwich";
  };

  cfg = options // config;


  # -- Utility functions

  /**
    Removes blank lines in a multiline string.

    Ex: The string "a\n \nb", would be converted to "a\nb".
  */
  utilityRemoveBlankLines = multilineString:
    let
      splittedString = pkgs.lib.strings.splitString "\n" multilineString;
      splittedStringFiltered = builtins.filter (s: builtins.match "[[:space:]]*" s == null) splittedString;
    in
    builtins.concatStringsSep "\n" splittedStringFiltered;


  /**
    Indents a multiline string to the specified indent level.

    # Arguments

    indentSpaces
    : An integer to specify amount to spaces characters to use to indent the lines in the string by.

    multilineString
    : A string.
  */
  utilityIndentMultilineString = indentSpaces: multilineString:
    let
      splittedString = pkgs.lib.strings.splitString "\n" multilineString;
      indentString = builtins.concatStringsSep "" (pkgs.lib.lists.replicate indentSpaces " ");
      splittedStringIndented = builtins.map (s: "${indentString}${s}") splittedString;
    in
    builtins.concatStringsSep "\n" splittedStringIndented;


  # -- Functions to create parts of the config


  createUserConfig = userInfo:
    let
      groupsConfig =
        if userInfo.groups == [] then
          ""
        else
          "groups: ${builtins.concatStringsSep " " userInfo.groups}";


      createSSHAuthorizedKeysConfig = sshKeys:
        let
          sshKeyEntries = map (sk: "- ${sk}") sshKeys;
        in
        if sshKeys == [] then
          ""
        else
          ''
            ssh_authorized_keys:
              ${builtins.concatStringsSep "\n\ \ " sshKeyEntries}
          '';
    in
    utilityRemoveBlankLines ''
      - name: ${userInfo.name}
        ${groupsConfig}
        lock_passwd: ${if userInfo.lockPasswd then "true" else "false"}
        shell: ${userInfo.shell}
      ${utilityIndentMultilineString 2 (createSSHAuthorizedKeysConfig userInfo.sshAuthorizedKeys)}
        sudo: ${userInfo.sudoRule}
    '';


  createUsersPasswdConfig = users:
    let
      createUserPasswdEntry = userInfo: ''
        - name: ${userInfo.name}
          password: ${userInfo.hashedPasswd}
      '';

      userPasswdEntries = map createUserPasswdEntry users;
    in
    ''
      chpasswd:
        expire: ${if cfg.changePasswordAtFirstLogin then "true" else "false"}
        users:
      ${utilityIndentMultilineString 4 (builtins.concatStringsSep "\n" userPasswdEntries)}
    '';
    # ${builtins.concatStringsSep "\n\ " userPasswdEntries}

  # -- Writeout initial setup scripts

  writeSetupScriptsConfig = initialSetupScripts:
    let
      createWriteEntry = scriptInfo:
        ''
          - content: |
          ${utilityIndentMultilineString 4 (builtins.readFile scriptInfo.sourceFile)}
            owner: ${scriptInfo.owner}
            path: ${scriptInfo.destination}
            permissions: ${if (pkgs.lib.attrsets.hasAttrByPath ["perimissoins"] scriptInfo) then scriptInfo.permissions else "700"}
        '';

      writeEntries = builtins.concatStringsSep "\n" (builtins.map createWriteEntry initialSetupScripts);
    in
    if initialSetupScripts == [] then
      ""
    else
      ''
        write_files:
        ${writeEntries}
      '';


  createRuncmdConfig =
    let
      cfgCommands = cfg.runcmd;


      # -- Create runcmds for initialScripts to be ran

      scriptInfoToRun = (
        builtins.filter (scriptInfo: scriptInfo.runType == "runcmd") cfg.initialSetupScripts
      );
      scriptsToRun = map (scriptInfo: scriptInfo.destination) scriptInfoToRun;

      commands = cfgCommands ++ scriptsToRun;


      # -- Create runcmd entries

      commandEntries = map (cmd: "- [\"${cmd}\"]") commands;

    in
    if commandEntries == [] then
      ""
    else
      ''
        #runcmd:
        #  ${builtins.concatStringsSep "\n\ \ " commandEntries}
        #  - reboot
      '';

  # -- The cloud-init.yaml file.

  cloudInit =
    let
      userConfigEntries = map createUserConfig cfg.users;
      usersConfig = builtins.concatStringsSep "\n\ \ " userConfigEntries;
    in
    pkgs.writeText "cloud-init.yaml" ''
      #cloud-config

      # Version: cloud-init 24.1.6

      hostname: ${cfg.hostname}
      timezone: ${cfg.timezone}
      users:
      ${utilityIndentMultilineString 2 usersConfig}

      ${createUsersPasswdConfig cfg.users}

      ${writeSetupScriptsConfig cfg.initialSetupScripts}

      packages:
        - fail2ban
        - ufw
      package_update: true
      package_upgrade: true

      ${createRuncmdConfig}
    '';
in
pkgs.stdenv.mkDerivation {
  name = "cloud-init.yaml";
  src = ./.;
  installPhase = ''
    mkdir $out
    cp ${cloudInit} $out/;
  '';
}

