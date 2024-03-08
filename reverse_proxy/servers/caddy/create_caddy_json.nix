/**
  Creates a `caddy.json` file using the given `proxiedServices`.

  # Types

  createCaddyJson :: {pkgs, [{dockerComposeFile = path; proxiedServiceInfo = {domainNameList = [string]; listeningPort = string; proxyNetwork = string; serviceName = string; upstreamHostName = string;};}] } -> derivation

*/

{pkgs, proxiedServices}:
let
  getRouteDefinition = service:
  let
    domainNameList = service.proxiedServiceInfo.domainNameList;
    upstreamHostName = service.proxiedServiceInfo.upstreamHostName;
    listeningPort = service.proxiedServiceInfo.listeningPort;

    domainNameListString = builtins.concatStringsSep ", " (builtins.map (d: "\"${d}\"") domainNameList);
  in
  ''
    {
      "match": [{"host": [ ${domainNameListString} ]}],
      "handle": [{
        "handler": "reverse_proxy",
        "upstreams": [{
          "dial": "${upstreamHostName}:${listeningPort}"
        }]
      }]
    }
  '';

  proxyRoutes = builtins.map getRouteDefinition proxiedServices;

in
pkgs.writeText "caddy.json" ''
  {
    "apps": {
      "http": {
        "servers": {
          "reverse_proxy": {
            "listen": [":80", ":443"],
            "routes": [${builtins.concatStringsSep ",\n" proxyRoutes}],
            "logs": {}
          }
        }
      }
    }
  }
''
