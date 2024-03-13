{
  description = ''
    Example flake.nix file to deploy a reverse proxy server with {hello-test-app, paperless-ngx} deployments.

    Build the server configuration files using `nix build .#proxyServer --impure` in the current directory.
    - Note:
      - Using `--impure` here since this is a flake & `builtins.getEnv` is used in config associated to the file.
        - However the `builtins.getEnv` was used in the file for the example, and not needed or recommended in practice.
  '';

  inputs = {
    nixpkgs.url = "github:Nixos/nixpkgs/nixos-22.11";
  };

  outputs = {self, nixpkgs}:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};


      proxyServers = import ../../servers;
      applications = import ../../applications;


      proxyNetwork = "caddy-proxy-internal-network";
      serviceLabels = ["reverse-proxy-component: \"proxied-service\""];


      # -- Get "docker-compose.yaml" for paperless-ngx

      config = import ./paperless_config.nix {inherit pkgs; inherit proxyNetwork; inherit serviceLabels;};
      paperlessngxFiles = import applications.organization.document_manager.paperlessngx {
        inherit pkgs;
        inherit config;
      };
      dockerComposeForPaperlessngx = paperlessngxFiles.dockerComposeFile;

      # -- proxiedServices

      proxiedServices = [
        # -- hello-test-app

        rec {
          proxiedServiceInfo = {
            serviceName = "hello-test-app";
            domainNameList = ["hello.test.app.patel.blue"];
            upstreamHostName = "hello-test-app";
            listeningPort = "80";
            inherit proxyNetwork;
            inherit serviceLabels;
          };
          dockerComposeFile = import applications.testExamples.helloTestApp.dockerComposeFile {
            inherit pkgs;
            inherit proxiedServiceInfo;
          };
        }


        # -- paperless_ngx

        rec {
          proxiedServiceInfo = config.proxiedServiceInfo;
          dockerComposeFile = dockerComposeForPaperlessngx;
        }
      ];
  in
  {
    packages.${system}.proxyServer = import proxyServers.caddy.proxyServer {
      inherit pkgs;
      inherit proxiedServices;
      externalVolumes = [];
    };
  };
}
