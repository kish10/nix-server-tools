{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, ... }:
    let
      # TODO: Make more dynamic, such as using `https://github.com/numtide/flake-utils`
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      utilities = import ./utilities {inherit pkgs;};
      buildInputsDockerUtilities = nixpkgs.lib.attrValues utilities.docker;
    in
    {
      applications = import ./applications;
      inherit utilities;
      servers = import ./applications;

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with nixpkgs; [] ++ buildInputsDockerUtilities;
        shellHook = ''
          # - Change bash prompt
          export PS1="\e[0;32m[(shell) \u@\H:\w]\$ \e[0m"
        '';
      };
    };
}
