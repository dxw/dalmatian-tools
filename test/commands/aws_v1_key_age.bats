#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  export AWS_CALLER_IDENTITY_USERNAME="example-user"
}

@test "key-age -h prints usage to stdout" {
  # Like awscli-version, this usage() has no \`1>&2\` redirection at all.
  run --separate-stderr run_command bin/aws/v1/key-age -h
  assert_failure 1
  assert_output_contains "Check the age of your AWS access key"
  [ -z "$stderr" ] || fail "expected no stderr output, got: $stderr"
}

@test "key-age refuses to run when AWS SSO is configured" {
  login_sandbox

  run --separate-stderr run_command bin/aws/v1/key-age
  assert_failure 1
  assert_stderr_contains "Access key rotation does not apply when Dalmatian is signing in with AWS SSO"
}

@test "key-age errors when the user has no access keys" {
  stub_response aws-iam-list_access_keys '{"AccessKeyMetadata": []}'

  run --separate-stderr run_command bin/aws/v1/key-age
  assert_failure 1
  assert_stderr_contains "No Access Keys were found for user 'example-user'"
}

@test "key-age prompts for a username when none is set" {
  unset AWS_CALLER_IDENTITY_USERNAME
  stub_response aws-iam-list_access_keys '{"AccessKeyMetadata": []}'

  run --separate-stderr run_command bin/aws/v1/key-age <<< "example-user"
  assert_failure 1
  assert_stderr_contains "No Access Keys were found for user 'example-user'"
  assert_stub_called_with "iam list-access-keys --user-name example-user"
}

@test "key-age reports the age of an old access key and warns about rotation" {
  # 2000-01-01 is used because it is guaranteed to stay more than 180 days in
  # the past for the lifetime of this test suite, so the "should be rotated"
  # branch cannot flip due to the real clock moving on. The exact age is
  # computed here with the same \`gdate\` arithmetic the script itself uses,
  # rather than a hardcoded day count, so the assertion does not go stale.
  stub_response_file aws-iam-list_access_keys aws-cmd-key-age-old-key.json

  local now create_epoch expected_age
  now=$(gdate +%s)
  create_epoch=$(gdate -d "2000-01-01T00:00:00Z" +%s)
  expected_age=$(( (now - create_epoch) / 86400 ))

  run --separate-stderr run_command bin/aws/v1/key-age
  assert_success
  assert_output_contains "Access key ID: AKIAEXAMPLE1234567890"
  assert_output_contains "Created on: 2000-01-01"
  assert_output_contains "Age in days: $expected_age"
  assert_stderr_contains "Access key is more than 180 days old and should be rotated."
}

@test "key-age does not warn about a recently created access key" {
  local recent
  recent=$(gdate -u -d '-10 days' '+%Y-%m-%dT%H:%M:%SZ')
  stub_response aws-iam-list_access_keys <<RESPONSE
{"AccessKeyMetadata": [{"AccessKeyId": "AKIAEXAMPLE0000000000", "CreateDate": "$recent"}]}
RESPONSE

  run --separate-stderr run_command bin/aws/v1/key-age
  assert_success
  assert_output_contains "Age in days: 10"
  [ -z "$stderr" ] || fail "expected no rotation warning, got stderr: $stderr"
}
