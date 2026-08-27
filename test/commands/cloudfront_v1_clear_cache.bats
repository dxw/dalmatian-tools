#!/usr/bin/env bats

load ../test_helper

# cloudfront/v1/clear-cache finds the distribution whose origin id is
# "<infra>-<service>-<env>-default-origin", invalidates it, then polls
# get-invalidation until its Status is "Completed". The fixture has a second,
# decoy distribution so tests can prove the *right* one was targeted.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1

  stub_response_file aws-cloudfront-list_distributions cdn-cf-distributions-v1.json
  stub_response 'aws-cloudfront-create_invalidation' '{"Invalidation": {"Id": "IEXAMPLEINV1"}}'
  stub_response 'aws-cloudfront-get_invalidation' '{"Invalidation": {"Status": "Completed"}}'
}

@test "clear-cache prints usage with no arguments" {
  run --separate-stderr run_command bin/cloudfront/v1/clear-cache
  assert_failure 1
  assert_stderr_contains "Usage: clear-cache"
  assert_output_contains "-i <infrastructure>"
}

@test "clear-cache requires a service name" {
  run --separate-stderr run_command bin/cloudfront/v1/clear-cache -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Usage: clear-cache"
}

@test "clear-cache -h shows usage" {
  run --separate-stderr run_command bin/cloudfront/v1/clear-cache -h
  assert_failure 1
  assert_stderr_contains "Usage: clear-cache"
}

@test "clear-cache invalidates exactly the distribution matching infra-service-env, not the decoy" {
  run run_command bin/cloudfront/v1/clear-cache -i example-infra -e staging -s example-service
  assert_success
  assert_stub_called_with "create-invalidation --distribution-id E1EXAMPLE123 --paths /*"
  refute_stub_called_with "E2DECOY456"
  assert_output_contains "Invalidation Completed"
}

@test "clear-cache -P sends a custom, space-separated path list" {
  run run_command bin/cloudfront/v1/clear-cache -i example-infra -e staging -s example-service -P "/foo/* /bar/*"
  assert_success
  assert_stub_called_with "create-invalidation --distribution-id E1EXAMPLE123 --paths /foo/* /bar/*"
}

# FINDING: unlike cloudfront/v2/clear-cache, this script never checks whether
# a matching distribution was actually found. When no origin matches,
# DISTRIBUTION_ID resolves to an empty string via `jq -r '.Id'` on an empty
# selection (confirmed directly: this exits 0 with no output, it does not
# yield "null"), and the script sails on to call create-invalidation with a
# blank --distribution-id instead of failing.
@test "clear-cache calls create-invalidation with an empty distribution id when no service matches (no not-found guard)" {
  run run_command bin/cloudfront/v1/clear-cache -i example-infra -e staging -s no-such-service
  assert_success
  assert_stub_called_with "create-invalidation --distribution-id  --paths /*"
}
