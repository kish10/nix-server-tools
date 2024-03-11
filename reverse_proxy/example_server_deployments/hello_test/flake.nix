{
  description = ''
    Example flake.nix file to deploy a reverse proxy server with a hello-test-app.

    Build the server configuration files using `nix build .#proxyServer --impure` in the current directory.
    - Note:
      - Using `--impure` here since this is a flake & `builtins.getEnv` is used in the file.
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


    /**
      Obtain the domainName through an enviroment variable as an example, but in practice it is better to put the domain name in the `proxiedServiceInfo` attribute directly.

      Note:
      - Since this is a flake, the environment variable would not be read unless build with `nix build .#proxyServer --impure`.
    */
    domainNameHelloTestApp =
      let
        domainNameHelloTestAppFromEnv = builtins.getEnv "DOMAIN_NAME_HELLO_TEST_APP";
      in
      if domainNameHelloTestAppFromEnv != "" then domainNameHelloTestAppFromEnv else "hello.test.example.com";



    proxiedServices = [
      rec {
        proxiedServiceInfo = {
          serviceName = "hello-test-app";
          domainNameList = [domainNameHelloTestApp];
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
