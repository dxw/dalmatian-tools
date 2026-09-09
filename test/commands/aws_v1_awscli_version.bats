#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
}

@test "awscli-version passes with a modern version" {
  stub_response aws-version "aws-cli/2.36.22 Python/3.13.0 Darwin/25.6.0 source/arm64"

  run --separate-stderr run_command bin/aws/v1/awscli-version
  assert_success
  assert_output_contains "Detected AWS CLI version: 2.36.22"
}

@test "awscli-version passes at exactly the 2.9.0 boundary" {
  stub_response aws-version "aws-cli/2.9.0 Python/3.11.6 Linux/5.15.0 exe/x86_64.ubuntu.22"

  run --separate-stderr run_command bin/aws/v1/awscli-version
  assert_success
  assert_output_contains "Detected AWS CLI version: 2.9.0"
}

@test "awscli-version fails on 2.8.x with the upgrade message" {
  stub_response aws-version "aws-cli/2.8.9 Python/3.11.6 Linux/5.15.0 exe/x86_64.ubuntu.22"

  run --separate-stderr run_command bin/aws/v1/awscli-version
  assert_failure 1
  assert_stderr_contains "awscli 2.8.9 is installed, but 2.9 or later is required for dalmatian-tools"
  assert_output_contains "brew upgrade awscli"
}

@test "awscli-version fails on AWS CLI 1 with removal advice" {
  stub_response aws-version "aws-cli/1.18.69 Python/3.7.4 Linux/4.19.0 botocore/1.17.13"

  run --separate-stderr run_command bin/aws/v1/awscli-version
  assert_failure 1
  assert_stderr_contains "awscli version 2 is not installed which is required for dalmatian-tools"
  assert_output_contains "brew remove awscli awscli@1"
  assert_output_contains "brew install awscli"
}

@test "awscli-version fails with an unparseable version string" {
  stub_response aws-version "not a version string"

  run --separate-stderr run_command bin/aws/v1/awscli-version
  assert_failure 1
  assert_stderr_contains "Could not determine the installed awscli version"
}

@test "awscli-version parses a version with trailing components and suffixes" {
  # grep -oE only extracts the leading "aws-cli/x.y.z" token, so trailing
  # platform/exe metadata after it must not affect parsing.
  stub_response aws-version "aws-cli/2.15.30 Python/3.11.6 Linux/5.15.0-1042-aws exe/x86_64.ubuntu.22 prompt/off"

  run --separate-stderr run_command bin/aws/v1/awscli-version
  assert_success
  assert_output_contains "Detected AWS CLI version: 2.15.30"
}

@test "awscli-version quiet mode suppresses the remediation block but not the error" {
  export QUIET_MODE=1
  stub_response aws-version "aws-cli/2.8.9 Python/3.11.6 Linux/5.15.0 exe/x86_64.ubuntu.22"

  run --separate-stderr run_command bin/aws/v1/awscli-version
  assert_failure 1
  assert_stderr_contains "awscli 2.8.9 is installed, but 2.9 or later is required for dalmatian-tools"
  assert_output ""
}

@test "awscli-version fails when the aws cli is not installed" {
  # A plain "system directories only" PATH (as used elsewhere in this suite
  # to hide a single binary) also hides the modern \`bash\` this repo's
  # scripts require via their \`#!/usr/bin/env bash\` shebang, since on this
  # host both bash and aws live in the same Homebrew bin directory. A
  # dedicated directory with only \`bash\` symlinked in keeps the shebang
  # resolvable while still hiding \`aws\`.
  local original_path="$PATH"
  mkdir -p "$SANDBOX/no-aws-bin"
  ln -sfn "$(command -v bash)" "$SANDBOX/no-aws-bin/bash"
  PATH="$SANDBOX/no-aws-bin:/usr/bin:/bin:/usr/sbin:/sbin"

  run --separate-stderr run_command bin/aws/v1/awscli-version

  PATH="$original_path"

  assert_failure 1
  assert_stderr_contains "awscli is not installed"
}

@test "awscli-version -h prints usage to stdout, not stderr" {
  # usage() here has no \`1>&2\` redirection at all, unlike most other
  # commands in this repo, so the whole message lands on stdout.
  stub_response aws-version "aws-cli/2.36.22 Python/3.13.0 Darwin/25.6.0 source/arm64"

  run --separate-stderr run_command bin/aws/v1/awscli-version -h
  assert_failure 1
  assert_output_contains "Check if awscli is installed and compatible with dalmatian-tools"
  [ -z "$stderr" ] || fail "expected no stderr output, got: $stderr"
}
