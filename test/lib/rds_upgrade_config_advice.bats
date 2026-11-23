#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  load_all_functions
  WHERE="engine_version for examplerds in config/infrastructures/example-infra.yml (rds block) in dalmatian-config"
}

@test "rds_upgrade_config_advice ok says no change is needed" {
  run --separate-stderr rds_upgrade_config_advice -s ok -t 8.4.10 -w "$WHERE"
  assert_success
  [[ "$stderr" == *"No config change is needed: the configured version matches 8.4.10."* ]]
  [[ "$stderr" == *"A deploy that changes this database for any other reason before the window applies the upgrade then."* ]]
  [[ "$stderr" != *"Leaving it unchanged"* ]]
}

@test "rds_upgrade_config_advice update says when to change config" {
  run --separate-stderr rds_upgrade_config_advice -s update -t 8.4.10 -w "$WHERE"
  assert_success
  [[ "$stderr" == *"Change $WHERE to 8.4.10 after the upgrade has happened and before the next deploy."* ]]
  [[ "$stderr" == *"Changing it before then makes the next deploy apply the upgrade immediately."* ]]
  [[ "$stderr" == *"Leaving it unchanged after the upgrade makes the next deploy fail: AWS will not downgrade."* ]]
  [[ "$stderr" == *"A deploy that changes this database for any other reason before the window applies the upgrade then."* ]]
  [[ "$stderr" != *"shared with other environments"* ]]
  [[ "$stderr" != *"lets environments upgrade independently"* ]]
}

@test "rds_upgrade_config_advice update lists shared environments" {
  run --separate-stderr rds_upgrade_config_advice -s update -t 8.4.10 -w "$WHERE" -o "$(printf 'staging 8.4.4\nprod not found')"
  assert_success
  [[ "$stderr" == *"This entry is shared with other environments:"* ]]
  [[ "$stderr" == *"staging 8.4.4"* ]]
  [[ "$stderr" == *"prod not found"* ]]
  [[ "$stderr" == *"Config can only change once all of them run 8.4.10."* ]]
}

@test "rds_upgrade_config_advice -m suggests major.minor" {
  run --separate-stderr rds_upgrade_config_advice -s update -t 8.4.10 -w "$WHERE" -m
  assert_success
  [[ "$stderr" == *"Setting engine_version to 8.4 lets environments upgrade independently."* ]]
}

@test "rds_upgrade_config_advice unknown asks the operator to check" {
  run --separate-stderr rds_upgrade_config_advice -s unknown -t 8.4.10 -w "$WHERE"
  assert_success
  [[ "$stderr" == *"Could not read the configured version. If $WHERE is a full version, change it to 8.4.10 after the upgrade has happened and before the next deploy."* ]]
  [[ "$stderr" == *"If it is a full version, changing it before then makes the next deploy apply the upgrade immediately."* ]]
  [[ "$stderr" == *"If it is a full version, leaving it unchanged after the upgrade makes the next deploy fail: AWS will not downgrade."* ]]
  [[ "$stderr" == *"A deploy that changes this database for any other reason before the window applies the upgrade then."* ]]
  [[ "$stderr" != *"was not checked"* ]]
}

@test "rds_upgrade_config_advice unknown with -c says the version was not checked" {
  run --separate-stderr rds_upgrade_config_advice -s unknown -t 8.4.10 -w "$WHERE" -c
  assert_success
  [[ "$stderr" == *"The configured version was not checked. If $WHERE is a full version, change it to 8.4.10 after the upgrade has happened and before the next deploy."* ]]
  [[ "$stderr" == *"If it is a full version, changing it before then makes the next deploy apply the upgrade immediately."* ]]
  [[ "$stderr" == *"If it is a full version, leaving it unchanged after the upgrade makes the next deploy fail: AWS will not downgrade."* ]]
  [[ "$stderr" != *"Could not read the configured version"* ]]
}

@test "rds_upgrade_config_advice prints its guidance to stderr in quiet mode" {
  QUIET_MODE=1
  run --separate-stderr rds_upgrade_config_advice -s update -t 8.4.10 -w "$WHERE" -o "prod not found" -m
  assert_success
  [[ "$stderr" == *"Change $WHERE to 8.4.10 after the upgrade has happened and before the next deploy."* ]]
  [[ "$stderr" == *"prod not found"* ]]
  [[ "$stderr" == *"Setting engine_version to 8.4 lets environments upgrade independently."* ]]
  [[ -z "$output" ]]
}

@test "rds_upgrade_config_advice leaves the caller's quiet mode alone" {
  QUIET_MODE=1
  rds_upgrade_config_advice -s ok -t 8.4.10 -w "$WHERE" 2> /dev/null
  [[ "$QUIET_MODE" == "1" ]]
}

@test "rds_upgrade_config_advice -a leaves out the deploy-before-the-window warning" {
  run --separate-stderr rds_upgrade_config_advice -s update -t 8.4.10 -w "$WHERE" -a
  assert_success
  [[ "$stderr" == *"Change $WHERE to 8.4.10 after the upgrade has happened and before the next deploy."* ]]
  [[ "$stderr" == *"Leaving it unchanged after the upgrade makes the next deploy fail: AWS will not downgrade."* ]]
  [[ "$stderr" != *"before the window applies the upgrade then"* ]]
}

@test "rds_upgrade_config_advice rejects an unknown status" {
  run --separate-stderr rds_upgrade_config_advice -s bogus -t 8.4.10 -w "$WHERE"
  assert_failure
  assert_stderr_contains "Invalid \`rds_upgrade_config_advice\` function usage"
}

@test "rds_upgrade_config_advice rejects a missing -s" {
  run --separate-stderr rds_upgrade_config_advice -t 8.4.10 -w "$WHERE"
  assert_failure
  assert_stderr_contains "Invalid \`rds_upgrade_config_advice\` function usage"
}

@test "rds_upgrade_config_advice rejects a missing -t" {
  run --separate-stderr rds_upgrade_config_advice -s ok -w "$WHERE"
  assert_failure
  assert_stderr_contains "Invalid \`rds_upgrade_config_advice\` function usage"
}

@test "rds_upgrade_config_advice rejects a missing -w" {
  run --separate-stderr rds_upgrade_config_advice -s ok -t 8.4.10
  assert_failure
  assert_stderr_contains "Invalid \`rds_upgrade_config_advice\` function usage"
}
