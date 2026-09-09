#!/usr/bin/env bats
#
# shellcheck disable=SC2030,SC2031
# Each @test block is a shellcheck-visible function, so `export FOO=bar`
# inside one looks like a subshell-local change that could be "lost" by the
# time a later @test reads it. bats runs each @test as its own process
# invocation anyway (via run_command's `bash -c`), so the exports here are
# read back within the same test that set them -- shellcheck just can't see
# that the boundary is a test, not a subshell escape.

load ../test_helper

setup() {
  setup_sandbox
  export QUIET_MODE=1
}

# run_command exports every function from lib/bash-functions via `export -f`,
# and an exported bash function is serialised into the environment as a
# multi-line value (BASH_FUNC_name%%=() { ... }). `env` prints each embedded
# line of that value on its own output line, and several of those function
# bodies mention AWS_* names -- so `env | grep AWS` inside the script under
# test matches plenty of noise beyond the variables a test actually set. That
# makes line-index assertions unreliable; this checks for one exact line
# anywhere in the output instead.
assert_has_exact_line() {
  local want=$1 line

  for line in "${lines[@]}"
  do
    if [ "$line" = "$want" ]
    then
      return 0
    fi
  done
  fail "$(printf 'expected a line exactly matching:\n%s\nactual output:\n%s' "$want" "$output")"
}

@test "util env prints usage and exits 1 with -h" {
  # usage() sends only the "Usage: env ..." line to stderr; the surrounding
  # lines (including the leading description and the -h/-i/-r option list) are
  # plain `echo`, so they land on stdout. Existing behaviour, not a fix target.
  run --separate-stderr run_command bin/util/v1/env -h
  assert_failure 1
  assert_stderr_contains "Usage: env"
  assert_output_contains "Get AWS credentials for an infrastructure"
  assert_output_contains "-i <infrastructure>"
  assert_output_contains "-r"
}

@test "util env prints usage and exits 1 with an unrecognised option" {
  run --separate-stderr run_command bin/util/v1/env -z
  assert_failure 1
  assert_stderr_contains "Usage: env"
}

@test "util env prefixes matching variables with export by default" {
  # AWS_TEST_TOKEN must be exported, not just assigned, so the child shell
  # started by run_command's `bash -c` actually inherits it.
  export AWS_TEST_TOKEN=example-token
  run run_command bin/util/v1/env
  unset AWS_TEST_TOKEN
  assert_success
  assert_has_exact_line "export AWS_TEST_TOKEN=example-token"
}

@test "util env omits the export prefix with -r" {
  export AWS_TEST_TOKEN=example-token
  run run_command bin/util/v1/env -r
  unset AWS_TEST_TOKEN
  assert_success
  assert_has_exact_line "AWS_TEST_TOKEN=example-token"
}

@test "util env only lists variables whose name or value contains AWS" {
  # Guards against a test that would pass even if the grep matched everything:
  # a variable with no AWS in it anywhere must not appear.
  export AWS_TEST_TOKEN=example-token
  export UNRELATED_TEST_VAR=example-value
  run run_command bin/util/v1/env -r
  unset AWS_TEST_TOKEN UNRELATED_TEST_VAR
  assert_success
  assert_output_contains "AWS_TEST_TOKEN=example-token"
  refute_output_line "UNRELATED_TEST_VAR=example-value"
}

@test "util env matches AWS anywhere in the line, not just as a var name prefix" {
  # The script is a bare `grep AWS`, unanchored. A variable whose *value*
  # contains AWS also matches, and its whole line -- name included -- is what
  # gets the export prefix. Documenting actual behaviour, not the likely intent.
  export SOME_TOKEN=contains-AWS-inside
  run run_command bin/util/v1/env -r
  unset SOME_TOKEN
  assert_success
  assert_output_contains "SOME_TOKEN=contains-AWS-inside"
}

@test "util env never actually captures the -i infrastructure name" {
  # getopts is declared as "irh" -- no colon after i -- so -i takes no
  # argument. $INFRASTRUCTURE_NAME is always empty, regardless of what
  # follows -i on the command line; "example-infra" here is simply an
  # unconsumed, unused positional argument. Usage documents "-i
  # <infrastructure> - infrastructure name", implying it works.
  export QUIET_MODE=0
  run run_command bin/util/v1/env -i example-infra -r
  assert_success
  assert_output_contains "Getting AWS credentials for "
  case "$output" in
    *"Getting AWS credentials for example-infra"*)
      fail "expected the infrastructure name to be dropped, but it appeared in the log line:
$output"
      ;;
  esac
}
