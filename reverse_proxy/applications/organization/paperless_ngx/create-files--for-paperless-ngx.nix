/**
  # Initial setup.

  ## Making the admin account.

  Once the docker container is running (and can access the `paperless-ngx` instance through the internet), need to manually create an initial admin account:
  - `exec` into the running container with `docker exec -it <container id> /bin/sh`
  - Within the container, run `python3 manage.py createsuperuser`

  Reference:
  - [Paperless-ngx docs - Setup - From GHCR / Docker-Hub](https://docs.paperless-ngx.com/setup/#docker_hub)
*/
{
  pkgs ? import <nixpkgs>{},
  config ? {}
}:
let
  userHome = builtins.getEnv("HOME");

  options = {

    proxiedServiceInfo = {
      serviceName = "paperless-ngx";
      domainNameList = ["paperlessngx.not_exist.com"];
      upstreamHostName = "paperless-ngx";
      listeningPort = "8000";
      proxyNetwork = "caddy-proxy-internal-network";
      serviceLabels = ["reverse-proxy-component: 'proxied-service'"];
    };


    /**
      List of borgbackup configs for one or more borgbackup servers.

      Note: `borgConfigPaths.sourceData` will be set below.
    */
    borgConfigList = [];


    paperlessConfigPaths = {
      env = {
        /**
          Path to env file with additional paperless-ngx enviroment variables

          Format of the file should be the format required for Docker ".env" files.
        */
        paperlessConfigEnv = "";

        /**
          `paperlessSecretsEnv` should set: "PAPERLESS_SECRET_KEY"
          `paperlessSecretsEnv` can optionally set: "PAPERLESS_ADMIN_MAIL", "PAPERLESS_ADMIN_PASSWORD"

          Example `paperless-ngx_secrets.env`:
          ```
          PAPERLESS_SECRET_KEY=<key>
          ```
        */
        paperlessSecretsEnv = "${userHome}/secrets/paperless-ngx_secrets.env";
      };
    };
  };

  cfg = options // config;


  # -- docker-compose--for-borgbackup.yaml -- To be extended in the paperless-ngx docker-compose.yaml

  borgbackupServicesConfig =
    let

      createComposeFilesForBorgbackup = borgConfig:
        let
          borgbackupSourceData = [
            "${cfg.proxiedServiceInfo.serviceName}__paperless_data:${cfg.proxiedServiceInfo.serviceName}__paperless_data"
            "${cfg.proxiedServiceInfo.serviceName}__paperless_media:${cfg.proxiedServiceInfo.serviceName}__paperless_media"
            "${cfg.proxiedServiceInfo.serviceName}__paperless_export:${cfg.proxiedServiceInfo.serviceName}__paperless_export"
            "${cfg.proxiedServiceInfo.serviceName}__paperless_consume:${cfg.proxiedServiceInfo.serviceName}__paperless_consume"
          ];

          borgConfigPaths = borgConfig.borgConfigPaths // {sourceData = borgbackupSourceData; };
          borgConfigFinal = borgConfig // { inherit borgConfigPaths; };

          generalUtility = import ../../../../utility;
          borgbackupFiles = import generalUtility.backup.borgbackup {inherit pkgs; config = borgConfigFinal;};
        in
        borgbackupFiles.dockerComposeFile;

      indexList = builtins.genList (ii: builtins.toString(ii)) (builtins.length cfg.borgConfigList);
      dockerComposeFileForBorgbackupList = map createComposeFilesForBorgbackup cfg.borgConfigList;

      zippedIndexAndFileList = pkgs.lib.lists.zipListsWith (ii: f: {index = ii; dockerComposeFile = f;}) indexList dockerComposeFileForBorgbackupList;

      makeBorgService = {index, dockerComposeFile}:
        ''
          ${cfg.proxiedServiceInfo.serviceName}-borgbackup-${index}:
              extends:
                file: ${dockerComposeFile}
                service: borgbackup
              depends_on:
                - ${cfg.proxiedServiceInfo.serviceName}
        '';

      borgServiceList = map makeBorgService zippedIndexAndFileList;
    in
    builtins.concatStringsSep "\n\ \ " borgServiceList;


  # -- docker-compose--for-paperless-ngx.yaml

  proxiedServiceLabelConfigLines =
    builtins.concatStringsSep "\n\ \ \ \ " cfg.proxiedServiceInfo.serviceLabels;


  paperlessUrlCsrfEnv =
    let
      withHttps = (map (d: "https://${d}") cfg.proxiedServiceInfo.domainNameList);
    in
    builtins.concatStringsSep "," withHttps;

  paperlessUrlAllowedEnv =
    builtins.concatStringsSep "," cfg.proxiedServiceInfo.domainNameList;


  paperlessConfigEnvPath =
    if cfg.paperlessConfigPaths.env.paperlessConfigEnv != "" then
      "- ${cfg.paperlessConfigPaths.env.paperlessConfigEnv}"
    else
      "";


  dockerComposeFile = pkgs.writeText "docker-compose--for-paperless-ngx.yaml" ''
    # Copied from: https://github.com/paperless-ngx/paperless-ngx/blob/main/docker/compose/docker-compose.sqlite-tika.yml

    version: "3.4"

    services:
      ${cfg.proxiedServiceInfo.serviceName}-broker:
        image: docker.io/library/redis:7
        networks:
          - ${cfg.proxiedServiceInfo.serviceName}__paperless_internal
        ports:
          - "6379"
        restart: unless-stopped
        volumes:
          - ${cfg.proxiedServiceInfo.serviceName}__paperless_redisdata:/data

      ${cfg.proxiedServiceInfo.serviceName}:
        image: ghcr.io/paperless-ngx/paperless-ngx:latest
        restart: unless-stopped
        depends_on:
          - ${cfg.proxiedServiceInfo.serviceName}-broker
          - ${cfg.proxiedServiceInfo.serviceName}-gotenberg
          - ${cfg.proxiedServiceInfo.serviceName}-tika
        networks:
          - ${cfg.proxiedServiceInfo.serviceName}__paperless_internal
          - ${cfg.proxiedServiceInfo.proxyNetwork}
        ports:
          - "${cfg.proxiedServiceInfo.listeningPort}"
        volumes:
          - ${cfg.proxiedServiceInfo.serviceName}__paperless_data:/usr/src/paperless/data
          - ${cfg.proxiedServiceInfo.serviceName}__paperless_media:/usr/src/paperless/media
          - ${cfg.proxiedServiceInfo.serviceName}__paperless_export:/usr/src/paperless/export
          - ${cfg.proxiedServiceInfo.serviceName}__paperless_consume:/usr/src/paperless/consume

        environment:
          PAPERLESS_CSRF_TRUSTED_ORIGINS: ${paperlessUrlCsrfEnv}
          PAPERLESS_ALLOWED_HOSTS: ${paperlessUrlAllowedEnv}
          PAPERLESS_PORT: ${cfg.proxiedServiceInfo.listeningPort}
          PAPERLESS_USE_X_FORWARD_HOST: True
          PAPERLESS_USE_X_FORWARD_PORT: True

          PAPERLESS_FILENAME_FORMAT: "{created_year}/{created_month}/{owner_username}/{correspondent}/{doc_pk}__{title}"

          PAPERLESS_REDIS: redis://${cfg.proxiedServiceInfo.serviceName}-broker:6379
          PAPERLESS_TIKA_ENABLED: 1
          PAPERLESS_TIKA_GOTENBERG_ENDPOINT: http://${cfg.proxiedServiceInfo.serviceName}-gotenberg:3000
          PAPERLESS_TIKA_ENDPOINT: http://${cfg.proxiedServiceInfo.serviceName}-tika:9998
        env_file:
          - ${cfg.paperlessConfigPaths.env.paperlessSecretsEnv}
          ${paperlessConfigEnvPath}
        labels:
          ${proxiedServiceLabelConfigLines}


      ${cfg.proxiedServiceInfo.serviceName}-gotenberg:
        image: docker.io/gotenberg/gotenberg:7.10
        restart: unless-stopped

        # The gotenberg chromium route is used to convert .eml files. We do not
        # want to allow external content like tracking pixels or even javascript.
        command:
          - "gotenberg"
          - "--chromium-disable-javascript=true"
          - "--chromium-allow-list=file:///tmp/.*"
        networks:
          - ${cfg.proxiedServiceInfo.serviceName}__paperless_internal
        ports:
          - "3000"

      ${cfg.proxiedServiceInfo.serviceName}-tika:
        image: ghcr.io/paperless-ngx/tika:latest
        networks:
          - ${cfg.proxiedServiceInfo.serviceName}__paperless_internal
        ports:
          - "9998"
        restart: unless-stopped


      # -- Configure Borg Backup

      ${borgbackupServicesConfig}


    volumes:
      ${cfg.proxiedServiceInfo.serviceName}__paperless_data:
      ${cfg.proxiedServiceInfo.serviceName}__paperless_media:
      ${cfg.proxiedServiceInfo.serviceName}__paperless_export:
      ${cfg.proxiedServiceInfo.serviceName}__paperless_consume:
      ${cfg.proxiedServiceInfo.serviceName}__paperless_redisdata:
      ${cfg.proxiedServiceInfo.serviceName}__paperless_borg_cache:

    networks:
      ${cfg.proxiedServiceInfo.serviceName}__paperless_internal:
        driver: bridge
      ${cfg.proxiedServiceInfo.proxyNetwork}:
        name: ${cfg.proxiedServiceInfo.proxyNetwork}
        external: true

  '';
in
{
  derivation = pkgs.stdenv.mkDerivation {
    name = "paperless_nxg";
    src = ./.;
    installPhase = ''
      mkdir $out

      cp ${dockerComposeFile} $out/docker-compose--for-paperless-ngx.yaml
    '';
  };

  dockerComposeFile = dockerComposeFile;
}
