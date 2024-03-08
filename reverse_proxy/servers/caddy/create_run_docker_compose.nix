/**
  Creates an executable "run_docker_compose.sh" that is used to start the reverse proxy server & the proxied applications.

  # Type

  createRunDockerCompose :: {pkgs, path, [{dockerComposeFile = path; proxiedServiceInfo = {domainNameList = [string]; listeningPort = string; proxyNetwork = string; serviceName = string; upstreamHostName = string;};}], [string], [string]} -> derivation
*/

{pkgs, dockerComposeForProxyServer, proxiedServices, externalVolumes}:
let

  scriptArgs = ''
    ARG_BUILD="--build"

    while [ "$1" != "" ]; do
      case $1 in
      -b | --build) # Default is "--build", use `-b false` to not rebuild
        shift
        if [ $1 = "false" ]; then
          ARG_BUILD=""
        fi
        ;;
      esac
      shift
    done
  '';


  toEnsureExternalVolumesExist =
    let
      externalVolumesListString = builtins.concatStringsSep " " (map (v: "'${v}'") externalVolumes);
    in
    ''
      # -- Create necessary external docker volumes if not exists

      EXTERNAL_VOLUMES=(${externalVolumesListString})

      volumeExists () {
        if [ "$(docker volume ls -f name=$1 | awk '{print $NF}' | grep -E '^'$1'$')" ]; then
          return 0
        else
          return 1
        fi
      }

      for external_volume in "''${EXTERNAL_VOLUMES[@]}"; do
        if ! volumeExists $external_volume; then
          docker volume create $external_volume
        fi
      done
    '';


  runCommand = ''
    # -- docker compose run command

    docker compose \
      -f ${dockerComposeForProxyServer}/docker-compose--for-caddy-proxy.yaml ${if builtins.length proxiedServices > 0 then "-f" else ""} ${builtins.concatStringsSep " -f " (map (service: service.dockerComposeFile) proxiedServices)} \
      up --build
  '';
in
pkgs.writeScript "run-docker-compose.sh" ''
  #!/bin/sh


  ${scriptArgs}


  ${toEnsureExternalVolumesExist}


  ${runCommand}
''
