let
  mkApplicationSet = createComposeFileNix:
    {
      dockerComposeFile = createComposeFileNix;
    };
in
{
  test_examples = {
    hello_test_app = mkApplicationSet ./test_examples/hello_test_app/create_docker_compose_for_hello_test_app.nix;
  };
}
