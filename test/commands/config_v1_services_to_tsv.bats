#!/usr/bin/env bats
#
# shellcheck disable=SC2030,SC2031
# Each @test block is a shellcheck-visible function, so reassigning
# DALMATIAN_CONFIG_PATH inside one looks like a subshell-local change that
# could be "lost" before it's read. bats runs each @test as its own
# invocation and the reassignment is read back within that same test --
# It just can't see that the boundary is a test, not a subshell.

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  stub_cli
  export QUIET_MODE=1
  DALMATIAN_CONFIG_PATH="$SANDBOX/dalmatian.yml"
  export DALMATIAN_CONFIG_PATH
  install_fixture dalmatian.yml "$DALMATIAN_CONFIG_PATH"
}

@test "config services-to-tsv prints usage and exits 1 with -h" {
  run --separate-stderr run_command bin/config/v1/services-to-tsv -h
  assert_failure 1
  assert_stderr_contains "Usage: services-to-tsv"
  assert_output_contains "List all services in spreadsheet format"
}

@test "config services-to-tsv has no header row" {
  # usage() documents the format ("<infra><tab><service><tab>...") but that
  # line only appears in usage() itself, never in real output. The first
  # line of real output is already data.
  run run_command bin/config/v1/services-to-tsv
  assert_success
  assert_line 0 "$(printf 'example-infra\tweb\t')"
}

@test "config services-to-tsv emits infra, service, domains in that order, tab-separated" {
  run run_command bin/config/v1/services-to-tsv
  assert_success
  [ "${#lines[@]}" -eq 3 ]
  assert_line 0 "$(printf 'example-infra\tweb\t')"
  assert_line 1 "$(printf 'example-infra\tworker\t')"
  assert_line 2 "$(printf 'other-infra\tapi\t')"
}

@test "config services-to-tsv defaults the domains field to empty when domain_names.prod is absent" {
  # None of the fixture's services set domain_names, so every row hits the
  # "else" branch that injects an empty domain_names.prod -- the third
  # (tab-separated) field is present but blank on every line, i.e. every
  # line ends with a trailing tab and nothing after it.
  run run_command bin/config/v1/services-to-tsv
  assert_success
  for line in "${lines[@]}"
  do
    case "$line" in
      *$'\t')
        ;;
      *)
        fail "expected line to end with an empty (trailing-tab) domains field:
$line"
        ;;
    esac
  done
}

@test "config services-to-tsv scoped to one infrastructure" {
  run run_command bin/config/v1/services-to-tsv -i other-infra
  assert_success
  assert_output "$(printf 'other-infra\tapi\t')"
}

@test "config services-to-tsv scoped to example-infra returns both its services" {
  run run_command bin/config/v1/services-to-tsv -i example-infra
  assert_success
  [ "${#lines[@]}" -eq 2 ]
  assert_line 0 "$(printf 'example-infra\tweb\t')"
  assert_line 1 "$(printf 'example-infra\tworker\t')"
}

@test "config services-to-tsv with an infrastructure that does not exist" {
  # Uses the same keys[]/select($infra_name == $i) pattern as
  # list-services-by-buildspec, so an unknown name yields empty output and
  # exit 0 rather than a jq error.
  run run_command bin/config/v1/services-to-tsv -i does-not-exist
  assert_success
  assert_output ""
}

@test "config services-to-tsv refreshes the config before reading it" {
  run run_command bin/config/v1/services-to-tsv
  assert_success
  assert_stub_called_with "dalmatian-refresh-config"
}

@test "config services-to-tsv produces no output for a missing config file" {
  DALMATIAN_CONFIG_PATH="$SANDBOX/does-not-exist.yml"
  export DALMATIAN_CONFIG_PATH

  run --separate-stderr run_command bin/config/v1/services-to-tsv
  assert_success
  assert_output ""
  assert_stderr_contains "no such file or directory"
}
