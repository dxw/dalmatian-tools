#!/usr/bin/env bats

load ../test_helper

# cloudfront/v2/clear-cache is the v2 counterpart of cloudfront/v1/clear-cache.
# It makes no direct `aws` calls -- everything goes through
# "$APP_ROOT/bin/dalmatian" aws run-command, so stub_cli is what fakes the CLI
# it shells back into. Divergences from v1 documented per-test below.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  # FINDING: unlike other v2 commands (e.g. bin/s3/v2/list-bucket-properties),
  # this script's dalmatian_aws() helper shells out to a bare `dalmatian`
  # rather than "$APP_ROOT/bin/dalmatian", so it ignores DALMATIAN_TEST_APP_ROOT
  # entirely and would otherwise resolve via PATH to whatever real dalmatian is
  # installed on this machine. Putting stub_cli's bin directory on PATH ahead
  # of everything else is what makes it reachable here.
  export PATH="$SANDBOX/cli/bin:$PATH"

  stub_response_file dalmatian-aws-run_command-i-example_infra-e-staging-cloudfront-list_distributions \
    cdn-cf-distributions-v2.json
  stub_response 'dalmatian-aws-run_command-i-example_infra-e-staging-cloudfront-create_invalidation-distribution_id-E1EXAMPLE123-paths-__' \
    '{"Invalidation": {"Id": "INVEXAMPLE1"}}'
}

@test "clear-cache prints usage with no arguments" {
  run --separate-stderr run_command bin/cloudfront/v2/clear-cache
  assert_failure 1
  assert_stderr_contains "Usage: clear-cache"
  assert_output_contains "-i <infrastructure>"
}

@test "clear-cache requires a service name" {
  run --separate-stderr run_command bin/cloudfront/v2/clear-cache -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Usage: clear-cache"
}

@test "clear-cache -h shows usage" {
  run --separate-stderr run_command bin/cloudfront/v2/clear-cache -h
  assert_failure 1
  assert_stderr_contains "Usage: clear-cache"
}

# DIVERGENCE: v1 matches origin id "<infra>-<service>-<env>-default-origin";
# v2 matches just "<service>-default" -- infra and environment are dropped
# from the match entirely. The v2 fixture's decoy distribution
# ("other-service-default") proves only the service-scoped match fires.
@test "clear-cache invalidates exactly the distribution matching <service>-default, not the decoy" {
  run run_command bin/cloudfront/v2/clear-cache -i example-infra -e staging -s example-service
  assert_success
  assert_stub_called_with "cloudfront create-invalidation --distribution-id E1EXAMPLE123 --paths /*"
  refute_stub_called_with "E2DECOY456"
}

# DIVERGENCE: v2 waits for completion via the AWS CLI's own
# `cloudfront wait invalidation-completed`, using the invalidation id from the
# create-invalidation response -- v1 instead hand-rolls a get-invalidation
# polling loop with `sleep 3`. Confirms the id is threaded through correctly.
@test "clear-cache waits on the invalidation id returned by create-invalidation" {
  run run_command bin/cloudfront/v2/clear-cache -i example-infra -e staging -s example-service
  assert_success
  assert_stub_called_with "cloudfront wait invalidation-completed --distribution-id E1EXAMPLE123 --id INVEXAMPLE1"
  assert_output_contains "Invalidation completed."
}

@test "clear-cache -P sends a custom, space-separated path list" {
  stub_response 'dalmatian-aws-run_command-i-example_infra-e-staging-cloudfront-create_invalidation-distribution_id-E1EXAMPLE123-paths-_foo____bar__' \
    '{"Invalidation": {"Id": "INVEXAMPLE1"}}'

  run run_command bin/cloudfront/v2/clear-cache -i example-infra -e staging -s example-service -P "/foo/* /bar/*"
  assert_success
  assert_stub_called_with "cloudfront create-invalidation --distribution-id E1EXAMPLE123 --paths /foo/* /bar/*"
}

# DIVERGENCE: unlike v1 (which has no such guard, see cloudfront_v1_clear_cache.bats),
# v2 explicitly checks for an empty/null DISTRIBUTION and refuses to proceed.
@test "clear-cache refuses to invalidate anything when no distribution matches the service" {
  run --separate-stderr run_command bin/cloudfront/v2/clear-cache -i example-infra -e staging -s no-such-service
  assert_failure 1
  assert_stderr_contains "Could not find distribution with origin ID: no-such-service-default"
  refute_stub_called_with "create-invalidation"
}

# FINDING (divergence from v1's `log_info -l "..." -q "$QUIET_MODE"`): every
# log_info call in v2 clear-cache omits `-q`, and log_info defaults QUIET_MODE
# to 0 internally when the flag is absent -- so these lines print even when
# the caller asked for quiet mode, unlike v1's equivalent calls.
@test "clear-cache logs 'Finding CloudFront distribution...' even when QUIET_MODE=1" {
  run run_command bin/cloudfront/v2/clear-cache -i example-infra -e staging -s example-service
  assert_success
  assert_output_contains "Finding CloudFront distribution..."
}

# FINDING: line 64 calls `dalmatian_aws cloudfront list-distributions` once
# with its output going straight to the script's stdout (not captured), then
# line 65 calls it again to actually capture $DISTRIBUTIONS. The first,
# discarded call means the raw distributions JSON is dumped to the user's
# terminal on every run, and the AWS API is queried twice for no reason.
@test "clear-cache leaks the raw list-distributions JSON to stdout via the uncaptured duplicate call" {
  run run_command bin/cloudfront/v2/clear-cache -i example-infra -e staging -s example-service
  assert_success
  assert_output_contains "d111111abcdef8.cloudfront.net"
}
