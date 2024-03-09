/**
  Utilities for working with docker containers for the proxy service.

  Can be used by:
  - Adding to the derivations as buildinputs to the `pkgs.mkShell` derivation.
  - Going into the development shell. Ex using `nix develop .#`
  - The calling the binaries. Ex: `utility_docker_ls_all_proxy_server_containers`.
    - Note:
      - Can use tab complete. Ex: start typing `util` & press `tab`.
*/

{pkgs ? import <nixpkgs> {}}:
let
  /**
    Exec into the proxy server container for debugging.
  */
  execIntoTheProxyContainerSh = pkgs.writeScript "exec_into_the_proxy_container.sh" ''
    #!/bin/sh

    PROXY_CONTAINER_ID=$(docker container ls --format "{{ .ID }}" --filter "label=reverse-proxy-component=proxy-server")

    docker exec -it $PROXY_CONTAINER_ID /bin/sh
  '';


  /**
    Print all docker containers in the proxy server deployment.
  */
  printAllProxyServerContainersSh = pkgs.writeScript "print_all_proxy_server_containers.sh" ''
    #!/bin/sh

    docker ps \
      --filter 'label=reverse-proxy-component' \
      --format '{\n  "ID": "{{.ID}}",\n  "Name": "{{.Names}}",\n  "Ports": "{{.Ports}}",\n  "Status": {{.Status}}"\n}'
  '';


  /**
    Remove all docker containers in the proxy server deployment.
  */
  rmAllProxyServerContainersSh = pkgs.writeScript "rm_all_proxy_server_containers.sh" ''
    #!/bin/sh

    ALL_PROXY_CONTAINER_IDS=$(docker container ls --format "{{ .ID }}" --filter "label=reverse-proxy-component")
    docker container stop $ALL_PROXY_CONTAINER_IDS
    docker container prune
  '';

in
{

  bin = {
    execIntoTheProxyContainer = pkgs.writeShellScriptBin "utility_docker_exec_into_the_proxy_container" ''
      #!/bin/sh

      exec ${execIntoTheProxyContainerSh}
    '';

    printAllProxyServerContainers = pkgs.writeShellScriptBin "utility_docker_ls_all_proxy_server_containers" ''
      #!/bin/sh

      exec ${printAllProxyServerContainersSh}
    '';


    rmAllProxyServerContainers = pkgs.writeShellScriptBin "utility_docker_rm_all_proxy_server_containers" ''
      #!/bin/sh

      exec ${rmAllProxyServerContainersSh}
    '';
  };


  derivation = pkgs.stdenv.mkDerivation {
    name = "age_utility";
    src = ./.;
    installPhase = ''
      mkdir $out

      cp ${execIntoTheProxyContainerSh} $out/exec_into_the_proxy_container.sh
      cp ${printAllProxyServerContainersSh} $out/print_all_proxy_server_containers.sh
      cp ${rmAllProxyServerContainersSh} $out/rm_all_proxy_server_containers.sh
    '';
  };

  scripts = {
    inherit execIntoTheProxyContainerSh;
    inherit printAllProxyServerContainersSh;
    inherit rmAllProxyServerContainersSh;
  };

}
