#!/usr/bin/env bats
#
# bin/aurora/v1/download-sql-backup is not a real implementation -- it is a
# 5-line wrapper that redirects straight to `dalmatian rds
# download-sql-backup` (its rds/v1 twin is a full ~120-line interactive
# script). Its rds counterpart's own bats suite already covers what happens
# once that command runs; these tests cover only the redirect itself.

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
}

# Diverges from its count-sql-backups sibling: that wrapper builds
# COMMAND_ARGS from "${@:2}" and silently drops its own first argument.
# download-sql-backup instead forwards "${@:1}" -- the whole argument list,
# unchanged -- so it does not have the same bug. Verified directly against
# both scripts.
@test "aurora download-sql-backup redirects to 'dalmatian rds download-sql-backup', forwarding every argument unchanged" {
  run run_command bin/aurora/v1/download-sql-backup -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27"
  assert_success
  assert_stub_called_with "dalmatian rds download-sql-backup -i example-infra -r example-rds -e staging -d 2026-08-27"
}

# There is no usage/argument-count guard of its own -- called with nothing at
# all, it still forwards (a now-empty) argument list straight through.
@test "aurora download-sql-backup has no usage guard of its own and forwards zero arguments unchanged" {
  run run_command bin/aurora/v1/download-sql-backup
  assert_success
  assert_stub_called_with "dalmatian rds download-sql-backup"
}

# Same swallowed-error bug as its count-sql-backups sibling: no `set -e`, and
# an unconditional `exit 0` after the delegated call, so a failure from the
# real rds command never propagates. Existing behaviour of the script under
# test.
@test "aurora download-sql-backup always exits 0, even when the delegated command fails" {
  stub_exit dalmatian-rds-download_sql_backup 1
  run run_command bin/aurora/v1/download-sql-backup -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27"
  assert_success
}
