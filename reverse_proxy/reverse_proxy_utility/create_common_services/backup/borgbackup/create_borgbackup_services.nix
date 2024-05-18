/**
  # Type

  createBorgbackupServices :: {pkgs, string, [set], [string], string} -> derivation

  # Argument
  sourceServiceName
  : Name of the sourceService that borgbackup services would be associated with, the borgbackup services would be named after the proxiedSerivice & they will depend on the proxiedService to be created first.

  borgConfigList
  : List of configuration for borgbackup, without the `sourceData` since that will be set here.

  borgbackupSourceData
  : List of mappings to local folder/file or docker volume to path in borgbackup repo. Format should be `local_path:repo_path`.
*/
{
  pkgs ? import <nixpkgs> {},
  sourceServiceName,
  borgConfigList,
  borgbackupSourceData,
  stringSepForServiceInYaml ? "\n\ \ "
}:
let

  /** Utility function to create docker-compose.yaml file for the borgbackup service */
  createComposeFilesForBorgbackup = borgConfig:
    let
      borgConfigPaths = borgConfig.borgConfigPaths // {sourceData = borgbackupSourceData; };
      borgConfigFinal = borgConfig // { inherit borgConfigPaths; };

      generalUtility = import ../../../../../utility;
      borgbackupFiles = import generalUtility.backup.borgbackup {inherit pkgs; config = borgConfigFinal;};
    in
    borgbackupFiles.dockerComposeFile;


  # -- Create list of docker compose files for the borgbackup services.

  dockerComposeFileForBorgbackupList = map createComposeFilesForBorgbackup borgConfigList;


  # -- Create a `zippedIndexAndFileList` for convenient processing.

  indexList = builtins.genList (ii: builtins.toString(ii)) (builtins.length borgConfigList);
  zippedIndexAndFileList = pkgs.lib.lists.zipListsWith (ii: f: {index = ii; dockerComposeFile = f;}) indexList dockerComposeFileForBorgbackupList;


  # -- Create a list of borg services.

  makeBorgService = {index, dockerComposeFile}:
    ''
      ${sourceServiceName}-borgbackup-${index}:
          extends:
            file: ${dockerComposeFile}
            service: borgbackup
          depends_on:
            - ${sourceServiceName}
    '';

  borgServiceList = map makeBorgService zippedIndexAndFileList;
in
builtins.concatStringsSep stringSepForServiceInYaml borgServiceList
