/**
  Example test example app for the proxy server.

  To use, add the following to the `proxiedServices` list in the server's flake.nix file:
  ```nix
  # -- hello-test-app --
  rec {
    proxiedServiceInfo = {
      domainNameList = ["www.<application domain name>" "<application domain name>"];
      listeningPort = "80";
      inherit proxyNetwork;
      serviceName = "hello-test-app";
      upstreamHostname = "hello-test-app";
    };
    dockerComposeFile = import <path to this file> {inherit pkgs; inherit proxiedServiceInfo};
  }
*/

{pkgs, proxiedServiceInfo}:
let

  # -- Create static html file for the hello test app.

  indexHtml = pkgs.writeText "index.html" ''
    <h1>Hello</h1>
    <img alt='Hello dog cartoon gif.' src="hello_dog_cartoon.gif">
    <p>(I'd love to attribute this gif, please let me know if you know the author's details.)</p>
  '';


  # -- Bring necessary files into one folder.

  /**
    This is a example of how to bring necessary files into one folder.

    This is necessary when have a Docker file that requires external files for `COPY` command.
    To use this derivation for a docker context need to:
      - Add the dockerfile to the derivation output:
        ```
        mkdir $out
        mkdir $out/nginx_html/

        cp ${indexHtml} $out/nginx_html/index.html
        cp ${./hello_dog_cartoon.gif} $out/nginx_html/hello_dog_cartoon.gif
        cp ${dockerfile} $out/Dockerfile
        ```
      - In service definition, would need to add:
        ```
        build:
          context: ${nginxHtmlFolder}
          dockerfile: ${nginxHtmlFolder}/Dockerfile
        ```
      - Note:
        - Don't need to add this folder as a bind volume in that case since would be directly using `COPY` in the Dockerfile:
          ```
          COPY index_html/. /usr/share/nginx/html/
          ```
  */
  nginxHtmlFolder = pkgs.stdenv.mkDerivation {
    name = "nginx_html_folder";
    src = ./.;
    installPhase = ''
      mkdir $out

      cp ${indexHtml} $out/index.html
      cp ${./hello_dog_cartoon.gif} $out/hello_dog_cartoon.gif
    '';
  };


  # -- Create the compose file for the test app.

  dockerComposeFile = pkgs.writeText "docker-compose.yaml" ''
    version: "3.7"

    services:
      ${proxiedServiceInfo.serviceName}:
        hostname: ${proxiedServiceInfo.upstreamHostName}
        image: nginx
        volumes:
          - ${nginxHtmlFolder}:/usr/share/nginx/html/
        ports:
          - "8000:${proxiedServiceInfo.listeningPort}"
        networks:
          - ${proxiedServiceInfo.proxyNetwork}
  '';
in
# -- Check listening port to make sure it's defined to be the one required for the app.
if proxiedServiceInfo.listeningPort == "80" then
  dockerComposeFile
else
  abort "Listening port for hello_test_app must be \"80\""

