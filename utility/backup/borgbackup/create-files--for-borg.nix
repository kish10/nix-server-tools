{pkgs ? import <nixpkgs> {}, config}:
let
  options =

  cfg = options // config;
in

