#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-two.json
}

@test "ecs ec2-access prints usage with no arguments" {
  # usage() sends only its first line to stderr; the option list itself
  # (lines 12-17 of the script) is plain `echo`, so it lands on stdout. That's
  # existing behaviour of the script under test, not something to "fix" here.
  run --separate-stderr run_command bin/ecs/v1/ec2-access
  assert_failure 1
  assert_stderr_contains "Usage: ec2-access"
  assert_output_contains "-i <infrastructure>"
}

@test "ecs ec2-access requires an environment" {
  run --separate-stderr run_command bin/ecs/v1/ec2-access -i "example-infra"
  assert_failure 1
  assert_stderr_contains "Usage: ec2-access"
}

@test "ecs ec2-access requires an infrastructure" {
  run --separate-stderr run_command bin/ecs/v1/ec2-access -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: ec2-access"
}

@test "ecs ec2-access -l lists the instances and connects to none" {
  run run_command bin/ecs/v1/ec2-access -i "example-infra" -e "staging" -l
  assert_success
  assert_output_contains "i-0123456789abcdef0"
  assert_output_contains "i-0fedcba987654321f"
  refute_stub_called_with "ssm start-session"
}

@test "ecs ec2-access filters instances by infrastructure and environment" {
  run run_command bin/ecs/v1/ec2-access -i "example-infra" -e "staging" -l
  assert_success
  assert_stub_called_with "Name=tag:Name,Values=example-infra-staging*"
  assert_stub_called_with "Name=instance-state-code,Values=16"
}

@test "ecs ec2-access connects to the first instance by default" {
  run run_command bin/ecs/v1/ec2-access -i "example-infra" -e "staging"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
}

@test "ecs ec2-access connects to an explicitly given instance" {
  run run_command bin/ecs/v1/ec2-access -i "example-infra" -e "staging" -I "i-0fedcba987654321f"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0fedcba987654321f"
}

@test "ecs ec2-access rejects an instance id that is not running" {
  run --separate-stderr run_command bin/ecs/v1/ec2-access -i "example-infra" -e "staging" -I "i-00000000000000000"
  assert_failure 1
  assert_stderr_contains "was not found or is not running"
}

@test "ecs ec2-access reports when no instances match" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-empty.json

  run --separate-stderr run_command bin/ecs/v1/ec2-access -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "No instances found for Infrastructure 'example-infra' Environment 'staging'"
}

@test "ecs ec2-access accepts an instance whose Name tag is empty" {
  stub_response_file aws-ec2-describe_instances ec2-describe-instances-empty-name.json

  run run_command bin/ecs/v1/ec2-access -i "example-infra" -e "staging" -I "i-0123456789abcdef0"
  assert_success
  assert_stub_called_with "ssm start-session --target i-0123456789abcdef0"
}

@test "ecs ec2-access -c cannot prompt with no terminal" {
  run --separate-stderr run_command bin/ecs/v1/ec2-access -i "example-infra" -e "staging" -c < /dev/null
  assert_failure
  assert_stderr_contains "there is no terminal to choose one with"
}

# session-manager-plugin is checked via `command -v`, which is a PATH lookup,
# not a hash the sandbox otherwise controls. `run VAR=value cmd` only sets the
# variable for bats' own `run` builtin, and run_command is a shell function
# rather than an executable, so neither `run PATH=... run_command ...` nor
# `env PATH=... run_command ...` reaches it. Instead PATH is reassigned in the
# test's own shell (still exported, since it inherited the export attribute
# use_stubs relied on) around the `run` call: `run` forks a subshell that
# inherits it, and run_command's internal `bash -c` inherits it again from
# that subshell. The restricted PATH -- standard system directories only --
# excludes both the stub directory (use_stubs put it first on PATH) and this
# host's real `/opt/homebrew/bin/session-manager-plugin`, confirmed absent by
# `command -v session-manager-plugin` under this same restricted PATH.
@test "ecs ec2-access fails without the session-manager-plugin" {
  local original_path="$PATH"
  PATH="/usr/bin:/bin:/usr/sbin:/sbin"

  run --separate-stderr run_command bin/ecs/v1/ec2-access -i "example-infra" -e "staging"

  PATH="$original_path"

  assert_failure 1
  assert_stderr_contains "requires the \`session-manager-plugin\` to be installed"
}
