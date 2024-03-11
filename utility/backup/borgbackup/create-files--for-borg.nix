/**
  Creates files to work with `borgbackup`.

  Note:
  - To use need to do setup that is outside of these files:
    - `borgbackup` setup:
      - Set up a `borgbackup` "storage box" server where the files would be stored & these scripts will ssh into.
      - Initialize the `borgbackup` repository with `borg init`.
        - This command needs to have `borg` installed on the "storage box" server.
          - So if can't install `borg` on the storage server, mount the server locally with `sshfs` & use the local `borg` installation to install `borg`.
            - References: [Borgbackup docs - Quickstart - Remote repositories](https://borgbackup.readthedocs.io/en/stable/quickstart.html#remote-repositories)
      - Create config & secret files, see below.

  For more details on `borgbackup` see: [Borg Documentation](https://borgbackup.readthedocs.io/en/stable/index.html)
*/
{pkgs ? import <nixpkgs> {}, config ? {}}:
let
  userHome = builtins.getEnv("HOME");

  options = {
    crontabSchedule = "0 0 * * *";


    borgConfigPaths = {
      env = {
        /**
          `borg.env` should `export`: "BORG_RSH", "BORG_REPO", optional: "BORG_ARCHIVE_PREFIX"

          Example `borg.env`:
          ```
          export BORG_RSH="sshpass -f /run/secrets/borg_ssh_passphrase -P passphrase ssh -i /root/.ssh/storage_box_private_key -p <ssh port number>"
          export BORG_REPO="ssh://user@storage_box_hostname:<ssh port number>/./<path to repo>"
          export BORG_ARCHIVE_PREFIX="test_borg_archive"
          ```
        */
        borg_config_env = "${userHome}/borgbackup_config/borg.env";

        /**
          `borg_secrets_env` should export: "BORG_PASSPHRASE"

          Example `borg_secrets.env`:
          ```
          export BORG_PASSPHRASE="test"
          ```
        */
        borg_secrets_env = "${userHome}/secrets/borg_secrets.env";
      };

      ssh = {
        /** `known_hosts` should have: A record of the storage box server that want to ssh into. */
        ssh_known_hosts = "${userHome}/.ssh/known_hosts";

        /** `ssh_server_key` should be the ssh key for the storage box that want to ssh into. */
        ssh_server_key = "${userHome}/.ssh/storage_box";

        /** `ssh_server_key_passphrase` should be the passphrase to the ssh key for the server. */
        ssh_server_key_passphrase = "${userHome}/secrets/storage_box_ssh_key_passphrase";
      };

      /**
        `sourceData` is a list of paths to the data that want to backup (Can be a local file or the name of a docker volume).

        The format of each entry should be "external_path:internal_path" where the "internal_path" represents the folder structure within the borg backup repository folder.
      */
      sourceData = [
        "${userHome}/test_data/:test_data/"
      ];
    };


    additionalDockerBindPaths = [
      "${userHome}/secrets/mailpace_secrets.env:/run/secrets/mailpace_secrets"
    ];


    errorEmail =
      let
        mailpaceUtility = import ../../email/mailpace/mailpace_utility.nix {inherit pkgs;};
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
  };


  cfg = options // config;


  /**
    Utility script to test whether backups were created.
  */
  borgListBackupsSh = pkgs.writeScript "borg_list_backups.sh" ''
    #!/bin/sh


    # Note:
    # - Should have: "BORG_RSH", "BORG_REPO"
    # - Optional variable: "BORG_ARCHIVE_PREFIX"
    source ''${BORG_ENV_FILE_PATH-/borg.env}

    # Note:
    # - Should have: "BORG_PASSPHRASE"
    source ''${BORG_ENV_SECRETS_FILE_PATH-/run/secrets/borg_secrets}


    borg list $BORG_REPO --pattern "+ $BORG_ARCHIVE_PREFIX--"
  '';


  /**
    Script called to {create, prune, compact} the borgbackup.

    Configured by the `borg.env` file.
  */
  borgBackupPruneCompactSh =
    let
      sendErrorEmailCmd =
        if cfg.errorEmail.enable then
          "( exec /email/send_error_email.sh \"$BORG_REPO\" \"$BORG_SOURCE_DIRS\" )"
        else
          "";
    in
    pkgs.writeScript "borg_backup_prune_compact.sh" ''
      #!/bin/sh

      # Note:
      # - Should have: "BORG_RSH", "BORG_REPO"
      # - Optional variable: "BORG_ARCHIVE_PREFIX"
      source ''${BORG_ENV_FILE_PATH-/borg.env}

      # Note:
      # - Should have: "BORG_PASSPHRASE"
      source ''${BORG_ENV_SECRETS_FILE_PATH-/run/secrets/borg_secrets}

      # some helpers and error handling:
      info() { printf "\n%s %s\n\n" "$( date )" "$*" >&2; }
      trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

      echo "----"
      info "Starting backup"

      borg create                                         \
        --verbose                                         \
        --filter AME                                      \
        --list                                            \
        --stats                                           \
        --show-rc                                         \
        --compression lz4                                 \
        --exclude-caches                                  \
        --exclude 'home/*/.cache/*'                       \
        --exclude 'var/tmp/*'                             \
                                                          \
        $BORG_REPO::$BORG_ARCHIVE_PREFIX--{hostname}--{now:%Y-%m-%dT%H:%M:%S.%f} \
        $BORG_SOURCE_DIRS

      backup_exit=$?


      echo "----"
      info "Pruning repository"

      # Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
      # archives of THIS machine. The '{hostname}-*' matching is very important to
      # limit prune's operation to this machine's archives and not apply to
      # other machines' archives also:

      borg prune                          \
          --list                          \
          --glob-archives '{hostname}-*'  \
          --show-rc                       \
          --keep-daily    7               \
          --keep-weekly   4               \
          --keep-monthly  6               \
          $BORG_REPO

      prune_exit=$?


      echo "----"
      info "Compacting repository"

      # actually free repo disk space by compacting segments

      borg compact $BORG_REPO

      compact_exit=$?


      # use highest exit code as global exit code
      global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
      global_exit=$(( compact_exit > global_exit ? compact_exit : global_exit ))

      if [ ''${global_exit} -eq 0 ]; then
          info "Backup, Prune, and Compact finished successfully"
      elif [ ''${global_exit} -eq 1 ]; then
          info "Backup, Prune, and/or Compact finished with warnings"
      else
          info "Backup, Prune, and/or Compact finished with errors"
          ${sendErrorEmailCmd}
      fi

      exit ''${global_exit}
    '';


    /**
      Crontab to automatically call borgbackup at scheduled times.
    */
    borgbackupCrontab = pkgs.writeText "borgbackup_crontab.txt" ''
      ${cfg.crontabSchedule} /borg_backup_prune_compact.sh 2>&1
    '';


    /**
      entry.sh file for the automatic backup Docker container.
    */
    dockerEntrySh = pkgs.writeScript "entry.sh" ''
      #!/bin/sh

      if [ "$1" = "bash" ] || [ "$1" = "sh" ] || [ "$1" = "/bin/bash" ] || [ "$1" = "/bin/sh" ]; then
        # -- Run Shell
        exec "$@"
      else
        # -- Run the borgbackup script once in subshell.
        ( exec /borg_backup_prune_compact.sh )

        # -- Set up cron job for automatic backups
        supercronic /borgbackup_crontab.txt

        # -- Keep the contianer running
        sleep infinity
      fi
    '';


  /**
    Dockerfile for the automatic borgbackup image.
  */
  dockerFileForBorgBackup = pkgs.writeText "Dockerfile--for-borgbackup" ''
    ARG BASE_IMAGE_VERSION=latest
    FROM alpine:$BASE_IMAGE_VERSION

    # -- Install common dependencies

    RUN apk --no-cache add \
      bash \
      borgbackup \
      curl \
      openssh sshpass


    # -- Install Supercronic

    ENV SUPERCRONIC_VERSION="v0.2.28"
    ENV SYSTEM="linux-386"

    # Latest releases available at https://github.com/aptible/supercronic/releases
    ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/$SUPERCRONIC_VERSION/supercronic-$SYSTEM \
        SUPERCRONIC=supercronic-$SYSTEM \
        SUPERCRONIC_SHA1SUM=6a37b4365698a0f83dc52ebcbad66a4ed1576369

    RUN curl -fsSLO "$SUPERCRONIC_URL" \
     && echo "''${SUPERCRONIC_SHA1SUM}  ''${SUPERCRONIC}" | sha1sum -c - \
     && chmod +x "$SUPERCRONIC" \
     && mv "$SUPERCRONIC" "/usr/local/bin/''${SUPERCRONIC}" \
     && ln -s "/usr/local/bin/''${SUPERCRONIC}" /usr/local/bin/supercronic


    # -- Copy runtime scripts

    COPY --chmod=700 \
      entry.sh \
      borg_backup_prune_compact.sh \
      borg_list_backups.sh \
      /

    RUN mkdir /email/
    copy --chmod=700 email/. /email/

    COPY borgbackup_crontab.txt /


    ENTRYPOINT ["/entry.sh"]
  '';


  /**
    Nix derivation to hold all the files needed by Dockerfile in one place in the Nix Store.
  */
  dockerContextDerivation =
    let
      cpSendErrorEmailSh =
        if cfg.errorEmail.enable then
          ''
          # -- Copy files for sending emails.

          mkdir $out/email/

          cp -r ${cfg.errorEmail.dockerContextDerivation}/. $out/email/.
          ''
        else
          "";
    in
    pkgs.stdenv.mkDerivation {
      name="borgbackup_docker_context";
      src=./.;
      dontPatchShebangs = true;
      installPhase = ''
        mkdir $out

        cp ${borgbackupCrontab} $out/borgbackup_crontab.txt
        cp ${borgBackupPruneCompactSh} $out/borg_backup_prune_compact.sh
        cp ${borgListBackupsSh} $out/borg_list_backups.sh
        cp ${dockerEntrySh} $out/entry.sh
        cp ${dockerFileForBorgBackup} $out/Dockerfile--for-borgbackup

        ${cpSendErrorEmailSh}
      '';
  };


  /**
    Utility function to make directories/files inside the docker container that will be backuped up.
  */
  makeInDockerSourcePaths = sourceData:
    let
      internalPaths = pkgs.lib.lists.flatten (map (ei_path: pkgs.lib.lists.last (builtins.split ":" ei_path)) sourceData);

      inDockerSourcePaths = map (p: "/backup_source_data/${p}") internalPaths;
    in
      builtins.concatStringsSep " " inDockerSourcePaths;


  /**
    Make lines for the volume section of the borgbackup service in `docker-compose.yaml`.

    # Type

    makeSourceDataConfigLines :: [string] -> string
  */
  makeSourceDataConfigLines = {sourceData, linePrefix ? "-", linePostfix ? ""}:
    let

      /**
        Make a single config line.
      */
      makeSourceDataConfigLine = external_internal_paths:
        let
          eip_splitted = pkgs.lib.lists.flatten (builtins.split ":" external_internal_paths);

          combinedPaths = builtins.concatStringsSep ":/backup_source_data/" eip_splitted;
        in
          "${linePrefix} ${combinedPaths}:ro ${linePostfix}";


      configLinesList = map makeSourceDataConfigLine sourceData;
    in
    builtins.concatStringsSep "\n\ \ \ \ \ \ " configLinesList;


  makeAdditionalDockerBindPathsConfigLines = {additionalDockerBindPaths, linePrefix ? "-", linePostfix ? ""}:
    let
      configLinesList = map (p: "${linePrefix} ${p} ${linePostfix}") additionalDockerBindPaths;
    in
    builtins.concatStringsSep "\n\ \ \ \ \ \ " configLinesList;


  /**
    docker-compose.yaml file for the automatic borgbackup.
  */
  dockerComposeForBorgBackup = pkgs.writeText "dockercompose--for-borgbackup.yaml" ''
    services:
      borgbackup:
        build:
          context: ${dockerContextDerivation}
          dockerfile: ${dockerContextDerivation}/Dockerfile--for-borgbackup
        environment:
          BORG_SOURCE_DIRS: ${makeInDockerSourcePaths cfg.borgConfigPaths.sourceData}
        volumes:
          - ${cfg.borgConfigPaths.env.borg_config_env}:/borg.env:ro
          - ${cfg.borgConfigPaths.env.borg_secrets_env}:/run/secrets/borg_secrets:ro
          - ${cfg.borgConfigPaths.ssh.ssh_known_hosts}:/root/.ssh/known_hosts:ro
          - ${cfg.borgConfigPaths.ssh.ssh_server_key}:/root/.ssh/storage_box_private_key:ro
          - ${cfg.borgConfigPaths.ssh.ssh_server_key_passphrase}:/run/secrets/borg_ssh_passphrase:ro
          ${makeSourceDataConfigLines {sourceData = cfg.borgConfigPaths.sourceData;}}
          ${makeAdditionalDockerBindPathsConfigLines {additionalDockerBindPaths = cfg.additionalDockerBindPaths;}}
        restart: unless-stopped
  '';


  /**
    Script to run docker compose.
  */
  runComposeSh = pkgs.writeScript "run-docker-compose.sh" ''
    #!/bin/sh

    docker compose -f ${dockerComposeForBorgBackup} up --build
  '';


  /**
    Script to run an interactive container for testing.

    To test:
    - Run `nix-build <path to this file> --attr scripts
    - Run `./result-4` Assuming that `result-4` is the `nix-build` output corresponding to this script.
    - In the docker container:
      - Run `./borg_backup_prune_compact.sh` to manually run a { "borg create" (backup), "borg prune", "borg compact"} commands.
      - Run `./borg_list_backups.sh` to manually check that the backup command was ran succesfully (there should be an entry for the backup that was just manually ran.
  */
  runTestInteractiveContainerSh = pkgs.writeScript "run-test-interactive-docker-container.sh" ''
    #!/bin/sh

    docker build \
      -f ${dockerContextDerivation}/Dockerfile--for-borgbackup \
      ${dockerContextDerivation} \
      -t test_borgbackup


    docker run \
      -v ${cfg.borgConfigPaths.env.borg_config_env}:/borg.env:ro \
      -v ${cfg.borgConfigPaths.env.borg_secrets_env}:/run/secrets/borg_secrets:ro \
      -v ${cfg.borgConfigPaths.ssh.ssh_known_hosts}:/root/.ssh/known_hosts:ro \
      -v ${cfg.borgConfigPaths.ssh.ssh_server_key}:/root/.ssh/storage_box_private_key:ro \
      -v ${cfg.borgConfigPaths.ssh.ssh_server_key_passphrase}:/run/secrets/borg_ssh_passphrase:ro \
      ${makeSourceDataConfigLines {sourceData = cfg.borgConfigPaths.sourceData; linePrefix = "-v"; linePostfix = "\\";}}
      ${makeAdditionalDockerBindPathsConfigLines {additionalDockerBindPaths = cfg.additionalDockerBindPaths; linePrefix = "-v"; linePostfix = "\\";}}
      -e BORG_SOURCE_DIRS="${makeInDockerSourcePaths cfg.borgConfigPaths.sourceData}" \
      -it test_borgbackup bash
  '';

in
{
  scripts = {
    inherit borgBackupPruneCompactSh;
    inherit borgListBackupsSh;
    inherit runComposeSh;
    inherit runTestInteractiveContainerSh;
  };

  dockerContext = dockerContextDerivation;

  dockerComposeFile = dockerComposeForBorgBackup;
}
