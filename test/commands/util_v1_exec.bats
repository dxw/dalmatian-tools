#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  export QUIET_MODE=1
}

@test "util exec prints usage and exits 1 with -h" {
  # Only the "Usage: exec ..." line is redirected to stderr; the four
  # preceding description/example lines and the two option lines after it are
  # plain `echo`, so they all land on stdout.
  run --separate-stderr run_command bin/util/v1/exec -h
  assert_failure 1
  assert_stderr_contains "Usage: exec"
  assert_output_contains "dalmatian util exec env | grep AWS"
  assert_output_contains "-i <infrastructure>"
}

@test "util exec prints usage and exits 1 with an unrecognised option" {
  run --separate-stderr run_command bin/util/v1/exec -z
  assert_failure 1
  assert_stderr_contains "Usage: exec"
}

@test "util exec runs the given command with no -i flag" {
  run run_command bin/util/v1/exec echo hello world
  assert_success
  assert_output "hello world"
}

@test "util exec still runs the command correctly when -i is given" {
  # getopts is declared as "ih", with no colon after i, so -i never actually
  # captures its argument into $OPTARG/$INFRASTRUCTURE_NAME -- it always ends
  # up empty. Because of that, the script's own `if [ -z $INFRASTRUCTURE_NAME
  # ]` branch is *always* taken, and it shifts by $((OPTIND-1)) twice, which
  # happens to strip both "-i" and its value in the common case of a single
  # -i flag. The net effect: -i is accepted and silently stripped, but the
  # named infrastructure has no effect on anything -- it is never read again.
  run run_command bin/util/v1/exec -i example-infra echo hello world
  assert_success
  assert_output "hello world"
}

@test "util exec propagates the exit status of the executed command" {
  run run_command bin/util/v1/exec false
  assert_failure 1
}

@test "util exec propagates a nonzero exit status other than 1" {
  run run_command bin/util/v1/exec sh -c "exit 7"
  assert_failure 7
}

@test "util exec fails when no command is given at all" {
  # exec "$@" with an empty array is a no-op in bash: nothing to exec, so the
  # script falls through with no output and no error.
  run run_command bin/util/v1/exec
  assert_success
  assert_output ""
}

@test "util exec preserves arguments containing spaces" {
  run run_command bin/util/v1/exec echo "hello there"
  assert_success
  assert_output "hello there"
}
