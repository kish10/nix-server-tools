let
  mkServerSet = createServerDerivationFileNix:
    {
      proxyServer = createServerDerivationFileNix;
    };
in
{
  caddy = mkServerSet ./caddy/setup_proxy_server_config.nix;
}
