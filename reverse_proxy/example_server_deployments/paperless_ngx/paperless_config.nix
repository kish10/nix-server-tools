{pkgs ? <nixpkgs> {}, proxyNetwork, serviceLabels}:
  let
    userHome = builtins.getEnv("HOME");

    borgConfig1 = import ./borgbackup_config_for_storage_box_1.nix {inherit pkgs;};
  in
  {
    proxiedServiceInfo = {
      serviceName = "paperless-ngx";
      domainNameList = ["paperlessngx.apps.example.com" "www.paperlessngx.apps.example.com"];
      upstreamHostName = "paperless-ngx";
      listeningPort = "8000";
      proxyNetwork = "caddy-proxy-internal-network";
      serviceLabels = ["reverse-proxy-component: 'proxied-service'"];
    };

    borgConfigList = [
      borgConfig1
    ];

    paperlessConfigPaths = {
      env = {
        /**
          `paperlessSecretsEnv` should set: "PAPERLESS_SECRET_KEY"

          Example `paperless-ngx_secrets.env`:
          ```
          PAPERLESS_SECRET_KEY=<key>
          ```
        */
        paperlessSecretsEnv = "${userHome}/secrets/paperless-ngx_secrets.env";
      };
    };
  }
