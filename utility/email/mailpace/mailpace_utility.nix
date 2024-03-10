{pkgs ? import <nixpkgs> {}}:
let
  sendEmailSh = {mailpaceSecretsEnvFilePath ? "/run/secrets/mailpace_secrets", emailSubject ? "$1", emailTextBody ? "$2"}:
    if builtins.isString mailpaceSecretsEnvFilePath then
      pkgs.writeText "send_email.sh" ''
          #!/bin/sh

          EMAIL_SUBJECT=${emailSubject}
          EMAIL_TEXTBODY=${emailTextBody}

          # Should set the variables: MAILPACE_SERVER_TOKEN, EMAIL_FROM, EMAIL_TO
          source ${mailpaceSecretsEnvFilePath}

          curl "https://app.mailpace.com/api/v1/send" \
          -X POST \
          -H "Accept: application/json" \
          -H "Content-Type: application/json" \
          -H "MailPace-Server-Token: $MAILPACE_SERVER_TOKEN" \
          -d "{
            \"from\": \"$EMAIL_FROM\",
            \"to\": \"$EMAIL_TO\",
            \"subject\": \"$EMAIL_SUBJECT\",
            \"textbody\": \"$EMAIL_TEXTBODY`\"
          }"
        ''
    else
      abort ''
        The `mailpaceSecretsEnvPath` should be a string to a file not checked into the nix store.

        If actually want to encrypt a file in the nix store, need to use string interpolation `"''${mailpaceSecretsEnvPath}"`.
      '';
in
{
  scripts = {
    inherit sendEmailSh;
  };
}
