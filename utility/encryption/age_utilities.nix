/**
  Utilities for encrypting files using `age`.

  See the age package for details: https://github.com/FiloSottile/age

  # Local usage.

  One way to use the package is: `nix-build <path to this file>`
*/
{pkgs ? import <nixpkgs> {} }:
let

  /**
    Convenience function to encrypt a folder using `age`.

    # Type

    ageEncryptTarGzSh :: {string, string, string} -> derivation


    # Arguments

    secretPath
    : Path to the folder/file that want to encrypt.
      - Note:
        - To avoid secret files from bieng accidentally checked into the nix store, `secretPath` is enforced to be a `string` & not a nix `path`.

    encryptedSecretName
    : The name of the encrypted file.
      - Ex: `encryptedSecretName = "secret_name"` becomes "secret_name.tar.gz".

    ageArgOptions
    : Options for the `age` command.
      - Ex: "-p", for `age -e -p secret_name.tar.gz > secret_name.tar.gz.age`
  */
  ageEncryptTarGzSh = {secretPath ? "$1", encryptedSecretName ? "$2", ageArgOptions ? "$3"}:
    if builtins.isString secretPath then
      pkgs.writeScript "age_encrypt_tar_gz.sh" ''
        #!/bin/sh

        tar -cvz ${secretPath} | age -e ${ageArgOptions} > ${encryptedSecretName}.tar.gz.age
      ''
    else
      abort ''
        The `secretPath` should be a string to a file not checked into the nix store.

        If actually want to encrypt a file in the nix store, need to use string interpolation `"${secretPath}"`.
      '';


  # unecryptedSecretName ? "$2"

  /**
    Decrypt an `age` encrypted `tar.gz` file.
  */
  ageDecryptTarGzSh = {ageEncryptedFilePath ? "$1", ageArgOptions ? "$2"}:
    pkgs.writeScript "age_decrypt_tar_gz.sh" ''
      #!/bin/sh

      AGE_ENCRYPTED_FILE_PATH=${ageEncryptedFilePath}
      AGE_ENCRYPTED_TAR_GZ_FILE_NAME=''${AGE_ENCRYPTED_FILE_PATH##*/} #
      TAR_GZ_FILE_NAME=''${AGE_ENCRYPTED_TAR_GZ_FILE_NAME%.age}

      age -d ${ageArgOptions} ${ageEncryptedFilePath} > $TAR_GZ_FILE_NAME
      tar -xvzf $TAR_GZ_FILE_NAME
      rm $TAR_GZ_FILE_NAME
    '';
in
{
  bin = {
    ageEncryptTarGz = pkgs.writeShellScriptBin "utility_encryption_age_encrypt_tar_gz" ''
      #!/bin/sh

      exec ${ageEncryptTarGzSh {}} $1 $2 $3
    '';

    ageDecryptTarGz = pkgs.writeShellScriptBin "utility_encryption_age_decrypt_tar_gz" ''
      #!/bin/sh

      exec ${ageDecryptTarGzSh {}} $1 $2
    '';
  };


  derivation = pkgs.stdenv.mkDerivation {
    name = "age_utility";
    src = ./.;
    installPhase = ''
      mkdir $out

      cp ${ageEncryptTarGzSh {}} $out/age_encrypt_tar_gz.sh
      cp ${ageDecryptTarGzSh {}} $out/age_decrypt_tar_gz.sh
    '';
  };


  scripts = {
    inherit ageEncryptTarGzSh;
    inherit ageDecryptTarGzSh;
  };



}
