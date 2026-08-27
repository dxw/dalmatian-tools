#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=0
}

@test "set-environment-variable prints usage with no arguments" {
  run --separate-stderr run_command bin/service/v1/set-environment-variable
  assert_failure 1
  assert_stderr_contains "Usage: set-environment-variable"
  assert_output_contains "-v <value>"
}

@test "set-environment-variable requires -k and -v when no -E is given" {
  run --separate-stderr run_command bin/service/v1/set-environment-variable \
    -i example-infra -s example-service -e staging
  assert_failure 1
  assert_stderr_contains "Usage: set-environment-variable"
  refute_stub_called_with "put-parameter"
}

@test "set-environment-variable rejects a key that does not start with a letter" {
  run --separate-stderr run_command bin/service/v1/set-environment-variable \
    -i example-infra -s example-service -e staging -k 1PORT -v 25
  assert_failure 1
  assert_stderr_contains "keys must start with an alphabetical"
  refute_stub_called_with "put-parameter"
}

@test "set-environment-variable builds the parameter path, key alias and value from -i/-s/-e/-k/-v" {
  run run_command bin/service/v1/set-environment-variable \
    -i example-infra -s example-service -e staging -k SMTP_HOST -v smtp.example.org
  assert_success
  assert_stub_called_with "--name /example-infra/example-service/staging/SMTP_HOST"
  assert_stub_called_with "--value smtp.example.org"
  assert_stub_called_with "--key-id alias/example-infra-example-service-staging-ssm"
  assert_stub_called_with "--type SecureString"
  assert_stub_called_with "--overwrite"
}

@test "set-environment-variable logs what it is setting when not quiet" {
  run run_command bin/service/v1/set-environment-variable \
    -i example-infra -s example-service -e staging -k SMTP_HOST -v smtp.example.org
  assert_success
  assert_output_contains "setting environment variable SMTP_HOST for example-infra/example-service/staging"
}

@test "set-environment-variable fails when the AWS call fails" {
  stub_exit aws-ssm-put_parameter 254

  run run_command bin/service/v1/set-environment-variable \
    -i example-infra -s example-service -e staging -k SMTP_HOST -v smtp.example.org
  assert_failure
}

# FINDING: -E alone (no -k) can never pass validation. The key-format check
# at line 91 runs unconditionally against the *global* $KEY before the
# ENV_FILE branch even looks at it, and $KEY is unset when only -E was given,
# so `[[ ! "$KEY" =~ ^[a-zA-Z] ]]` is true for an empty string and usage()
# fires. A placeholder -k (any letter-led string; it is overwritten per line
# from the file) is required to reach the file-reading code at all.
@test "set-environment-variable -E alone fails validation before the file is ever read" {
  local env_file="$SANDBOX/service-v1-envfile.env"
  printf 'SMTP_HOST=smtp.example.org\n' > "$env_file"

  run --separate-stderr run_command bin/service/v1/set-environment-variable \
    -i example-infra -s example-service -e staging -E "$env_file"
  assert_failure 1
  assert_stderr_contains "keys must start with an alphabetical"
  refute_stub_called_with "put-parameter"
}

@test "set-environment-variable -E with a placeholder -k sets every key=value line in the file" {
  local env_file="$SANDBOX/service-v1-envfile.env"
  printf 'SMTP_HOST=smtp.example.org\nSMTP_PORT=25\n' > "$env_file"

  run run_command bin/service/v1/set-environment-variable \
    -i example-infra -s example-service -e staging -k placeholder -E "$env_file"
  assert_success
  assert_stub_called_with "--name /example-infra/example-service/staging/SMTP_HOST --value smtp.example.org"
  assert_stub_called_with "--name /example-infra/example-service/staging/SMTP_PORT --value 25"
}

@test "set-environment-variable -E strips a single leading/trailing quote and keeps embedded '=' in the value" {
  local env_file="$SANDBOX/service-v1-envfile-quoted.env"
  printf "TOKEN='abc=def=='\n" > "$env_file"

  run run_command bin/service/v1/set-environment-variable \
    -i example-infra -s example-service -e staging -k placeholder -E "$env_file"
  assert_success
  assert_stub_called_with "--name /example-infra/example-service/staging/TOKEN --value abc=def=="
}

@test "set-environment-variable errors when the given -E file does not exist" {
  run --separate-stderr run_command bin/service/v1/set-environment-variable \
    -i example-infra -s example-service -e staging -k placeholder -E "$SANDBOX/service-v1-missing.env"
  assert_failure 1
  assert_stderr_contains "does not exist"
  refute_stub_called_with "put-parameter"
}
