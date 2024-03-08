{pkgs, caddyJsonFile, proxyNetwork ? "caddy-proxy-internal-network"}:
let

  # -- Create the "Dockerfile" for the caddy proxy server.

  runCaddySh = pkgs.writeText "run-caddy.sh" ''
    #!/bin/sh

    curl localhost:2019/load \
      -H "Content-Type: application/json" \
      -d @/etc/caddy/caddy.json


    # Note:
    # - The "@" is curl syntax to load data from a file.
  '';


  dockerFileCaddy = pkgs.writeText "Dockerfile--for-caddy-proxy" ''
    FROM caddy:latest

    RUN apk --no-cache add curl

    ADD run-caddy.sh /etc/caddy/run-caddy.sh
    RUN chmod +x /etc/caddy/run-caddy.sh

    # Change workdir to `/etc/caddy/` for convience when debbuging
    WORKDIR /etc/caddy/

    CMD ["caddy", "run", "--config", "/etc/caddy/caddy.json"]
  '';


  # -- Create the "docker-compose.yaml" file the caddy proxy server.

  dockerComposeFile = pkgs.writeText "docker-compose--for-proxy-server.yaml" ''
    services:
      caddy-proxy:
        build:
          context: .
          dockerfile: '${dockerFileCaddy}'
        labels:
          reverse-proxy-component: 'proxy-server'
        environment:
          CADDY_PATH_TO_JSON_CONFIG: /etc/caddy/caddy.json
        ports:
          - "2019:2019" # Caddy API
          # Note:
          # - If on "rootless" docker, can use privileged ports by running:
          #   - `sudo setcap cap_net_bind_service=ep $(which rootlesskit)`
          #   - `systemctl --user restart docker`
          # - Reference:
          #   - https://docs.docker.com/engine/security/rootless/#exposing-privileged-ports
          - "80:80"
          - "443:443"

        volumes:
          - caddy-proxy-data:/data
          - caddy-proxy-config:/config
          # Note:
          # - Watch for the container exiting with an error, since Caddy can fail if the config is correctly setup
          #     - When that happens on another terminal run:
          #         - `docker container exec -it server-caddy-proxy-1 /bin/sh`
          #         - In the container's shell run diagnostics steps such as:
          #             - `/etc/caddy/caddy.json`
          #             - `curl localhost:2019/config/`
          - ${caddyJsonFile}:/etc/caddy/caddy.json # Needed to configure Caddy
        networks:
          - caddy-proxy-external-network
          - ${proxyNetwork}
        restart: unless-stopped

    volumes:
      # Note:
      # - `caddy-proxy-data` created externally so that the volume isn't deleted on `docker-compose down`
      #     - External volume created using: `docker volume create caddy-proxy-data`
      caddy-proxy-data:
        external: true
      caddy-proxy-config:

    networks:
      caddy-proxy-external-network:
        driver: bridge
      ${proxyNetwork}:
        driver: bridge
  '';
in
pkgs.stdenv.mkDerivation {
  name = "proxy-server-docker-config";
  src = ./.;
  installPhase = ''
    mkdir $out

    # -- Copy files into same directory for docker context (since using "." as the docker context)

    cp ${runCaddySh} $out/run-caddy.sh
    cp ${dockerFileCaddy} $out/Dockerfile--for-caddy-proxy
    cp ${dockerComposeFile} $out/docker-compose--for-caddy-proxy.yaml
  '';
}
