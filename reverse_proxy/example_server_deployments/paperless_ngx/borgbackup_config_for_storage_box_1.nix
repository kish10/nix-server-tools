{pkgs ? import <nixpkgs> {}}:
let
  userHome = builtins.getEnv("HOME");
in
{
  crontabSchedule = "0 0 * * *";


  borgConfigPaths = {
    env = {
      /**
        `borg.env` should have: "BORG_RSH", "BORG_REPO", optional: "BORG_ARCHIVE_PREFIX"

        Example `borg.env`:
        ```
        BORG_RSH="sshpass -f /run/secrets/borg_ssh_passphrase -P passphrase ssh -i /root/.ssh/storage_box_private_key -p <ssh port number>"
        BORG_REPO="ssh://user@storage_box_hostname:<ssh port number>/./<path to repo>"
        BORG_ARCHIVE_PREFIX="test_borg_archive"
        ```
      */
      borgConfigEnv = "${userHome}/borgbackup_config/borg.env";

      /**
        `borg_secrets_env` should have: "BORG_PASSPHRASE"

        Example `borg_secrets.env`:
        ```
        BORG_PASSPHRASE="test"
        ```
      */
      borgSecretsEnv = "${userHome}/secrets/borg_secrets.env";
    };

    ssh = {
      /** `knownHosts` should have: A record of the storage box server that want to ssh into. */
      sshKnownHosts = "${userHome}/.ssh/known_hosts";

      /** `sshServerKey` should be the ssh key for the storage box that want to ssh into. */
      sshServerKey = "${userHome}/.ssh/storage_box";

      /** `ssh_server_key_passphrase` should be the passphrase to the ssh key for the server. */
      sshServerKeyPassphrase = "${userHome}/secrets/storage_box_ssh_key_passphrase";
    };

    /** sourceData is set by the Nix file that creates the docker-compose.yaml file for paperless-ngx. */
    #sourceData = [];
  };


  additionalDockerBindPaths = [
    "${userHome}/secrets/mailpace_secrets.env:/run/secrets/mailpace_secrets"
  ];


  errorEmail =
    let
      generalUtility = import ../../../utility;
      mailpaceUtility = import generalUtility.email.mailpace {inherit pkgs;};
    in
    rec {
      enable = true;

      sendEmailSh = mailpaceUtility.scripts.sendEmailSh {
        mailpaceSecretsEnvFilePath = "/run/secrets/mailpace_secrets";
        emailSubject = "$1";
        emailTextBody = "$2";
      };

      sendErrorEmailSh =
        pkgs.writeScript "send_error_email.sh" ''
          #!/bin/sh

          BORG_REPO="$1"
          BORG_SOURCE_DIRS="$2"

          /email/send_email.sh \
            "Backup job failed" \
            "Backup job failed -- to Repo: {  $BORG_REPO  } -- on source dirs: {  $BORG_SOURCE_DIRS  }"
        '';

      dockerContextDerivation = pkgs.stdenv.mkDerivation {
        name="borgbackup_docker_context";
        src=./.;
        dontPatchShebangs = true;
        installPhase = ''
          mkdir $out

          cp ${sendEmailSh} $out/send_email.sh
          cp ${sendErrorEmailSh} $out/send_error_email.sh
        '';
      };
    };
}
