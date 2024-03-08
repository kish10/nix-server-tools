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
{

  /**
    Exec into the proxy server container for debugging.
  */
  execIntoTheProxyContainer = pkgs.writeShellScriptBin "utility_docker_exec_into_the_proxy_container" ''
    #!/bin/sh

    PROXY_CONTAINER_ID=$(docker container ls --format "{{ .ID }}" --filter "label=reverse-proxy-component=proxy-server")

    docker exec -it $PROXY_CONTAINER_ID /bin/sh
  '';


  /**
    Print all docker containers in the proxy server deployment.
  */
  printAllProxyServerContainers = pkgs.writeShellScriptBin "utility_docker_ls_all_proxy_server_containers" ''
    #!/bin/sh

    docker ps \
      --filter 'label=reverse-proxy-component' \
      --format '{\n  "ID": "{{.ID}}",\n  "Name": "{{.Names}}",\n  "Ports": "{{.Ports}}",\n  "Status": {{.Status}}"\n}'
  '';


  /**
    Remove all docker containers in the proxy server deployment.
  */
  rmAllProxyServerContainers = pkgs.writeShellScriptBin "utility_docker_rm_all_proxy_server_containers" ''
    #!/bin/sh

    ALL_PROXY_CONTAINER_IDS=$(docker container ls --format "{{ .ID }}" --filter "label=reverse-proxy-component")
    docker container stop $ALL_PROXY_CONTAINER_IDS
    docker container prune
  '';
}
