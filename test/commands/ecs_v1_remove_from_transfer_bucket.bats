#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "ecs remove-from-transfer-bucket prints usage with no arguments" {
  run --separate-stderr run_command bin/ecs/v1/remove-from-transfer-bucket
  assert_failure 1
  assert_stderr_contains "Usage: remove-from-transfer-bucket"
  assert_output_contains "-s <source>"
}

@test "ecs remove-from-transfer-bucket requires a source" {
  run --separate-stderr run_command bin/ecs/v1/remove-from-transfer-bucket -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: remove-from-transfer-bucket"
  refute_stub_called_with "s3 rm"
}

@test "ecs remove-from-transfer-bucket deletes exactly the given key from the infrastructure/environment bucket" {
  run run_command bin/ecs/v1/remove-from-transfer-bucket -i "example-infra" -e "staging" -s "uploads/example-file.jpg"
  assert_success
  assert_stub_called_with "s3 rm s3://example-infra-ecs-staging-dalmatian-transfer/uploads/example-file.jpg"
  # No -r given: nothing about the call should ask for recursive deletion,
  # which is what would let a single `s3 rm` sweep an entire prefix
  refute_stub_called_with "--recursive"
}

@test "ecs remove-from-transfer-bucket only adds --recursive when -r is given" {
  run run_command bin/ecs/v1/remove-from-transfer-bucket -i "example-infra" -e "staging" -s "uploads/example-dir" -r
  assert_success
  assert_stub_called_with "s3 rm s3://example-infra-ecs-staging-dalmatian-transfer/uploads/example-dir --recursive"
}

@test "ecs remove-from-transfer-bucket scopes the bucket name to the given infrastructure and environment" {
  run run_command bin/ecs/v1/remove-from-transfer-bucket -i "other-infra" -e "prod" -s "uploads/example-file.jpg"
  assert_success
  assert_stub_called_with "s3 rm s3://other-infra-ecs-prod-dalmatian-transfer/uploads/example-file.jpg"
}

@test "ecs remove-from-transfer-bucket propagates a failing S3 delete" {
  stub_exit aws-s3-rm 1

  run run_command bin/ecs/v1/remove-from-transfer-bucket -i "example-infra" -e "staging" -s "uploads/example-file.jpg"
  assert_failure 1
}
