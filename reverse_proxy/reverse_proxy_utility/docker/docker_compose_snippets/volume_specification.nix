{pkgs ? import <nixpkgs> {}}:
let
  indent = indentLevel: pkgs.lib.strings.concatStringsSep "" (pkgs.lib.lists.replicate indentLevel "\ \ ");
in
rec {
  specifyDockerManagedVolume = {indentStart ? 1, name, ...}:
    "${indent indentStart}${name}:";

  specifyLocalVolume = {indentStart ? 1, mountPoint, name, ...}:
    ''
      ${indent indentStart}${name}:
      ${indent (indentStart + 1)}driver: local
      ${indent (indentStart + 1)}driver_opts:
      ${indent (indentStart + 2)}o: bind
      ${indent (indentStart + 2)}type: none
      ${indent (indentStart + 2)}device: ${mountPoint}
    '';

  specifyExternalVolume = {indentStart ? 1, name, ...}:
    ''
      ${indent indentStart}${name}:
      ${indent (indentStart + 1)}external: true
    '';


  /**
    Example:
    {
      driver="local";
      name="${serviceName}__paperless_data";
      mountPoint="";
    }
  */
  specifyVolume = args@{
    driver ? "local",
    indentStart ? 1,
    mountPoint ? "",
    name
  }:
    if (driver == "local") && (mountPoint == "") then
      specifyDockerManagedVolume args
    else if (driver == "local") && (mountPoint != "") then
      specifyLocalVolume args
    else if (driver == "external") then
      specifyExternalVolume args
    else
      abort "Volume specification configuration not recognized";
}
