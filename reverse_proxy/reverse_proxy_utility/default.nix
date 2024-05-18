{
  createCommonServices = {
    backup = {
      borgbackup = {
        createBorgbackupServices = ./create_common_services/backup/borgbackup/create_borgbackup_services.nix;
      };
    };
  };

  docker = {
    dockerComposeSnippets = {
      volumeSpecification = ./docker/docker_compose_snippets/volume_specification.nix;
    };
  };

  shell = {
    buildInputs = {
      dockerUtility = ./docker_utilities.nix;
    };
  };
}
