#!/usr/bin/env bats
#
# bin/aurora/v1/count-sql-backups is not a real implementation -- it is a
# 6-line wrapper that redirects straight to `dalmatian rds count-sql-backups`
# (its rds/v1 twin is a full ~70-line script). Its rds counterpart's own bats
# suite already covers what happens once that command runs; these tests cover
# only the redirect itself and the two bugs it has that the redirect logic in
# its download-sql-backup sibling does not.

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
}

# The wrapper builds COMMAND_ARGS from "${@:2}", not "${@:1}", so it drops the
# script's own first argument before forwarding. When invoked the way
# dalmatian's dispatcher actually calls it (bin/dalmatian sets COMMAND_ARGS
# from $3 onward, so this script's $1 is the caller's first real flag, e.g.
# "-i"), that flag is silently lost: "-i" disappears and "example-infra" is
# forwarded as a bare non-option argument ahead of the rest of the flags.
# Verified directly against the script and by tracing an actual invocation.
@test "aurora count-sql-backups redirects to 'dalmatian rds count-sql-backups' but drops its own first argument" {
  run run_command bin/aurora/v1/count-sql-backups -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27"
  assert_success
  assert_stub_called_with "dalmatian rds count-sql-backups example-infra -r example-rds -e staging -d 2026-08-27"
  refute_stub_called_with "-i example-infra"
}

# There is no usage/argument-count guard of its own -- called with nothing at
# all, it still forwards (a now-empty) COMMAND_ARGS straight through.
@test "aurora count-sql-backups has no usage guard of its own and forwards zero arguments unchanged" {
  run run_command bin/aurora/v1/count-sql-backups
  assert_success
  assert_stub_called_with "dalmatian rds count-sql-backups"
}

# The script has no `set -e`, and unconditionally ends with `exit 0` after the
# delegated call -- so a failure from the real rds command is swallowed and
# this wrapper always reports success. Existing behaviour of the script under
# test.
@test "aurora count-sql-backups always exits 0, even when the delegated command fails" {
  stub_exit dalmatian-rds-count_sql_backups 1
  run run_command bin/aurora/v1/count-sql-backups -i "example-infra" -r "example-rds" -e "staging" -d "2026-08-27"
  assert_success
}
