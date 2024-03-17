{
  pkgs ? import <nixpkgs>{},
  config ? {}
}:
let
  userHome = builtins.getEnv("HOME");

  options = {
    proxiedServiceInfo = {
      serviceName = "immich";
      domainNameList = ["immich.not_exist.com"];
      upstreamHostName = "immich";
      listeningPort = "3001";
      proxyNetwork = "caddy-proxy-internal-network";
      serviceLabels = ["reverse-proxy-component: 'proxied-service'"];
    };

    /**
      List of borgbackup configs for one or more borgbackup servers.

      Note: `borgConfigPaths.sourceData` will be set below.
    */
    borgConfigList = [];

    immichConfigPaths = {
      env = {

        /**
          Environment variables file for Immich (In Docker format).

          See `https://immich.app/docs/install/environment-variables/` for more enviroment variable options.
        */
        immichConfigEnv = "";


        /**
          JSON file with Immich configurations.

          For details see: https://immich.app/docs/install/config-file/
        */
        immichCofigJson = "";

        /**
          `immichSecretsEnv` for secrets such as:

          Example `immich_secrets.env`:
          ```
          DB_PASSWORD="<key>"
          ```
        */
        #immichSecretsEnv = ""; #"${userHome}/secrets/immich_secrets.env";


        /**
          `immichDbSecretsEnv` should have:
          - DB_PASSWORD, DB_USERNAME, DB_DATABASE_NAME
          - POSTGRES_PASSWORD, POSTGRESS_USER, POSTGRESS_DB (should be same as the "DB" counterparts.)

        */
        immichDbSecretsEnv = "${userHome}/secrets/immich_db_secrets.env";
      };
    };


    /**
      Immich enviroment variables set through Nix for convinience.
    */
    immichEnvVars = {

      immichVersion = "release";


      machineLearningHost="";
      machineLearningPort="3003";

      /**
        Timezone for Vikunja, Vikunja's default timezone is GMT.

        See "TZ Identifier" in `https://en.wikipedia.org/wiki/List_of_tz_database_time_zones` for additional timezones.

        (Users can also change the timezone once logged in.)
      */
      timezone = "GMT";

    };
  };

  cfg = options // config;


  # -- docker-compose--for-borgbackup.yaml -- To be extended in the Immich docker-compose.yaml

  serviceName = cfg.proxiedServiceInfo.serviceName;

  reverseProxyUtility = import ../../../../reverse_proxy_utility;
  createBorgbackupServices = reverseProxyUtility.createCommonServices.backup.borgbackup.createBorgbackupServices;

  borgbackupServicesConfig = import createBorgbackupServices {
    inherit pkgs;
    sourceServiceName = serviceName; borgConfigList = cfg.borgConfigList;
    borgbackupSourceData = [
      "${serviceName}__immich-upload-location:${serviceName}__immich-upload-location"
      "${serviceName}__pgdata_db_dumps:${serviceName}__pgdata_db_dumps"
    ];
    stringSepForServiceInYaml = "\n\ \ ";
  };


  /**
    Reference:
      - Immich's docker-compose.yaml: https://github.com/immich-app/immich/blob/main/docker/docker-compose.yml
        - Version from commit id: af0de1a768d54c84ba59b4158723aa8d29e1d02b
  */
  dockerComposeForImmich =
    let
      proxiedServiceLabelConfigLines =
        builtins.concatStringsSep "\n\ \ \ \ " cfg.proxiedServiceInfo.serviceLabels;

      machineLearningHost =
        if cfg.immichEnvVars.machineLearningHost == "" then
          "${cfg.proxiedServiceInfo.serviceName}-immich-machine-learning"
        else
          cfg.immichEnvVars.machineLearningHost;

      immichConfigEnvPath =
        if cfg.immichConfigPaths.env.immichConfigEnv != "" then
          "- ${cfg.immichConfigPaths.env.immichConfigEnv}"
        else
          "";

    in
    pkgs.writeText "docker-compose--for-immich.yaml" ''
      version: '3.8'

      #
      # WARNING: Make sure to use the docker-compose.yml of the current release:
      #
      # https://github.com/immich-app/immich/releases/latest/download/docker-compose.yml
      #
      # The compose file on main may not be compatible with the latest release.
      #

      name: immich

      services:
        ${cfg.proxiedServiceInfo.serviceName}:
          container_name: ${cfg.proxiedServiceInfo.serviceName}
          image: ghcr.io/immich-app/immich-server:${cfg.immichEnvVars.immichVersion}
          command: ['start.sh', 'immich']
          depends_on:
            - ${cfg.proxiedServiceInfo.serviceName}-immich-redis
            - ${cfg.proxiedServiceInfo.serviceName}-immich-database
          environment:
            DB_HOSTNAME: ${cfg.proxiedServiceInfo.serviceName}-immich-database
            MACHINE_LEARNING_HOST: ${machineLearningHost}
            MACHINE_LEARNING_PORT: ${cfg.immichEnvVars.machineLearningPort}
            REDIS_HOSTNAME: ${cfg.proxiedServiceInfo.serviceName}-immich-redis
            SERVER_PORT: ${cfg.proxiedServiceInfo.listeningPort}
            TZ: ${cfg.immichEnvVars.timezone}

            DB_PASSWORD: postgres-test
            DB_USERNAME: postgres-test
            DB_DATABASE_NAME: immich
          #env_file:
          #  ${immichConfigEnvPath}
          #  # Should have: POSTGRES_PASSWORD, POSTGRESS_USER, POSTGRESS_DB
          #  - ${cfg.immichConfigPaths.env.immichDbSecretsEnv}
          labels:
            ${proxiedServiceLabelConfigLines}
          networks:
            - "${cfg.proxiedServiceInfo.proxyNetwork}"
            - "immich-internal"
          ports:
            - "${cfg.proxiedServiceInfo.listeningPort}"
          volumes:
            - ${cfg.proxiedServiceInfo.serviceName}__immich-upload-location:/usr/src/app/upload
            - /etc/localtime:/etc/localtime:ro
          restart: always

        ${cfg.proxiedServiceInfo.serviceName}-immich-microservices:
          container_name: ${cfg.proxiedServiceInfo.serviceName}-immich-microservices
          image: ghcr.io/immich-app/immich-server:${cfg.immichEnvVars.immichVersion}
          # extends: # uncomment this section for hardware acceleration - see https://immich.app/docs/features/hardware-transcoding
          #   file: hwaccel.transcoding.yml
          #   service: cpu # set to one of [nvenc, quicksync, rkmpp, vaapi, vaapi-wsl] for accelerated transcoding
          command: ['start.sh', 'microservices']
          depends_on:
            - ${cfg.proxiedServiceInfo.serviceName}-immich-redis
            - ${cfg.proxiedServiceInfo.serviceName}-immich-database
          environment:
            DB_PASSWORD: postgres-test
            DB_USERNAME: postgres-test
            DB_DATABASE_NAME: immich

            DB_HOSTNAME: ${cfg.proxiedServiceInfo.serviceName}-immich-database
            REDIS_HOSTNAME: ${cfg.proxiedServiceInfo.serviceName}-immich-redis
          env_file:
            ${immichConfigEnvPath}
            # Should have: POSTGRES_PASSWORD, POSTGRESS_USER, POSTGRESS_DB
            - ${cfg.immichConfigPaths.env.immichDbSecretsEnv}
          networks:
            - "immich-internal"
          volumes:
            - ${cfg.proxiedServiceInfo.serviceName}__immich-upload-location:/usr/src/app/upload
            - /etc/localtime:/etc/localtime:ro
          restart: always

        ${cfg.proxiedServiceInfo.serviceName}-immich-machine-learning:
          container_name: ${cfg.proxiedServiceInfo.serviceName}-immich_machine_learning
          # For hardware acceleration, add one of -[armnn, cuda, openvino] to the image tag.
          # Example tag: ${cfg.immichEnvVars.immichVersion}-cuda
          image: ghcr.io/immich-app/immich-machine-learning:${cfg.immichEnvVars.immichVersion}
          # extends: # uncomment this section for hardware acceleration - see https://immich.app/docs/features/ml-hardware-acceleration
          #   file: hwaccel.ml.yml
          #   service: cpu # set to one of [armnn, cuda, openvino, openvino-wsl] for accelerated inference - use the `-wsl` version for WSL2 where applicable
          networks:
            - "immich-internal"
          volumes:
            - ${cfg.proxiedServiceInfo.serviceName}__model-cache:/cache
          ${if immichConfigEnvPath == "" then "" else "env_file: ${immichConfigEnvPath}"}
          restart: always

        ${cfg.proxiedServiceInfo.serviceName}-immich-redis:
          container_name: ${cfg.proxiedServiceInfo.serviceName}-immich_redis
          image: registry.hub.docker.com/library/redis:6.2-alpine@sha256:51d6c56749a4243096327e3fb964a48ed92254357108449cb6e23999c37773c5
          networks:
            - "immich-internal"
          restart: always

        ${cfg.proxiedServiceInfo.serviceName}-immich-database:
          container_name: ${cfg.proxiedServiceInfo.serviceName}-immich-database
          image: registry.hub.docker.com/tensorchord/pgvecto-rs:pg14-v0.2.0@sha256:90724186f0a3517cf6914295b5ab410db9ce23190a2d9d0b9dd6463e3fa298f0
          environment:
            POSTGRES_PASSWORD: postgres-test
            POSTGRES_USER: postgres-test
            POSTGRES_DB: immich
          #env_file:
          #  # Should have: POSTGRES_PASSWORD, POSTGRESS_USER, POSTGRESS_DB
          #  - ${cfg.immichConfigPaths.env.immichDbSecretsEnv}
          networks:
            - "immich-internal"
          volumes:
            - ${cfg.proxiedServiceInfo.serviceName}__pgdata:/var/lib/postgresql/data
          restart: always

        ${cfg.proxiedServiceInfo.serviceName}-pg-backup:
          container_name: ${cfg.proxiedServiceInfo.serviceName}-pg-backup
          image: prodrigestivill/postgres-backup-local
          env_file:
            - ${cfg.immichConfigPaths.env.immichDbSecretsEnv}
          environment:
            POSTGRES_HOST: ${cfg.proxiedServiceInfo.serviceName}-immich-database
            SCHEDULE: "@daily"
            BACKUP_DIR: /db_dumps
          networks:
            - "immich-internal"
          volumes:
            - ${cfg.proxiedServiceInfo.serviceName}__pgdata_db_dumps:/db_dumps
          depends_on:
            - ${cfg.proxiedServiceInfo.serviceName}-immich-database

        #''${borgbackupServicesConfig}

      volumes:
        ${cfg.proxiedServiceInfo.serviceName}__immich-upload-location:
        ${cfg.proxiedServiceInfo.serviceName}__pgdata:
        ${cfg.proxiedServiceInfo.serviceName}__pgdata_db_dumps:
        ${cfg.proxiedServiceInfo.serviceName}__model-cache:

      networks:
        ${cfg.proxiedServiceInfo.proxyNetwork}:
          name: ${cfg.proxiedServiceInfo.proxyNetwork}
          external: true
        immich-internal:
    '';

in
{
  derivation = pkgs.stdenv.mkDerivation {
    name = "immich";
    src = ./.;
    installPhase = ''
      mkdir $out

      cp ${dockerComposeForImmich} $out/docker-compose--for-immich.yaml
    '';
  };

  dockerComposeFile = dockerComposeForImmich;
}
