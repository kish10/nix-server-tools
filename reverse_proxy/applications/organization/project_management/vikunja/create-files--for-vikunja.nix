{
  pkgs ? import <nixpkgs>{},
  config ? {}
}:
let
  userHome = builtins.getEnv("HOME");

  options = {
    proxiedServiceInfo = {
      serviceName = "vikunja";
      domainNameList = ["vikunja.not_exist.com"];
      upstreamHostName = "vikunja";
      listeningPort = "3456";
      proxyNetwork = "caddy-proxy-internal-network";
      serviceLabels = ["reverse-proxy-component: 'proxied-service'"];
    };

    /**
      List of borgbackup configs for one or more borgbackup servers.

      Note: `borgConfigPaths.sourceData` will be set below.
    */
    borgConfigList = [];

    dockerVolumes = {
      vikunjaFiles = {
        driver="local";
        name="${proxiedServiceInfo.serviceName}__vikunja_files";
        mountPoint="";
      };

     vikunjaDB = {
        driver="local";
        name="${proxiedServiceInfo.serviceName}__vikunja_db";
        mountPoint="";
      };
    };

    vikunjaConfigPaths = {
      env = {

        /**
          Environment variables file for Vikunja (In Docker format).

          See `https://vikunja.io/docs/config-options/` for more enviroment variable options.
        */
        vikunjaConfigEnv = "";


        /**
          `vikunjaSecretsEnv` for secrets such as: "VIKUNJA_SERVICE_JWTSECRET"

          Example `vikunja_secrets.env`:
          ```
          VIKUNJA_SERVICE_JWTSECRET="<key>"
          ```
        */
        vikunjaSecretsEnv = ""; #"${userHome}/secrets/vikunja_secrets.env";
      };
    };


    /**
      Vikunja enviroment variables set through Nix for convinience.
    */
    vikunjaEnvVars = {
      /**
        Timezone for Vikunja, Vikunja's default timezone is GMT.

        See "TZ Identifier" in `https://en.wikipedia.org/wiki/List_of_tz_database_time_zones` for additional timezones.

        (Users can also change the timezone once logged in.)
      */
      timezone = "GMT";


      /**
        Disable registration by defualt.

        Should be a string: "true"/"false"

        To create a user can:
        - Exec into the container `docker exec -it <container> /bin/sh`
        - Within the container run `/app/vikunja/vikunja user create -e <email> -p <password> -u <username>`

        References:
        - https://vikunja.io/docs/cli/
      */
      enableRegistration = "false";
    };
  };

  cfg = options // config;


  # -- docker-compose--for-borgbackup.yaml -- To be extended in the vikunja docker-compose.yaml

  serviceName = cfg.proxiedServiceInfo.serviceName;

  reverseProxyUtility = import ../../../../reverse_proxy_utility;
  createBorgbackupServices = reverseProxyUtility.createCommonServices.backup.borgbackup.createBorgbackupServices;

  borgbackupServicesConfig = import createBorgbackupServices {
    inherit pkgs;
    sourceServiceName = serviceName;
    borgConfigList = cfg.borgConfigList;
    borgbackupSourceData = [
      "${serviceName}__vikunja_files:${serviceName}__vikunja_files"
      "${serviceName}__vikunja_db:${serviceName}__vikunja_db"
    ];
    stringSepForServiceInYaml = "\n\ \ ";
  };


  # -- Dockerfile--for-vikunja

  /**
    Need to explicitly create relevant Vikunja folders to avoid "permission denied" errors when the don't exist.
  */
  dockerFileForVikunja = pkgs.writeText "Dockerfile--for-vikunja" ''
    FROM vikunja/vikunja

    RUN mkdir -p /data/vikunja/files/
    RUN mkdir -p /data/vikunja/db/

    WORKDIR /app/vikunja
    ENTRYPOINT [ "/app/vikunja/vikunja" ]
  '';


  # -- docker-compose--for-vikunja.yaml

  volumeSpecificationUtility = import reverseProxyUtility.docker.dockerComposeSnippets.volumeSpecification {inherit pkgs;};
  specifyVolume = volumeSpecificationUtility.specifyVolume;

  dockerComposeFile =
    let
      domainName = (builtins.head cfg.proxiedServiceInfo.domainNameList);
      httpAddress = "https://${domainName}/"; # Need: https://<your public frontend url with slash>/

      proxiedServiceLabelConfigLines =
        builtins.concatStringsSep "\n\ \ \ \ " cfg.proxiedServiceInfo.serviceLabels;


      vikunjaConfigEnvPath =
        if cfg.vikunjaConfigPaths.env.vikunjaConfigEnv != "" then
          "- ${cfg.vikunjaConfigPaths.env.vikunjaConfigEnv}"
        else
          "";

      vikunjaSecretsEnvPath =
        if cfg.vikunjaConfigPaths.env.vikunjaSecretsEnv != "" then
          "- ${cfg.vikunjaConfigPaths.env.vikunjaSecretsEnv}"
        else
          "";

      envFileConfig =
        if (vikunjaConfigEnvPath != "") || (vikunjaSecretsEnvPath != "") then
          ''
            env_file:
              ${vikunjaConfigEnvPath}
              ${vikunjaSecretsEnvPath}
          ''
        else
          "";
    in
    pkgs.writeText "docker-compose--for-vikunja.yaml" ''
      version: "3.4"

      services:
        ${cfg.proxiedServiceInfo.serviceName}:
          build:
            context: ${./.}
            dockerfile: ${dockerFileForVikunja}
          environment:
            VIKUNJA_DATABASE_PATH: /data/vikunja/db/vikunja.db
            VIKUNJA_FILES_BASEPATH: /data/vikunja/files/
            VIKUNJA_SERVICE_ENABLEREGISTRATION: ${cfg.vikunjaEnvVars.enableRegistration}
            VIKUNJA_SERVICE_INTERFACE: ":${cfg.proxiedServiceInfo.listeningPort}" # Note: Need the ":".
            VIKUNJA_SERVICE_PUBLICURL: ${httpAddress}
            VIKUNJA_SERVICE_TIMEZONE: ${cfg.vikunjaEnvVars.timezone}
          ${envFileConfig}
          labels:
            ${proxiedServiceLabelConfigLines}
          networks:
            - "${cfg.proxiedServiceInfo.proxyNetwork}"
          ports:
            - "${cfg.proxiedServiceInfo.listeningPort}"
          volumes:
            - ${cfg.proxiedServiceInfo.serviceName}__vikunja_files:/data/vikunja/files/
            - ${cfg.proxiedServiceInfo.serviceName}__vikunja_db:/data/vikunja/db/
          restart: unless-stopped


        # -- Configure Borg Backup

        ${borgbackupServicesConfig}


      volumes:
      ${specifyVolume cfg.dockerVolumes.vikunjaFiles}
      ${specifyVolume cfg.dockerVolumes.vikunjaDB}


      networks:
        ${cfg.proxiedServiceInfo.proxyNetwork}:
          name: ${cfg.proxiedServiceInfo.proxyNetwork}
          external: true

    '';
in
{
  derivation = pkgs.stdenv.mkDerivation {
    name = "vikunja";
    src = ./.;
    installPhase = ''
      mkdir $out

      cp ${dockerComposeFile} $out/docker-compose--for-vikunja.yaml
    '';
  };

  dockerComposeFile = dockerComposeFile;
}
