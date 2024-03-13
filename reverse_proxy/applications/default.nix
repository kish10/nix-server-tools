let
  mkApplicationSet = createComposeFileNix:
    {
      dockerComposeFile = createComposeFileNix;
    };
in
{
  organization = {
    bookmark_manager = {
      shiori = ./organization/bookmark_manager/shiori/create-files--for-shiori.nix;
    };

    document_manager = {
      paperlessngx = ./organization/document_manager/paperless_ngx/create-files--for-paperless-ngx.nix;
    };
  };

  testExamples = {
    helloTestApp = mkApplicationSet ./test_examples/hello_test_app/create_docker_compose_for_hello_test_app.nix;
  };
}
