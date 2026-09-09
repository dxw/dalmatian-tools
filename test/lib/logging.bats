#!/usr/bin/env bats

load ../test_helper

setup() {
  # setup_sandbox exports QUIET_MODE=0, which esc_msg relies on: it reads
  # QUIET_MODE from the environment and hands it to log_msg
  setup_sandbox
  load_all_functions
}

@test "log_info writes the message with an arrow prefix" {
  run log_info -l "hello" -q 0
  assert_success
  assert_output_contains "hello"
  assert_output_contains "==>"
}

@test "log_info suppresses output in quiet mode" {
  run log_info -l "hello" -q 1
  assert_success
  assert_output ""
}

@test "log_info defaults to not quiet when -q is omitted" {
  run log_info -l "hello"
  assert_success
  assert_output_contains "hello"
}

@test "log_info rejects an unknown flag" {
  run log_info -z "hello"
  assert_failure
  assert_output_contains "Invalid \`log_info\` function usage"
}

@test "log_msg writes the message with no prefix" {
  run log_msg -l "plain" -q 0
  assert_success
  assert_output "plain"
}

@test "log_msg suppresses output in quiet mode" {
  run log_msg -l "plain" -q 1
  assert_success
  assert_output ""
}

@test "esc_msg doubles a backslash so echo -e cannot reinterpret it" {
  run esc_msg 'C:\path\to\thing'
  assert_success
  assert_output 'C:\path\to\thing'
}

@test "esc_msg keeps text after a \\c that would otherwise truncate the line" {
  run esc_msg 'account\c (123456789012)'
  assert_success
  assert_output_contains "123456789012"
}

@test "err writes to stderr with an error prefix" {
  run --separate-stderr err "went wrong"
  assert_success
  assert_output ""
  assert_stderr_contains "Error:"
  assert_stderr_contains "went wrong"
}

@test "warning writes to stderr with a warning prefix" {
  run --separate-stderr warning "be careful"
  assert_success
  assert_output ""
  assert_stderr_contains "Warning:"
  assert_stderr_contains "be careful"
}

@test "die reports the error and exits non-zero" {
  run --separate-stderr die "fatal thing"
  assert_failure 1
  assert_stderr_contains "fatal thing"
}
