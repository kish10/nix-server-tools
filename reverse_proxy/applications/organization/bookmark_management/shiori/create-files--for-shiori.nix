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

  serviceName = cfg.proxiedServiceInfo.serviceName;

  reverseProxyUtility = import ../../../../reverse_proxy_utility;
  createBorgbackupServices = reverseProxyUtility.createCommonServices.backup.borgbackup.createBorgbackupServices;

  borgbackupServicesConfig = import createBorgbackupServices {
    inherit pkgs;
    sourceServiceName = serviceName;
    borgConfigList = cfg.borgConfigList;
    borgbackupSourceData = [
      "${serviceName}__shiori_data:${serviceName}__shiori_data"
    ];
    stringSepForServiceInYaml = "\n\ \ ";
  };


  # -- docker-compose--for-shiori.yaml

  dockerComposeForShiori =
    let
      httpAddress = builtins.head cfg.proxiedServiceInfo.domainNameList;

      proxiedServiceLabelConfigLines =
        builtins.concatStringsSep "\n\ \ \ \ " cfg.proxiedServiceInfo.serviceLabels;

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
          environment:
            SHIORI_DIR: /shiori/
            SHIORI_HTTP_ADDRESS: ${httpAddress}
            SHIORI_HTTP_PORT: ${cfg.proxiedServiceInfo.listeningPort}
          env_file:
            - ${cfg.shioriConfigPaths.env.shioriSecretsEnv}
            ${shioriConfigEnvPath}
          labels:
            ${proxiedServiceLabelConfigLines}
          networks:
            - ${cfg.proxiedServiceInfo.proxyNetwork}
          ports:
            - "${cfg.proxiedServiceInfo.listeningPort}"
          restart:
            unless-stopped
          volumes:
            - ${cfg.proxiedServiceInfo.serviceName}__shiori_data:/shiori/
            #- ${cfg.shioriConfigPaths.env.shioriSecretsEnv}:/run/secrets/shiori_secrets

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
