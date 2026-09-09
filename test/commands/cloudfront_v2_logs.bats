#!/usr/bin/env bats

load ../test_helper

# cloudfront/v2/logs is the v2 counterpart of cloudfront/v1/logs. It makes no
# direct `aws` calls -- it shells out through "$APP_ROOT/bin/dalmatian" aws
# run-command, so stub_cli fakes that CLI. It also calls the real
# resource_prefix_hash function (sourced by run_command like everything else
# in lib/bash-functions), which needs CONFIG_SETUP_JSON_FILE to exist.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  # FINDING: like cloudfront/v2/clear-cache, this script calls a bare
  # `dalmatian` rather than "$APP_ROOT/bin/dalmatian", so it ignores
  # DALMATIAN_TEST_APP_ROOT unless stub_cli's bin directory is put on PATH.
  export PATH="$SANDBOX/cli/bin:$PATH"
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
}

teardown() {
  rm -rf "/tmp/example-infra-example-service-staging-cloudfront-logs"
}

@test "logs prints usage with no arguments" {
  run --separate-stderr run_command bin/cloudfront/v2/logs
  assert_failure 1
  assert_stderr_contains "Usage: logs"
  assert_output_contains "-s <service_name>"
}

@test "logs requires a service name" {
  run --separate-stderr run_command bin/cloudfront/v2/logs -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Usage: logs"
}

@test "logs -h shows usage" {
  run --separate-stderr run_command bin/cloudfront/v2/logs -h
  assert_failure 1
  assert_stderr_contains "Usage: logs"
}

# DIVERGENCE: v1 syncs a dedicated per-service bucket directly
# (s3://<infra>-<service>-<env>-cloudfront-logs/); v2 syncs a shared,
# resource-prefix-hashed account bucket under a per-service key prefix. The
# default *download directory* naming is unchanged from v1, though.
@test "logs syncs from the resource-prefix-hashed bucket and key prefix, into the same default directory as v1" {
  QUIET_MODE=0 run run_command bin/cloudfront/v2/logs -i example-infra -e staging -s example-service
  assert_success
  assert_stub_called_with "s3 sync s3://ccb69c87-logs/cloudfront/infrasructure-ecs-cluster-service/example-service /tmp/example-infra-example-service-staging-cloudfront-logs"
  assert_output_contains "logs in /tmp/example-infra-example-service-staging-cloudfront-logs"
}

# FINDING: the S3 key literally spells "infrasructure" (missing the second
# "t") rather than "infrastructure". This is asserted here as-is because it is
# the real, current behaviour, not a typo in the test.
@test "logs uses the literal (typo'd) infrasructure-ecs-cluster-service path segment" {
  run run_command bin/cloudfront/v2/logs -i example-infra -e staging -s example-service
  assert_success
  assert_stub_called_with "infrasructure-ecs-cluster-service/example-service"
}

@test "logs -d overrides the download directory" {
  run run_command bin/cloudfront/v2/logs -i example-infra -e staging -s example-service -d "$SANDBOX/custom-logs"
  assert_success
  assert_stub_called_with "s3 sync s3://ccb69c87-logs/cloudfront/infrasructure-ecs-cluster-service/example-service $SANDBOX/custom-logs"
  [ -d "$SANDBOX/custom-logs" ]
}

@test "logs -p filters the sync with an --exclude/--include pattern pair" {
  run run_command bin/cloudfront/v2/logs -i example-infra -e staging -s example-service -d "$SANDBOX/custom-logs" -p "2026-08-27"
  assert_success
  assert_stub_called_with "s3 sync s3://ccb69c87-logs/cloudfront/infrasructure-ecs-cluster-service/example-service $SANDBOX/custom-logs --exclude * --include *2026-08-27*"
}

# Contrast with cloudfront/v2/clear-cache: unlike that script, every log_info
# call here does pass "-q $QUIET_MODE", so quiet mode is actually respected.
@test "logs respects QUIET_MODE=1 (no drift here, unlike clear-cache)" {
  run run_command bin/cloudfront/v2/logs -i example-infra -e staging -s example-service -d "$SANDBOX/custom-logs"
  assert_success
  case "$output" in
    *"making sure"*) fail "expected no 'making sure ... exists' log line under QUIET_MODE=1, got: $output" ;;
  esac
}
