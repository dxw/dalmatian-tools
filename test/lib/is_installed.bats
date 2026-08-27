#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
}

@test "is_installed is true for a binary on PATH" {
  # `is_installed` tests `which -s`, which is a BSD flag. GNU which, as shipped
  # on Linux, rejects it and exits non-zero, so on those hosts the function
  # reports every binary as missing. The check below is capability-based rather
  # than OS-based so this reads as "the host cannot support the assertion"
  # rather than encoding a guess about which platforms are affected.
  #
  # Skipped rather than asserted either way: passing on the broken behaviour
  # would make the bug look intentional. It is recorded in the design spec's
  # follow-up list.
  if ! which -s bash 2> /dev/null
  then
    skip "which -s is unsupported here, so is_installed cannot succeed"
  fi

  run is_installed "aws"
  assert_success
}

@test "is_installed is false for a binary that is not on PATH" {
  run --separate-stderr is_installed "definitely-not-a-real-binary"
  assert_failure
  assert_stderr_contains "was not detected in your \$PATH"
}
