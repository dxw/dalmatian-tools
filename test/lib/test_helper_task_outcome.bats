#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  stub_cli
}

@test "stub_task_outcome writes the line into run-command's result file and logs the call" {
  stub_task_outcome "exited 2"

  run "$DALMATIAN_TEST_APP_ROOT/bin/dalmatian" utilities run-command -i example-infra -c "true" -R "$SANDBOX/result"
  assert_success
  [ "$(cat "$SANDBOX/result")" == "exited 2" ]
  assert_call_args dalmatian utilities run-command -i example-infra -c true -R "$SANDBOX/result"
}

@test "stub_task_outcome with an empty line leaves the result file empty" {
  stub_task_outcome ""
  : > "$SANDBOX/result"

  run "$DALMATIAN_TEST_APP_ROOT/bin/dalmatian" utilities run-command -c "true" -R "$SANDBOX/result"
  assert_success
  [ ! -s "$SANDBOX/result" ]
  assert_stub_called_with "dalmatian utilities run-command -c true -R $SANDBOX/result"
}

@test "stub_task_outcome leaves other calls answered by the stub responses" {
  stub_task_outcome "exited 0"
  stub_response dalmatian-aws-run_command "answer"
  stub_exit dalmatian-utilities-run_command 255

  run "$DALMATIAN_TEST_APP_ROOT/bin/dalmatian" aws run-command -p example-account
  assert_success
  assert_output "answer"

  run "$DALMATIAN_TEST_APP_ROOT/bin/dalmatian" utilities run-command -c "true" -R "$SANDBOX/result"
  assert_failure 255
  [ "$(cat "$SANDBOX/result")" == "exited 0" ]
}
