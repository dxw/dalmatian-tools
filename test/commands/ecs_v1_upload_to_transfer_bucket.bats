#!/usr/bin/env bats

load ../test_helper

# Pins the S3 key's `$(date +%Y-%m-%d)` component to a known value so the
# constructed S3 key can be asserted on exactly. $SANDBOX/bin is first on
# PATH (use_stubs put it there), so this shim shadows the real `date`. The
# other half of PREFIX_DIR is `$HOSTNAME`, which is left alone -- tests match
# on the date-and-onward suffix of the key rather than the whole thing.
fake_date() {
  printf '#!/usr/bin/env bash\necho 2026-01-01\n' > "$SANDBOX/bin/date"
  chmod +x "$SANDBOX/bin/date"
}

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "ecs upload-to-transfer-bucket prints usage with no arguments" {
  run --separate-stderr run_command bin/ecs/v1/upload-to-transfer-bucket
  assert_failure 1
  assert_stderr_contains "Usage: upload-to-transfer-bucket"
  assert_output_contains "-s <source>"
}

@test "ecs upload-to-transfer-bucket requires a source" {
  run --separate-stderr run_command bin/ecs/v1/upload-to-transfer-bucket -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: upload-to-transfer-bucket"
  refute_stub_called_with "s3 cp"
}

@test "ecs upload-to-transfer-bucket copies the source into the infrastructure/environment bucket, dated" {
  fake_date

  run run_command bin/ecs/v1/upload-to-transfer-bucket -i "example-infra" -e "staging" -s "/local/example-file.jpg"
  assert_success
  assert_stub_called_with "s3 cp /local/example-file.jpg s3://example-infra-ecs-staging-dalmatian-transfer/"
  assert_stub_called_with "-2026-01-01/example-file.jpg"
  refute_stub_called_with "--recursive"
}

@test "ecs upload-to-transfer-bucket only adds --recursive when -r is given" {
  fake_date

  run run_command bin/ecs/v1/upload-to-transfer-bucket -i "example-infra" -e "staging" -s "/local/example-dir" -r
  assert_success
  assert_stub_called_with "s3 cp /local/example-dir"
  assert_stub_called_with "--recursive"
}

@test "ecs upload-to-transfer-bucket prints the download command for the exact key it just uploaded" {
  fake_date

  run run_command bin/ecs/v1/upload-to-transfer-bucket -i "example-infra" -e "staging" -s "/local/example-file.jpg"
  assert_success
  assert_output_contains "aws s3 cp s3://example-infra-ecs-staging-dalmatian-transfer/"
  assert_output_contains "-2026-01-01/example-file.jpg .  to download the file(s)"
}

@test "ecs upload-to-transfer-bucket propagates a failing S3 copy" {
  stub_exit aws-s3-cp 1

  run run_command bin/ecs/v1/upload-to-transfer-bucket -i "example-infra" -e "staging" -s "/local/example-file.jpg"
  assert_failure 1
}
