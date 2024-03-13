{
  pkgs ? import <nixpkgs>{},
  config ? {}
}:
let
  userHome = builtins.getEnv("HOME");

  options = {
    proxiedServiceInfo = {
      serviceName = "shiori";
      domainNameList = ["shiori.not_exist.com"];
      upstreamHostName = "shiori";
      listeningPort = "8080";
      proxyNetwork = "caddy-proxy-internal-network";
      serviceLabels = ["reverse-proxy-component: 'proxied-service'"];
    };

    /**
      List of borgbackup configs for one or more borgbackup servers.

      Note: `borgConfigPaths.sourceData` will be set below.
    */
    borgConfigList = [];

    shioriConfigPaths = {
      env = {

        shioriConfigEnv = "";


        /**
          `shioriSecretsEnv` should have: "SHIORI_HTTP_SECRET_KEY_FILE"

          Example `shiori_secrets.env`:
          ```
          SHIORI_HTTP_SECRET_KEY_FILE="<key>"
          ```
        */
        shioriSecretsEnv = "${userHome}/secrets/shiori_secrets.env";
      };
    };
  };

  cfg = options // config;


  # -- docker-compose--for-borgbackup.yaml -- To be extended in the shiori docker-compose.yaml

  borgbackupServicesConfig =
    let

      /** Utility function to create docker-compose.yaml file for the borgbackup service */
      createComposeFilesForBorgbackup = borgConfig:
        let
          serviceName = cfg.proxiedServiceInfo.serviceName;

          borgbackupSourceData = [
            "${serviceName}__shiori_data:${serviceName}__shiori_data"
          ];

          borgConfigPaths = borgConfig.borgConfigPaths // {sourceData = borgbackupSourceData; };
          borgConfigFinal = borgConfig // { inherit borgConfigPaths; };

          generalUtility = import ../../../../../utility;
          borgbackupFiles = import generalUtility.backup.borgbackup {inherit pkgs; config = borgConfigFinal;};
        in
        borgbackupFiles.dockerComposeFile;


      indexList = builtins.genList (ii: builtins.toString(ii)) (builtins.length cfg.borgConfigList);
      dockerComposeFileForBorgbackupList = map createComposeFilesForBorgbackup cfg.borgConfigList;


      # -- Create a docker service for each borgbackup configuration.

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


  # -- docker-compose--for-shiori.yaml

  dockerComposeForShiori =
    let
      httpAddress = builtins.head cfg.proxiedServiceInfo.domainNameList;

      shioriConfigEnvPath =
        if cfg.shioriConfigPaths.env.shioriConfigEnv != "" then
          "- ${cfg.shioriConfigPaths.env.shioriConfigEnv}"
        else
          "";
    in
    pkgs.writeText "docker-compose--for-shiori.yaml" ''
      version: "3.4"

      services:
        ${cfg.proxiedServiceInfo.serviceName}:
          image: ghcr.io/go-shiori/shiori
          networks:
            - ${cfg.proxiedServiceInfo.proxyNetwork}
          ports:
            - "${cfg.proxiedServiceInfo.listeningPort}"
          restart:
            unless-stopped
          volumes:
            - ${cfg.proxiedServiceInfo.serviceName}__shiori_data:/shiori/
            #- ${cfg.shioriConfigPaths.env.shioriSecretsEnv}:/run/secrets/shiori_secrets
          environment:
            SHIORI_DIR: /shiori/
            SHIORI_HTTP_ADDRESS: ${httpAddress}
            SHIORI_HTTP_PORT: ${cfg.proxiedServiceInfo.listeningPort}
          env_file:
            - ${cfg.shioriConfigPaths.env.shioriSecretsEnv}
            ${shioriConfigEnvPath}


        # -- Configure Borg Backup

        ${borgbackupServicesConfig}


      volumes:
        ${cfg.proxiedServiceInfo.serviceName}__shiori_data:

      networks:
        ${cfg.proxiedServiceInfo.proxyNetwork}:
          name: ${cfg.proxiedServiceInfo.proxyNetwork}
          external: true
    '';

in
{
  derivation = pkgs.stdenv.mkDerivation {
    name = "shiori";
    src = ./.;
    installPhase = ''
      mkdir $out

      cp ${dockerComposeForShiori} $out/docker-compose--for-shiori.yaml
    '';
  };

  dockerComposeFile = dockerComposeForShiori;
}
