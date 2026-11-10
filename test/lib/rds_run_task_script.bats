#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  stub_dalmatian
}

# The command handed to `utilities run-command -c`, with the wrapping
# stripped, leaving the base64
sent_base64() {
  # shellcheck disable=SC2016
  sed -n 's/^dalmatian utilities run-command .* -c bash -c "$(echo \([^ ]*\) | base64 -d)".*/\1/p' "$DALMATIAN_STUB_LOG"
}

@test "rds_run_task_script sends the script as base64 through utilities run-command" {
  script=$'echo "a b"\nprintf \'%s\\n\' "$HOME"'

  run rds_run_task_script -i example-infra -e staging -r example-rds -s "$script"
  assert_success
  refute_stub_called_with "-R"
  [ "$(sent_base64 | base64 -d)" == "$script" ]
  assert_call_args dalmatian utilities run-command -i example-infra -e staging -r example-rds -c "bash -c \"\$(echo $(sent_base64) | base64 -d)\""
}

@test "rds_run_task_script passes -R through" {
  run rds_run_task_script -i example-infra -e staging -r example-rds -s "true" -R "$SANDBOX/result"
  assert_success
  assert_call_args dalmatian utilities run-command -i example-infra -e staging -r example-rds -c "bash -c \"\$(echo $(sent_base64) | base64 -d)\"" -R "$SANDBOX/result"
}

@test "rds_run_task_script returns the status of run-command" {
  stub_exit dalmatian-utilities-run_command 3

  run rds_run_task_script -i example-infra -e staging -r example-rds -s "true"
  assert_failure 3
}

# Piped into bash's stdin, a command in the script that reads stdin would
# consume the rest of the script instead of it being run
@test "rds_run_task_script runs the script so a command reading stdin cannot swallow the rest" {
  script=$'cat > /dev/null\necho after'

  run rds_run_task_script -i example-infra -e staging -r example-rds -s "$script"
  assert_success
  run bash -c "$(sed -n 's/^dalmatian utilities run-command -i [^ ]* -e [^ ]* -r [^ ]* -c //p' "$DALMATIAN_STUB_LOG")" < /dev/null
  assert_success
  [ "$output" == "after" ] || fail "output was: $output"
}
