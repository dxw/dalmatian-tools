#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

teardown() {
  # The default -d directory lives under the real /tmp (not the sandbox HOME),
  # so any test that exercises the default clears up after itself here.
  rm -rf "/tmp/example-infra-example-service-staging-cloudfront-logs"
}

@test "logs prints usage with no arguments" {
  run --separate-stderr run_command bin/cloudfront/v1/logs
  assert_failure 1
  assert_stderr_contains "Usage: logs"
  assert_output_contains "-s <service_name>"
}

@test "logs requires a service name" {
  run --separate-stderr run_command bin/cloudfront/v1/logs -i example-infra -e staging
  assert_failure 1
  assert_stderr_contains "Usage: logs"
}

@test "logs -h shows usage" {
  run --separate-stderr run_command bin/cloudfront/v1/logs -h
  assert_failure 1
  assert_stderr_contains "Usage: logs"
}

@test "logs defaults the download directory to /tmp/<infra>-<service>-<env>-cloudfront-logs" {
  QUIET_MODE=0 run run_command bin/cloudfront/v1/logs -i example-infra -e staging -s example-service
  assert_success
  assert_stub_called_with "s3 sync s3://example-infra-example-service-staging-cloudfront-logs/ /tmp/example-infra-example-service-staging-cloudfront-logs"
  assert_output_contains "logs in /tmp/example-infra-example-service-staging-cloudfront-logs"
  [ -d "/tmp/example-infra-example-service-staging-cloudfront-logs" ]
}

@test "logs -d overrides the download directory and it gets created" {
  run run_command bin/cloudfront/v1/logs -i example-infra -e staging -s example-service -d "$SANDBOX/custom-logs"
  assert_success
  assert_stub_called_with "s3 sync s3://example-infra-example-service-staging-cloudfront-logs/ $SANDBOX/custom-logs"
  [ -d "$SANDBOX/custom-logs" ]
}

@test "logs -p filters the sync with an --exclude/--include pattern pair" {
  run run_command bin/cloudfront/v1/logs -i example-infra -e staging -s example-service -d "$SANDBOX/custom-logs" -p "2026-08-27"
  assert_success
  assert_stub_called_with 's3 sync s3://example-infra-example-service-staging-cloudfront-logs/ '"$SANDBOX"'/custom-logs --exclude * --include *2026-08-27*'
}

@test "logs without -p syncs the whole bucket with no --exclude/--include" {
  run run_command bin/cloudfront/v1/logs -i example-infra -e staging -s example-service -d "$SANDBOX/custom-logs"
  assert_success
  refute_stub_called_with "--exclude"
}
