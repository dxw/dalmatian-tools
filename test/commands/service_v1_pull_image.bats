#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1

  # The script's only unstubbed dependency is `docker` (login/pull); every
  # other command it runs (aws) is already faked by use_stubs via
  # test/stubs/_dispatch. Symlinking `docker` at the same stub adds it to the
  # same call log / response mechanism without touching test/stubs itself.
  ln -sfn "$DALMATIAN_ROOT/test/stubs/_dispatch" "$SANDBOX/bin/docker"

  stub_response_file aws-ecr-describe_repositories service-deploy-ecr-describe-repositories.json
}

@test "pull-image prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/pull-image
  assert_failure 1
  assert_stderr_contains "Usage: pull-image"
  assert_output_contains "-i <infrastructure>"
}

@test "pull-image -h shows usage" {
  run --separate-stderr run_command bin/service/v1/pull-image -h
  assert_failure 1
  assert_stderr_contains "Usage: pull-image"
}

@test "pull-image requires infrastructure, service and environment" {
  run --separate-stderr run_command bin/service/v1/pull-image -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Usage: pull-image"
  refute_stub_called_with "docker pull"
}

@test "pull-image looks up the repository built from -i/-s/-e, logs in and pulls it" {
  run run_command bin/service/v1/pull-image -i example-infra -s example-service -e staging
  assert_success
  assert_stub_called_with "ecr describe-repositories --repository-name example-infra-example-service-staging"
  assert_stub_called_with "docker login --username AWS --password-stdin 123456789012.dkr.ecr.eu-west-2.amazonaws.com"
  assert_stub_called_with "docker pull 123456789012.dkr.ecr.eu-west-2.amazonaws.com/example-infra-example-service-staging"
}

@test "pull-image propagates a failing describe-repositories call and never pulls" {
  stub_exit aws-ecr-describe_repositories 1

  run --separate-stderr run_command bin/service/v1/pull-image -i example-infra -s example-service -e staging
  assert_failure
  refute_stub_called_with "docker pull"
}

@test "pull-image propagates a failing docker login and never pulls" {
  stub_exit docker-login 1

  run --separate-stderr run_command bin/service/v1/pull-image -i example-infra -s example-service -e staging
  assert_failure
  refute_stub_called_with "docker pull"
}

@test "pull-image indents docker's pull output by two spaces" {
  stub_response docker-pull "Pulling from example-infra-example-service-staging"

  run run_command bin/service/v1/pull-image -i example-infra -s example-service -e staging
  assert_success
  assert_output_contains "  Pulling from example-infra-example-service-staging"
}
