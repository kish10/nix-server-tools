{pkgs ? import <nixpkgs> {}, config ? {}}:
let
  userHome = builtins.getEnv("HOME");

  options = {
    crontabSchedule = "0 0 * * *";


    borgConfigPaths = {
      env = {
        /** `borg.env` should `export`: "BORG_RSH", "BORG_REPO", optional: "BORG_ARCHIVE_PREFIX" */
        borg_config_env = "${userHome}/borgbackup_config/borg.env";

        /** `borg_secrets_end` should export: "BORG_PASSPHRASE" */
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
      "${userHome}/secrets/mailpace_secrets.env:/run_secrets/mailpace_secrets"
    ];


    errorEmail = {
      enable = true;

      sendErrorEmailSh =
        let
          mailpaceUtility = import ../../email/mailpace/mailpace_utility.nix {inherit pkgs;};
          sendEmailSh = mailpaceUtility.scripts.sendEmailSh {
            mailpaceSecretsEnvFilePath = "/run/secrets/mailpace_secrets";
            emailSubject = "Backup job failed";
            emailTextBody = "$1";
          };
        in
        pkgs.writeScript "send_error_email.sh" ''
          #!/bin/sh

          BORG_REPO=$1
          BORG_SOURCE_DIRS=$2

          ${sendEmailSh} "Backup job failed -- to Repo: `$BORG_REPO` -- on source dirs: `$BORG_SOURCE_DIRS`";
        '';
    };
  };


  cfg = options // config;


  /**
    Script called to {create, prune, compact} the borgbackup.

    Configured by the `borg.env` file.
  */
  borgBackupScript =
    let
      sendErrorEmailCmd =
        if cfg.errorEmail.enable then
          "( ${cfg.errorEmail.sendErrorEmailSh} \"$BORG_REPO\" \"$BORG_SOURCE_DIRS\" )"
        else
          "";
    in
    pkgs.writeText "borgbackup_script.sh" ''
      #!/bin/bash

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
        $BORG_REPO::$BORG_ARCHIVE_PREFIX{hostname}-{now:%Y-%m-%dT%H:%M:%S.%f} \
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
    borgbackupCrontab = pkgs.writeText "borgbackup_crontab.txt"
    ''
    ${cfg.crontabSchedule} /borgbackup_script.sh 2>&1
    '';


    /**
      entry.sh file for the automatic backup Docker container.
    */
    dockerEntrySh = pkgs.writeText "entry.sh" ''
      #!/bin/sh

      if [ "$1" = "bash" ] || [ "$1" = "sh" ] || [ "$1" = "/bin/bash" ] || [ "$1" = "/bin/sh" ]; then
        # -- Run Shell
        exec "$@"
      else
        # -- Run the borgbackup script once in subshell.
        ( exec /borgbackup_script.sh )

        # -- Set up cron job for automatic backups
        supercronic /borgbackup_crontab.txt

        # -- Keep the contianer running
        sleep infinity
      fi
    '';


  /**
    Dockerfile for the automatic borgbackup image.
  */
  dockerFileForBorgBackup = pkgs.writeText "Dockerfile--for-borgbackup"
  ''
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

  COPY --chmod=700 entry.sh borgbackup_script.sh send_error_email.sh /
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
          "cp ${cfg.errorEmail.sendErrorEmailSh} $out/send_error_email.sh"
        else
          "";
    in
    pkgs.stdenv.mkDerivation {
      name="borgbackup_docker_context";
      src=./.;
      installPhase = ''
        mkdir $out

        cp ${borgbackupCrontab} $out/borgbackup_crontab.txt
        cp ${borgBackupScript} $out/borgbackup_script.sh
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
          #- ''${a.mailpace_secrets_env}:/run/secrets/mailpace_secrets:ro
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
    inherit borgBackupScript;
    inherit runComposeSh;
    inherit runTestInteractiveContainerSh;
  };

  dockerContext = dockerContextDerivation;

  dockerCompose = dockerComposeForBorgBackup;
}
