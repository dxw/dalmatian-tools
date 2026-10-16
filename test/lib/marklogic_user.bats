#!/usr/bin/env bats

load ../test_helper

# marklogic_user decides which MarkLogic user a command authenticates as.
# Operators have their own users; the stack's admin user is the emergency
# account and is only ever used when asked for explicitly with -A.

setup() {
  setup_sandbox
  load_all_functions
  unset MARKLOGIC_USER
}

@test "marklogic_user takes the -u user first" {
  MARKLOGIC_USER="env-user" run marklogic_user -u option-user -a stack-admin
  assert_success
  assert_output "option-user"
}

@test "marklogic_user takes MARKLOGIC_USER when there is no -u" {
  MARKLOGIC_USER="env-user" run marklogic_user -a stack-admin
  assert_success
  assert_output "env-user"
}

@test "marklogic_user prompts when neither is given, and never falls back to the stack's admin user" {
  run marklogic_user -a stack-admin <<< "typed-user"
  assert_success
  assert_output "typed-user"
}

@test "marklogic_user fails with no answer to the prompt" {
  run --separate-stderr marklogic_user -a stack-admin < /dev/null
  assert_failure
  assert_stderr_contains "No MarkLogic username given"
  assert_stderr_contains "-A"
}

@test "marklogic_user -A returns the stack's admin user with a warning" {
  run --separate-stderr marklogic_user -A -a stack-admin
  assert_success
  assert_output "stack-admin"
  assert_stderr_contains "Using the stack's admin user 'stack-admin'"
}

@test "marklogic_user -A fails when the stack has no admin user" {
  run --separate-stderr marklogic_user -A -a ""
  assert_failure
  assert_stderr_contains "the stack has no AdminUser parameter"
}

@test "marklogic_user refuses -A together with -u" {
  run --separate-stderr marklogic_user -A -u option-user -a stack-admin
  assert_failure
  assert_stderr_contains "-A and -u cannot be used together"
}
