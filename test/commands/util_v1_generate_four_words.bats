#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  export QUIET_MODE=1
  DICT="$DALMATIAN_ROOT/data/common-short-words.txt"
}

@test "util generate-four-words prints usage and exits 1 with -h" {
  # Only the "Usage: ..." line is redirected to stderr; the description and
  # the -q/-h option lines are plain `echo`, so they land on stdout.
  run --separate-stderr run_command bin/util/v1/generate-four-words -h
  assert_failure 1
  assert_stderr_contains "Usage: generate-four-words"
  assert_output_contains "Generate a password"
  assert_output_contains "-q"
}

@test "util generate-four-words rejects -q even though usage documents it" {
  # getopts is declared as "h" only, so -q is not a recognised option despite
  # usage() advertising "-q - Quiet mode". It falls through bash's own
  # unrecognised-option handling straight to usage().
  run --separate-stderr run_command bin/util/v1/generate-four-words -q
  assert_failure 1
  assert_stderr_contains "illegal option"
  assert_stderr_contains "Usage: generate-four-words"
}

# The next two use --separate-stderr so $output is stdout alone.
#
# The script does `sort -R "$DICT" | head -n 4`, and GNU sort complains
# "write failed: 'standard output': Broken pipe" to stderr when head closes the
# pipe on it. BSD sort is silent. Without the separation that warning lands in
# $output and reads as a fifth word, which is what it did on Linux CI. The words
# themselves are unaffected -- the script captures only stdout -- but the
# spurious stderr line is real for Linux users.
@test "util generate-four-words produces four hyphen-separated words" {
  run --separate-stderr run_command bin/util/v1/generate-four-words
  assert_success
  [ "$(printf '%s' "$output" | tr -cd '-' | wc -c | tr -d ' ')" -eq 3 ]
  IFS='-' read -ra words <<< "$output"
  [ "${#words[@]}" -eq 4 ]
}

@test "util generate-four-words draws every word from the dictionary" {
  run --separate-stderr run_command bin/util/v1/generate-four-words
  assert_success
  IFS='-' read -ra words <<< "$output"
  for word in "${words[@]}"
  do
    grep -qxF "$word" "$DICT" || fail "word '$word' not found in $DICT"
  done
}

@test "util generate-four-words varies across invocations" {
  run run_command bin/util/v1/generate-four-words
  first="$output"
  run run_command bin/util/v1/generate-four-words
  second="$output"
  run run_command bin/util/v1/generate-four-words
  third="$output"

  # sort -R is randomised, not guaranteed-unique, so assert that at least one
  # of three draws differs rather than requiring all three to differ.
  if [ "$first" = "$second" ] && [ "$second" = "$third" ]
  then
    fail "three consecutive invocations all produced: $first"
  fi
}

@test "util generate-four-words prints the disclaimer unless QUIET_MODE is set" {
  export QUIET_MODE=0
  run run_command bin/util/v1/generate-four-words
  assert_success
  assert_output_contains "should not be used as login"
}

@test "util generate-four-words suppresses the disclaimer when QUIET_MODE=1" {
  run run_command bin/util/v1/generate-four-words
  assert_success
  refute_output_line "Please note that the phrases generated here should not be used as login"
}
