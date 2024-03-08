/**
  Creates files to build & run docker compose services for the caddy reverse proxy, and the proxied application services.

  # Type

  setupCaddyProxyServer :: { pkgs, [{dockerComposeFile = path; proxiedServiceInfo = {domainNameList = [string]; listeningPort = string; proxyNetwork = string; serviceName = string; serviceLabels = [string]; upstreamHostName = string;};}], [string] } -> derivation


  # Arguments

  pkgs
  : Nixpkgs

  proxiedServices
  : List of sets defining the proxied service
    - Explanation of attributes:
      - `dockerComposeFile`, path to a "docker-compose.yaml" file for the application -- Services defined in the compose file will be built & ran along with the reverse proxy service.
      - `proxiedServiceInfo`, network information for the proxied service (the application).
        - Should have the attributes:
            - Labels for the proxied service
          - `domainNameList`:
            - List of domain names for which the traffic should be routed to the appplication service by the reverse proxy service.
            - Note:
              - Need to make sure that there is a public DNS record that points to the domains to this server.
                - If get a `letsencrypt` error then a missing public DNS record is the likely cause.
        - `serviceLabels`:
          - Labels for the service.
            - Note: The "reverse-proxy-component: 'proxied-service'" label is used to filter proxied service containers in the docker utility scripts.
    - Example:
      ```nix
      [
        {
          dockerComposeFile = ./docker-compose-file--for-application-1.yaml;
          proxiedServiceInfo = {
            componentLabels = ["reverse-proxy-component: 'proxied-service'"];
            domainNameList = ["www.subsubdomain.subdomain.example.com" "subsubdomain.subdomain.example.com"];
            listeningPort = "8000";
            proxyNetwork = "caddy-proxy-internal-network;
            serviceName = "docker-service-name";
            upstreamHostName = "service-container-hostname";
          };
        }
      ]
      ```

  externalVolumes
  : List of volumes that need to be created externally (the volume is created if it doesn't exist already).
    - Note:
      - It is necessary to create critical volumes that don't want to be deleted on `docker compose down` externally.
*/

{pkgs ? import <nixpkgs> {}, proxiedServices, externalVolumes ? [] }:
let

  # -- Get the caddy proxy `proxyNetwork`

  allProxyNetworks = (map (ps: ps.proxiedServiceInfo.proxyNetwork) proxiedServices);
  firstProxyNetwork = builtins.head(allProxyNetworks);
  /**
    `lastProxyNetworkInEqualityChain`, represents the last `proxyNetwork` in an equality chain.
    `lastProxyNetworkInEqualityChain` == "not_e_#@4*~zxcs#!" if there is atleast one not same.
    Note:
    - It's faster to check if all are same through a chain since checking equality of each pair is O(n^2).
  */
  lastProxyNetworkInEqualityChain =
    builtins.foldl' (acc: pn: if acc == pn then pn else "not_e_#@4*~zxcs#!") firstProxyNetwork allProxyNetworks;

  proxyNetwork =
    if firstProxyNetwork == lastProxyNetworkInEqualityChain then
      firstProxyNetwork
    else
      abort "Atleast one `proxyNetwork` value in the `proxiedServices` list is not the same as the others.";


  # -- Create caddy.json file for the caddy server.

  caddyJsonFile = import ./create_caddy_json.nix {
    inherit pkgs;
    inherit proxiedServices;
  };


  # -- Create the docker-compose.yaml file for the caddy proxy server.

  dockerComposeForProxyServer = import ./create_docker_compose_for_proxy_server.nix {
    inherit pkgs;
    inherit caddyJsonFile;
    inherit proxyNetwork;
  };


  # -- Get utility function for copying the "docker-compose.yaml" files of the services to the output. (For reference when debugging)

  getServiceComposeFileCp = service:
  # Get `cp` command to copy the services dockerComposeFile to the result output directory
  # Note: `$(date +"%Y-%m-%d_%H-%M-%S")__` is added to ensure that the file name is unique
  let
    splitedPath = builtins.split "/" "${service.dockerComposeFile}";
    fileName = builtins.elemAt splitedPath (builtins.length splitedPath - 1);
  in
  ''
    cp ${service.dockerComposeFile} $out/docker_files/for_proxied_services/$(date +"%Y-%m-%d_%H-%M-%S")__${fileName}
  '';


  # -- Create run-docker-compose.sh script

  runComposeSh = import ./create_run_docker_compose.nix {
    inherit pkgs;
    inherit dockerComposeForProxyServer;
    inherit proxiedServices;
    externalVolumes = ["caddy-proxy-data"] ++ externalVolumes;
  };

in
pkgs.stdenv.mkDerivation {
  name = "proxy-server";
  src = ./.;
  installPhase = ''
    mkdir $out
    mkdir $out/caddy_config
    mkdir $out/docker_files
    mkdir $out/docker_files/for_proxy_server/
    mkdir $out/docker_files/for_proxied_services/

    # -- Copy caddy file
    cp ${caddyJsonFile} $out/caddy_config/caddy.json

    # -- Copy docker files
    cp -r ${dockerComposeForProxyServer}/. $out/docker_files/for_proxy_server/

    ${builtins.concatStringsSep "\n " (builtins.map getServiceComposeFileCp proxiedServices)}

    # -- Copy run-docker-compose.sh
    cp ${runComposeSh} $out/run-docker-compose.sh
  '';
}
