#!/usr/bin/env bats

load ../test_helper

# Pins the S3 key's `$(gdate +%s)` prefix directory to a known value so the
# constructed S3 key can be asserted on exactly. $SANDBOX/bin is first on
# PATH (use_stubs put it there), so this shim shadows both the real `gdate`
# and the passthrough shim use_stubs installs when `gdate` is missing.
fake_gdate_epoch() {
  printf '#!/usr/bin/env bash\necho 1700000000\n' > "$SANDBOX/bin/gdate"
  chmod +x "$SANDBOX/bin/gdate"
}

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

@test "ecs file-upload prints usage with no arguments" {
  run --separate-stderr run_command bin/ecs/v1/file-upload
  assert_failure 1
  assert_stderr_contains "Usage: file-upload"
  assert_output_contains "-t <host_target>"
}

@test "ecs file-upload requires a host target" {
  run --separate-stderr run_command bin/ecs/v1/file-upload -i "example-infra" -e "staging" -s "/local/example-file.jpg"
  assert_failure 1
  assert_stderr_contains "Usage: file-upload"
}

@test "ecs file-upload copies to S3 then downloads to the explicitly given instance" {
  fake_gdate_epoch

  run run_command bin/ecs/v1/file-upload -i "example-infra" -e "staging" -I "i-0123456789abcdef0" -s "/local/example-file.jpg" -t "/var/www/example-file.jpg"
  assert_success
  assert_stub_called_with "s3 cp /local/example-file.jpg s3://example-infra-ecs-staging-dalmatian-transfer/1700000000/example-file.jpg"
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0 --document-name example-infra-staging-s3-download --parameters Source=s3://example-infra-ecs-staging-dalmatian-transfer/1700000000/example-file.jpg,HostTarget=/var/www/example-file.jpg,Recursive=--ignore-glacier-warnings"
  assert_stub_called_with "s3 rm s3://example-infra-ecs-staging-dalmatian-transfer/1700000000/example-file.jpg"
  # An explicit -I is given, so the picker helper (and its `aws ec2
  # describe-instances` call) must never run
  refute_stub_called_with "describe-instances"
}

@test "ecs file-upload -r passes --recursive through to the S3 copy/remove and the SSM document" {
  fake_gdate_epoch

  run run_command bin/ecs/v1/file-upload -i "example-infra" -e "staging" -I "i-0123456789abcdef0" -s "/local/example-dir" -t "/var/www/example-dir" -r
  assert_success
  assert_stub_called_with "s3 cp /local/example-dir s3://example-infra-ecs-staging-dalmatian-transfer/1700000000/example-dir --recursive"
  assert_stub_called_with "Recursive=--recursive"
  assert_stub_called_with "s3 rm s3://example-infra-ecs-staging-dalmatian-transfer/1700000000/example-dir --recursive"
}

@test "ecs file-upload picks an instance via pick_ecs_instance when -I is omitted" {
  fake_gdate_epoch
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json

  run run_command bin/ecs/v1/file-upload -i "example-infra" -e "staging" -s "/local/example-file.jpg" -t "/var/www/example-file.jpg"
  assert_success
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
}

@test "ecs file-upload fails without the session-manager-plugin" {
  local original_path="$PATH"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"

  run --separate-stderr run_command bin/ecs/v1/file-upload -i "example-infra" -e "staging" -I "i-0123456789abcdef0" -s "/local/example-file.jpg" -t "/var/www/example-file.jpg"

  PATH="$original_path"

  assert_failure 1
  assert_stderr_contains "requires the \`session-manager-plugin\` to be installed"
}

@test "ecs file-upload does not touch S3 or SSM when validation fails" {
  run --separate-stderr run_command bin/ecs/v1/file-upload -i "example-infra" -e "staging"
  assert_failure 1
  refute_stub_called_with "s3 cp"
  refute_stub_called_with "ssm start-session"
}
