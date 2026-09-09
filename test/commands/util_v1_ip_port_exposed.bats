#!/usr/bin/env bats
#
# shellcheck disable=SC2030,SC2031
# Each @test block is a shellcheck-visible function, so `export QUIET_MODE=0`
# inside one looks like a subshell-local change that could be "lost". bats
# runs each @test as its own invocation, so the export is read back within
# the same test that set it -- shellcheck just can't see that the boundary
# is a test, not a subshell escape.

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
}

teardown() {
  # The script under test writes its scratch file to a real, unsandboxed
  # /tmp/<epoch-seconds>.exposed_ports.txt and never cleans it up. That is a
  # side effect of the production script (see findings), not something to fix
  # here, but the test run shouldn't litter the host's /tmp permanently.
  rm -f /tmp/*.exposed_ports.txt
}

@test "util ip-port-exposed prints usage and exits 1 with no arguments" {
  run --separate-stderr run_command bin/util/v1/ip-port-exposed
  assert_failure 1
  assert_stderr_contains "Usage: ip-port-exposed"
}

@test "util ip-port-exposed prints usage and exits 1 with -h" {
  run --separate-stderr run_command bin/util/v1/ip-port-exposed -h
  assert_failure 1
  assert_stderr_contains "Usage: ip-port-exposed"
  assert_output_contains "-i <infrastructure>"
}

@test "util ip-port-exposed requires -i to have a value" {
  run --separate-stderr run_command bin/util/v1/ip-port-exposed -i
  assert_failure 1
  assert_stderr_contains "Usage: ip-port-exposed"
}

@test "util ip-port-exposed reports exposed ports outside 80/443" {
  export QUIET_MODE=0
  stub_response_file aws-ec2-describe_security_groups util-v1-exposed-ports-with-ssh.json

  run run_command bin/util/v1/ip-port-exposed -i example-infra
  assert_success
  assert_output_contains "Exposed port found!"
  assert_output_contains "sg-2 ssh-sg 22 22 0.0.0.0/0"
}

@test "util ip-port-exposed reports no exposed ports when only 80/443 are open" {
  export QUIET_MODE=0
  stub_response_file aws-ec2-describe_security_groups util-v1-exposed-ports-safe.json

  run run_command bin/util/v1/ip-port-exposed -i example-infra
  assert_success
  assert_output_contains "No exposed ports found!"
  refute_output_line "sg-1 web-sg 80 80 0.0.0.0/0"
}

@test "util ip-port-exposed prints nothing at all when quiet and safe" {
  # With QUIET_MODE left at its default (1) and no exposed port to report,
  # every log_info call is suppressed and grep finds nothing to print either.
  stub_response_file aws-ec2-describe_security_groups util-v1-exposed-ports-safe.json

  run run_command bin/util/v1/ip-port-exposed -i example-infra
  assert_success
  assert_output ""
}

@test "util ip-port-exposed builds the query with the 0.0.0.0/0 filter" {
  stub_response_file aws-ec2-describe_security_groups util-v1-exposed-ports-safe.json

  run run_command bin/util/v1/ip-port-exposed -i example-infra
  assert_success
  assert_stub_called_with "0.0.0.0/0"
  assert_stub_called_with "describe-security-groups"
}

@test "util ip-port-exposed does not filter the AWS call by infrastructure name" {
  # -i is required by usage() and appears in the log message, but the value
  # is never passed to the aws CLI call (no --profile, no query parameter
  # referencing it) -- an infrastructure that does not exist behaves
  # identically to one that does.
  export QUIET_MODE=0
  stub_response_file aws-ec2-describe_security_groups util-v1-exposed-ports-with-ssh.json

  run run_command bin/util/v1/ip-port-exposed -i does-not-exist
  assert_success
  assert_output_contains "Exposed port found!"
}

@test "util ip-port-exposed logs progress unless QUIET_MODE is set" {
  export QUIET_MODE=0
  stub_response_file aws-ec2-describe_security_groups util-v1-exposed-ports-safe.json

  run run_command bin/util/v1/ip-port-exposed -i example-infra
  assert_success
  assert_output_contains "Searching ..."
  assert_output_contains "Finished!"
}
