#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
}

@test "kill_process_tree ends a process and its descendants" {
  local marker="kill-tree-test-$$-$RANDOM"
  bash -c "bash -c '/bin/sleep 30; : $marker-inner'; : $marker-outer" &
  local root=$!
  local tries=0
  until pgrep -f "$marker-inner" > /dev/null || [ "$tries" -ge 50 ]
  do
    tries=$(( tries + 1 ))
    /bin/sleep 0.1
  done
  pgrep -f "$marker-inner" > /dev/null || fail "expected the inner process to be running"

  kill_process_tree "$root"
  /bin/sleep 0.2

  run pgrep -f "$marker-inner"
  assert_failure
  run pgrep -f "$marker-outer"
  assert_failure
}

@test "kill_process_tree is quiet about a process that has already gone" {
  run --separate-stderr kill_process_tree 2147483000
  assert_success
  [ -z "$stderr" ] || fail "expected no stderr, got: $stderr"
}

@test "kill_process_tree rejects a missing pid" {
  run --separate-stderr kill_process_tree
  assert_failure
  assert_stderr_contains "Invalid \`kill_process_tree\` function usage"
}
