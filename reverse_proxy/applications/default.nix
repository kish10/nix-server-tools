let
  mkApplicationSet = createComposeFileNix:
    {
      dockerComposeFile = createComposeFileNix;
    };
in
{
  organization = {
    paperlessngx = ./organization/paperless_ngx/create-files--for-paperless-ngx.nix;
  };

  testExamples = {
    helloTestApp = mkApplicationSet ./test_examples/hello_test_app/create_docker_compose_for_hello_test_app.nix;
  };
}
