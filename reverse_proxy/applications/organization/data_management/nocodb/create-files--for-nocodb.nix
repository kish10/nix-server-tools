/**
  Creates Docker services for NocoDB.

  See: [Github - NocoDB](https://github.com/nocodb/nocodb) for details.

*/
{
  pkgs ? import <nixpkgs>{},
  config ? {}
}:
let
  userHome = builtins.getEnv("HOME");

  options = rec {
    proxiedServiceInfo = {
      serviceName = "nocodb";
      domainNameList = ["nocodb.not_exist.com"];
      upstreamHostName = "nocodb";
      listeningPort = "8080";
      proxyNetwork = "caddy-proxy-internal-network";
      serviceLabels = ["reverse-proxy-component: 'proxied-service'"];
    };

    /**
      List of borgbackup configs for one or more borgbackup servers.

      Note: `borgConfigPaths.sourceData` will be set below.
    */
    borgConfigList = [];

    dockerVolumes = {
      nocodbData = {
        driver="local";
        name="${proxiedServiceInfo.serviceName}__nocodb_data";
        mountPoint="";
      };
    };

    nocodbConfigPaths = {
      env = {

        nocodbConfigEnv = "";


        /**
          `nocodbSecretsEnv` should have: "NC_AUTH_JWT_SECRET"

          Example `nocodb_secrets.env`:
          ```
          NC_AUTH_JWT_SECRET="<jwt secret>"
          ```
        */
        nocodbSecretsEnv = "${userHome}/secrets/nocodb_secrets.env";
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
      "${cfg.dockerVolumes.nocodbData.name}:${cfg.dockerVolumes.nocodbData.name}"
    ];
    stringSepForServiceInYaml = "\n\ \ ";
  };


  # -- docker-compose--for-nocodb.yaml

  volumeSpecificationUtility = import reverseProxyUtility.docker.dockerComposeSnippets.volumeSpecification {inherit pkgs;};
  specifyVolume = volumeSpecificationUtility.specifyVolume;


  dockerComposeForNocoDB =
    let
      domain = builtins.head cfg.proxiedServiceInfo.domainNameList;
      httpAddress =
        if (builtins.match "http://" domain) == [] then
          "http://${domain}"
        else
          domain;

      proxiedServiceLabelConfigLines =
        builtins.concatStringsSep "\n\ \ \ \ " cfg.proxiedServiceInfo.serviceLabels;

      dependencyServiceLabelConfigLines =
        builtins.concatStringsSep "\n\ \ \ \ " ["reverse-proxy-component: 'proxied-service--dependency'"];

      nocodbConfigEnvPath =
        if cfg.nocodbConfigPaths.env.nocodbConfigEnv != "" then
          "- ${cfg.nocodbConfigPaths.env.nocodbConfigEnv}"
        else
          "";
    in
    pkgs.writeText "docker-compose--for-nocodb.yaml" ''
      version: "3.4"

      services:
        ${cfg.proxiedServiceInfo.serviceName}-redis-broker:
          image: docker.io/library/redis:7
          labels:
            ${dependencyServiceLabelConfigLines}
          networks:
            - ${cfg.proxiedServiceInfo.serviceName}__nocodb_internal
          ports:
            - "6379"
          restart: unless-stopped
          volumes:
            - ${cfg.proxiedServiceInfo.serviceName}__nocodb_redisdata:/data

        ${cfg.proxiedServiceInfo.serviceName}:
          image: nocodb/nocodb:latest
          environment:
            NC_TOOL_DIR: /usr/app/data/
            #NC_PUBLIC_URL: ${httpAddress}
            NC_REDIS_URL: redis://${cfg.proxiedServiceInfo.serviceName}-redis-broker:6379
            PORT: ${cfg.proxiedServiceInfo.listeningPort}
          env_file:
            - ${cfg.nocodbConfigPaths.env.nocodbSecretsEnv}
            ${nocodbConfigEnvPath}
          labels:
            ${proxiedServiceLabelConfigLines}
          networks:
            - ${cfg.proxiedServiceInfo.serviceName}__nocodb_internal
            - ${cfg.proxiedServiceInfo.proxyNetwork}
          ports:
            - ${cfg.proxiedServiceInfo.listeningPort}
          restart:
            unless-stopped
          volumes:
            - ${cfg.dockerVolumes.nocodbData.name}:/usr/app/data/

        # -- Configure Borg Backup

        ${borgbackupServicesConfig}


      volumes:
      ${specifyVolume cfg.dockerVolumes.nocodbData}
        ${cfg.proxiedServiceInfo.serviceName}__nocodb_redisdata:

      networks:
        ${cfg.proxiedServiceInfo.serviceName}__nocodb_internal:
          driver: bridge
        ${cfg.proxiedServiceInfo.proxyNetwork}:
          name: ${cfg.proxiedServiceInfo.proxyNetwork}
          external: true
    '';

in
{
  derivation = pkgs.stdenv.mkDerivation {
    name = "nocodb";
    src = ./.;
    installPhase = ''
      mkdir $out

      cp ${dockerComposeForNocoDB} $out/docker-compose--for-nocodb.yaml
    '';
  };

  dockerComposeFile = dockerComposeForNocoDB;
}
