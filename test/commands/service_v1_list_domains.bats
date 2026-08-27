#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-cloudfront-list_distributions service-deploy-cloudfront-list-distributions.json
}

@test "list-domains prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/list-domains
  assert_failure 1
  assert_stderr_contains "Usage: list-domains"
  assert_output_contains "-i <infrastructure>"
}

@test "list-domains -h shows usage" {
  run --separate-stderr run_command bin/service/v1/list-domains -h
  assert_failure 1
  assert_stderr_contains "Usage: list-domains"
}

@test "list-domains requires infrastructure, service and environment" {
  run --separate-stderr run_command bin/service/v1/list-domains -i example-infra -s example-service
  assert_failure 1
  assert_stderr_contains "Usage: list-domains"
}

@test "list-domains finds the CloudFront domain and aliases for the origin built from -i/-s/-e" {
  run run_command bin/service/v1/list-domains -i example-infra -s example-service -e staging
  assert_success
  assert_output_contains "d111111abcdef8.cloudfront.net"
  assert_output_contains "example.com"
  assert_output_contains "www.example.com"
  refute_output_line "d222222abcdef8.cloudfront.net"
}

@test "list-domains prints nothing, and still exits 0, when no distribution matches" {
  run run_command bin/service/v1/list-domains -i example-infra -s example-service -e prod
  assert_success
  assert_output ""
}

@test "list-domains propagates a failing list-distributions call" {
  stub_exit aws-cloudfront-list_distributions 1

  run --separate-stderr run_command bin/service/v1/list-domains -i example-infra -s example-service -e staging
  assert_failure
}
