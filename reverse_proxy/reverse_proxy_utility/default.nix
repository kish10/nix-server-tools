#{pkgs ? import <nixpgs> {}}:
#{
#  createCommonServices = {
#    backup = {
#      borgbackup = {
#        createBorgbackupServices = ./create_common_services/backup/borgbackup/create_borgbackup_services.nix;
#      };
#    };
#  };
#
#  docker = import ./docker_utilities.nix {inherit pkgs;};
#}


{
  createCommonServices = {
    backup = {
      borgbackup = {
        createBorgbackupServices = ./create_common_services/backup/borgbackup/create_borgbackup_services.nix;
      };
    };
  };

  shell = {
    buildInputs = {
      dockerUtility = ./docker_utilities.nix;
    };
  };
  #docker = import ./docker_utilities.nix {inherit pkgs;};
}
