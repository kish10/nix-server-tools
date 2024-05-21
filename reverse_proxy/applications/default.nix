let
  mkApplicationSet = createComposeFileNix:
    {
      dockerComposeFile = createComposeFileNix;
    };
in
{
  organization = {
    bookmarkManagement = {
      shiori = ./organization/bookmark_management/shiori/create-files--for-shiori.nix;
    };

    dataManagement = {
      nocodb = ./organization/data_management/nocodb/create-files--for-nocodb.nix;
    };

    documentManagement = {
      paperlessngx = ./organization/document_management/paperless_ngx/create-files--for-paperless-ngx.nix;
    };

    mediaManagement = {
      immich = ./organization/media_management/immich/create-files--for-immich.nix;
    };

    projectManagement = {
      vikunja = ./organization/project_management/vikunja/create-files--for-vikunja.nix;
    };
  };

  testExamples = {
    helloTestApp = mkApplicationSet ./test_examples/hello_test_app/create_docker_compose_for_hello_test_app.nix;
  };
}
