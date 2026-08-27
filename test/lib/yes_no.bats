#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
}

@test "yes_no accepts y" {
  run bash -c 'source "$DALMATIAN_ROOT/lib/bash-functions/yes_no.sh"; yes_no "Continue? (Y/n)" "Y" <<< "y"'
  assert_success
}

@test "yes_no rejects n" {
  run bash -c 'source "$DALMATIAN_ROOT/lib/bash-functions/yes_no.sh"; yes_no "Continue? (Y/n)" "Y" <<< "n"'
  assert_failure
}

@test "yes_no takes the default on an empty answer" {
  run bash -c 'source "$DALMATIAN_ROOT/lib/bash-functions/yes_no.sh"; yes_no "Continue? (Y/n)" "N" <<< ""'
  assert_failure
}

@test "yes_no re-prompts on an unrecognised answer" {
  run bash -c 'source "$DALMATIAN_ROOT/lib/bash-functions/yes_no.sh"; printf "maybe\nn\n" | yes_no "Continue? (Y/n)" "Y"'
  assert_failure
  assert_output_contains "Please answer Y or N"
}
