#!/usr/bin/env bats

load ../test_helper

# Pins the S3 key's `$(gdate +%s)` prefix directory to a known value so the
# constructed S3 key can be asserted on exactly, rather than against whatever
# second the test happens to run in. $SANDBOX/bin is first on PATH (use_stubs
# put it there), so this shim shadows both the real `gdate` and the
# passthrough shim use_stubs installs when `gdate` is missing.
fake_gdate_epoch() {
  printf '#!/usr/bin/env bash\necho 1700000000\n' > "$SANDBOX/bin/gdate"
  chmod +x "$SANDBOX/bin/gdate"
}

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json
}

@test "ecs file-download prints usage with no arguments" {
  run --separate-stderr run_command bin/ecs/v1/file-download
  assert_failure 1
  assert_stderr_contains "Usage: file-download"
  assert_output_contains "-t <local target>"
}

@test "ecs file-download requires a local target" {
  run --separate-stderr run_command bin/ecs/v1/file-download -i "example-infra" -e "staging" -s "/wp-uploads/example-file.jpg"
  assert_failure 1
  assert_stderr_contains "Usage: file-download"
}

@test "ecs file-download uploads from the first running instance to S3, then downloads locally" {
  fake_gdate_epoch

  run run_command bin/ecs/v1/file-download -i "example-infra" -e "staging" -s "/wp-uploads/example-file.jpg" -t "/tmp/example-file.jpg"
  assert_success
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0 --document-name example-infra-staging-s3-upload --parameters S3Target=s3://example-infra-ecs-staging-dalmatian-transfer/1700000000/example-file.jpg,Source=/wp-uploads/example-file.jpg,Recursive=--ignore-glacier-warnings"
  assert_stub_called_with "s3 cp s3://example-infra-ecs-staging-dalmatian-transfer/1700000000/example-file.jpg /tmp/example-file.jpg"
  assert_stub_called_with "s3 rm s3://example-infra-ecs-staging-dalmatian-transfer/1700000000/example-file.jpg"
}

@test "ecs file-download connects to an explicitly given instance but still logs the first instance's name" {
  # INSTANCE_NAME is always read from .Reservations[0].Instances[0], not from
  # whichever instance -I actually selected. With the two-instance fixture,
  # picking the *second* instance by id still logs the *first* instance's
  # Name tag in the "uploading from ..." message -- a cosmetic mismatch, but
  # confirms the SSM target itself is still the id that was actually given.
  fake_gdate_epoch

  QUIET_MODE=0 run run_command bin/ecs/v1/file-download -i "example-infra" -e "staging" -I "i-0fedcba987654321f" -s "/wp-uploads/example-file.jpg" -t "/tmp/example-file.jpg"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f"
  assert_output_contains "uploading from 'example-infra-staging-ecs' (id: i-0fedcba987654321f)"
}

@test "ecs file-download -r passes --recursive through to the SSM document and the S3 copy/remove" {
  fake_gdate_epoch

  run run_command bin/ecs/v1/file-download -i "example-infra" -e "staging" -s "/wp-uploads/example-dir" -t "/tmp/example-dir" -r
  assert_success
  assert_stub_called_with "Recursive=--recursive"
  assert_stub_called_with "s3 cp s3://example-infra-ecs-staging-dalmatian-transfer/1700000000/example-dir /tmp/example-dir --recursive"
  assert_stub_called_with "s3 rm s3://example-infra-ecs-staging-dalmatian-transfer/1700000000/example-dir --recursive"
}

@test "ecs file-download crashes with an opaque jq error rather than 'no instances found' on an empty result" {
  # Unlike ec2-access, this script never checks whether any instance was
  # found. INSTANCE_ID would fall back to
  # `.Reservations[0].Instances[0].InstanceId`, which jq -r renders as the
  # literal string "null" on an empty Reservations list and would not itself
  # error -- but INSTANCE_NAME is then computed with `.Tags[]` (no `?`), and
  # iterating over the null Tags of a null Instances[0] is a hard jq error.
  # With `set -e` that aborts the whole script (exit 5) before any SSM
  # session is opened, with no user-facing "no instances found" message at
  # all -- just jq's own stderr text.
  fake_gdate_epoch
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-empty.json

  run --separate-stderr run_command bin/ecs/v1/file-download -i "example-infra" -e "staging" -s "/wp-uploads/example-file.jpg" -t "/tmp/example-file.jpg"
  assert_failure 5
  assert_stderr_contains "Cannot iterate over null"
  refute_stub_called_with "ssm start-session"
}

@test "ecs file-download fails without the session-manager-plugin" {
  local original_path="$PATH"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"

  run --separate-stderr run_command bin/ecs/v1/file-download -i "example-infra" -e "staging" -s "/wp-uploads/example-file.jpg" -t "/tmp/example-file.jpg"

  PATH="$original_path"

  assert_failure 1
  assert_stderr_contains "requires the \`session-manager-plugin\` to be installed"
}
