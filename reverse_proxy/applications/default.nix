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

    documentManagement = {
      paperlessngx = ./organization/document_management/paperless_ngx/create-files--for-paperless-ngx.nix;
    };

    projectManagement = {
      vikunja = ./organization/project_management/vikunja/create-files--for-vikunja.nix;
    };
  };

  testExamples = {
    helloTestApp = mkApplicationSet ./test_examples/hello_test_app/create_docker_compose_for_hello_test_app.nix;
  };
}
