#!/usr/bin/env bats

load ../test_helper

LIST=aws-rds-describe_db_instances
STAGING=aws-rds-describe_db_instances-db_instance_identifier-exampleinfraexamplerdsstaging
FILTERED=aws-rds-describe_db_instances-filters
PROD=aws-rds-describe_db_instances-filters-Name_db_instance_id_Values_exampleinfraexamplerdsprod
PINNEDPG=aws-rds-describe_db_instances-db_instance_identifier-exampleinfrapinnedpgstaging
ENGINE_VERSIONS=aws-rds-describe_db_engine_versions
PENDING_ACTIONS=aws-rds-describe_pending_maintenance_actions

setup() {
  setup_sandbox
  use_stubs
  stub_cli
  export QUIET_MODE=0
  export DALMATIAN_CONFIG_PATH="$DALMATIAN_ROOT/test/fixtures/dalmatian-rds-upgrade.yml"
  stub_response_file "$LIST" rds-v1-upgrade-describe-db-instances.json
  stub_response_file "$STAGING" rds-v1-upgrade-describe-db-instance.json
  stub_response_file "$ENGINE_VERSIONS" rds-describe-db-engine-versions-mysql.json
  stub_response "$FILTERED" '{"DBInstances": []}'
}

upgrade_engine() {
  run_command bin/rds/v1/upgrade-engine -i "example-infra" -e "staging" "$@"
}

# The describe after modify-db-instance has the same argv as the one before
# it, so a shim in front of the aws stub restages the response (for staging
# examplerds unless a key is given) as the modify call passes through. A
# $SANDBOX/read-back.exit written after this call makes the read-back fail
# with that status
read_back_after_modify() {
  local key=${1:-$STAGING}
  mkdir -p "$SANDBOX/dispatch"
  ln -sfn "$DALMATIAN_ROOT/test/stubs/_dispatch" "$SANDBOX/dispatch/aws"
  cat > "$SANDBOX/read-back.json"
  cat > "$SANDBOX/bin/aws" <<SHIM
#!/usr/bin/env bash
if [ "\${2-}" == "modify-db-instance" ]
then
  cp $(printf '%q' "$SANDBOX/read-back.json") $(printf '%q' "$DALMATIAN_STUB_RESPONSES/$key.out")
  if [ -f $(printf '%q' "$SANDBOX/read-back.exit") ]
  then
    cp $(printf '%q' "$SANDBOX/read-back.exit") $(printf '%q' "$DALMATIAN_STUB_RESPONSES/$key.exit")
  fi
fi
exec $(printf '%q' "$SANDBOX/dispatch/aws") "\$@"
SHIM
  chmod +x "$SANDBOX/bin/aws"
}

refute_list_called() {
  if grep -qFx "aws rds describe-db-instances" "$DALMATIAN_STUB_ARGV_LOG"
  then
    fail "expected no unfiltered describe-db-instances call when -r is given"
  fi
}

config_with_engine_version() {
  export DALMATIAN_CONFIG_PATH="$SANDBOX/dalmatian.yml"
  cat > "$DALMATIAN_CONFIG_PATH" <<YAML
infrastructures:
  example-infra:
    environments:
      staging: {}
      prod: {}
    rds:
      - identifier: $1
        engine: mysql
        engine_version: $2
YAML
}

staging_with() {
  fixture_json rds-v1-upgrade-describe-db-instance.json | jq "$1"
}

@test "rds upgrade-engine prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v1/upgrade-engine
  assert_failure 1
  assert_stderr_contains "Usage: upgrade-engine"
  assert_output_contains "-v <target_version>"
}

@test "rds upgrade-engine requires an infrastructure" {
  run --separate-stderr run_command bin/rds/v1/upgrade-engine -e "staging" -r "examplerds"
  assert_failure 1
  assert_stderr_contains "Usage: upgrade-engine"
  refute_stub_called_with "aws"
}

@test "rds upgrade-engine requires an environment" {
  run --separate-stderr run_command bin/rds/v1/upgrade-engine -i "example-infra" -r "examplerds"
  assert_failure 1
  assert_stderr_contains "Usage: upgrade-engine"
  refute_stub_called_with "aws"
}

@test "rds upgrade-engine refuses names that are not identifier-like" {
  run --separate-stderr upgrade_engine -r 'example rds' -v 8.4.10 -y
  assert_failure 1
  assert_stderr_contains "must be letters, digits"
  refute_stub_called_with "aws"
}

@test "declining the prompt changes nothing" {
  run upgrade_engine -r "examplerds" -v 8.4.10 <<< "n"
  assert_success
  assert_output_contains "Current version: 8.4.3"
  assert_output_contains "Target version: 8.4.10"
  assert_output_contains "Maintenance window: mon:19:00-mon:19:30 (UTC)"
  assert_output_contains "Next window: "
  assert_output_contains "Nothing was changed"
  assert_call_args aws rds describe-db-instances --db-instance-identifier exampleinfraexamplerdsstaging
  assert_call_args aws rds describe-db-engine-versions --engine mysql --engine-version 8.4.3 --include-all
  assert_call_args aws rds describe-pending-maintenance-actions --resource-identifier arn:aws:rds:eu-west-2:123456789012:db:exampleinfraexamplerdsstaging
  refute_list_called
  refute_stub_called_with "modify-db-instance"
}

@test "quiet mode still shows the summary on stderr before the prompt" {
  QUIET_MODE=1 run --separate-stderr upgrade_engine -r "examplerds" -v 8.4.10 <<< "n"
  assert_success
  assert_stderr_contains "Current version: 8.4.3"
  assert_stderr_contains "Target version: 8.4.10"
  assert_stderr_contains "Next window: "
  assert_stderr_contains "Take a manual snapshot first:"
  case "$output" in
    *"Target version:"*) fail "expected the summary on stderr only, got: $output" ;;
  esac
  refute_stub_called_with "modify-db-instance"
}

@test "an empty answer declines" {
  run upgrade_engine -r "examplerds" -v 8.4.10 <<< ""
  assert_success
  assert_output_contains "Nothing was changed"
  refute_stub_called_with "modify-db-instance"
}

@test "the summary recommends a snapshot with the command to take one" {
  run upgrade_engine -r "examplerds" -v 8.4.10 <<< "n"
  assert_success
  assert_output_contains "dalmatian aws exec -i example-infra rds create-db-snapshot --db-instance-identifier exampleinfraexamplerdsstaging --db-snapshot-identifier exampleinfraexamplerdsstaging-pre-8-4-10"
}

@test "the summary lists pending maintenance actions with the command to opt in" {
  stub_response "$PENDING_ACTIONS" <<'JSON'
{
  "PendingMaintenanceActions": [
    {
      "ResourceIdentifier": "arn:aws:rds:eu-west-2:123456789012:db:exampleinfraexamplerdsstaging",
      "PendingMaintenanceActionDetails": [
        {"Action": "system-update", "Description": "New Operating System update is available"}
      ]
    }
  ]
}
JSON
  run upgrade_engine -r "examplerds" -v 8.4.10 <<< "n"
  assert_success
  assert_output_contains "system-update: New Operating System update is available"
  assert_output_contains "dalmatian aws exec -i example-infra rds apply-pending-maintenance-action --resource-identifier arn:aws:rds:eu-west-2:123456789012:db:exampleinfraexamplerdsstaging --apply-action system-update --opt-in-type next-maintenance"
  refute_stub_called_with "apply-pending-maintenance-action"
}

@test "-y queues the upgrade for the next window" {
  fixture_json rds-v1-upgrade-describe-db-instance-pending.json | read_back_after_modify
  run upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_success
  assert_call_args aws rds modify-db-instance --db-instance-identifier exampleinfraexamplerdsstaging --engine-version 8.4.10 --no-apply-immediately
  refute_stub_called_with "--allow-major-version-upgrade"
  assert_output_contains "Next window: "
  assert_output_contains "Pending engine version: 8.4.10"
  assert_output_contains "maintenance window"
  assert_output_contains "A deploy that changes this database for any other reason before the window applies the upgrade then."
}

@test "confirms a queued upgrade AWS has already started" {
  staging_with '.DBInstances[0].DBInstanceStatus = "upgrading"' | read_back_after_modify
  run upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_success
  assert_output_contains "AWS started the upgrade straight away, in the current maintenance window."
}

@test "confirms a queued upgrade AWS has already finished" {
  staging_with '.DBInstances[0].EngineVersion = "8.4.10"' | read_back_after_modify
  run upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_success
  assert_output_contains "AWS started the upgrade straight away, in the current maintenance window."
}

@test "-a warns that other pending changes are applied too" {
  staging_with '.DBInstances[0].PendingModifiedValues = {DBInstanceClass: "db.t3.large", EngineVersion: "8.4.5"}' | stub_response "$STAGING"
  run --separate-stderr upgrade_engine -r "examplerds" -v 8.4.10 -a <<< "n"
  assert_success
  assert_stderr_contains "Applying now also applies the other changes already pending on exampleinfraexamplerdsstaging: DBInstanceClass."
  refute_stub_called_with "modify-db-"
}

@test "does not warn about other pending changes without -a" {
  staging_with '.DBInstances[0].PendingModifiedValues = {DBInstanceClass: "db.t3.large", EngineVersion: "8.4.5"}' | stub_response "$STAGING"
  run --separate-stderr upgrade_engine -r "examplerds" -v 8.4.10 <<< "n"
  assert_success
  [[ "$stderr" != *"other changes already pending"* ]]
}

@test "-a applies immediately" {
  staging_with '.DBInstances[0].DBInstanceStatus = "upgrading"' | read_back_after_modify
  run upgrade_engine -r "examplerds" -v 8.4.10 -a -y
  assert_success
  assert_call_args aws rds modify-db-instance --db-instance-identifier exampleinfraexamplerdsstaging --engine-version 8.4.10 --apply-immediately
  assert_output_contains "When: immediately"
  assert_output_contains "The database restarts now and is unavailable while it upgrades."
  assert_output_contains "Status: upgrading"
  case "$output" in
    *"Next window: "*) fail "expected no next window with -a, got: $output" ;;
    *"before the window applies the upgrade then"*) fail "expected no window warning with -a, got: $output" ;;
  esac
}

@test "-a fails when the immediate upgrade cannot be confirmed" {
  run --separate-stderr upgrade_engine -r "examplerds" -v 8.4.10 -a -y
  assert_failure
  assert_call_args aws rds modify-db-instance --db-instance-identifier exampleinfraexamplerdsstaging --engine-version 8.4.10 --apply-immediately
  assert_stderr_contains "could not be confirmed"
}

@test "refuses a version that is not a minor target" {
  run --separate-stderr upgrade_engine -r "examplerds" -v 9.0.1 -y
  assert_failure
  assert_stderr_contains "9.0.1 is not a minor upgrade target"
  assert_stderr_contains "Major version upgrades are not supported"
  refute_stub_called_with "modify-db-instance"
}

@test "refuses a target with a line of its own after a valid version" {
  run --separate-stderr upgrade_engine -r "examplerds" -v $'8.4.10\nx' -y
  assert_failure
  assert_stderr_contains "is not a minor upgrade target"
  refute_stub_called_with "modify-db-instance"
}

@test "refuses a version AWS did not offer" {
  run --separate-stderr upgrade_engine -r "examplerds" -v 8.4.99 -y
  assert_failure
  assert_stderr_contains "8.4.99 is not a minor upgrade target"
  refute_stub_called_with "modify-db-instance"
}

@test "refuses a database that is not available" {
  staging_with '.DBInstances[0].DBInstanceStatus = "modifying"' | stub_response "$STAGING"
  run --separate-stderr upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_failure
  assert_stderr_contains "modifying"
  refute_stub_called_with "describe-db-engine-versions"
  refute_stub_called_with "modify-db-instance"
}

@test "refuses -v when AWS offers no minor targets" {
  stub_response "$ENGINE_VERSIONS" '{"DBEngineVersions": [{"Engine": "mysql", "EngineVersion": "8.4.3", "ValidUpgradeTarget": [{"EngineVersion": "9.0.1", "IsMajorVersionUpgrade": true}]}]}'
  run --separate-stderr upgrade_engine -r "examplerds" -v 9.0.1 -y
  assert_failure
  assert_stderr_contains "9.0.1 is not a minor upgrade target"
  assert_stderr_contains "Major version upgrades are not supported"
  assert_stderr_contains "AWS offers no minor upgrade targets for mysql 8.4.3."
  [[ "$output" != *"already on the latest minor version"* ]]
  refute_stub_called_with "modify-db-instance"
}

@test "fails when AWS has no record of the current version" {
  stub_response "$ENGINE_VERSIONS" '{"DBEngineVersions": []}'
  run --separate-stderr upgrade_engine -r "examplerds" -y
  assert_failure
  assert_stderr_contains "AWS returned no record of"
  refute_stub_called_with "modify-db-instance"
}

@test "says when there is nothing to upgrade to" {
  stub_response "$ENGINE_VERSIONS" '{"DBEngineVersions": [{"Engine": "mysql", "EngineVersion": "8.4.3", "ValidUpgradeTarget": []}]}'
  run upgrade_engine -r "examplerds" -y
  assert_success
  assert_output_contains "already on the latest minor version"
  refute_stub_called_with "modify-db-instance"
}

@test "warns about an upgrade already pending" {
  stub_response_file "$STAGING" rds-v1-upgrade-describe-db-instance-pending.json
  run upgrade_engine -r "examplerds" -v 8.4.4 <<< "n"
  assert_success
  local before_prompt="${output%%Nothing was changed*}"
  case "$before_prompt" in
    *"already has a pending upgrade to 8.4.10"*) ;;
    *) fail "expected the pending upgrade warning before the prompt, got: $output" ;;
  esac
}

@test "fails when the upgrade cannot be confirmed" {
  run --separate-stderr upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_failure
  assert_call_args aws rds modify-db-instance --db-instance-identifier exampleinfraexamplerdsstaging --engine-version 8.4.10 --no-apply-immediately
  assert_stderr_contains "could not be confirmed"
}

@test "fails when the read-back describe fails" {
  printf '' | read_back_after_modify
  printf '255\n' > "$SANDBOX/read-back.exit"
  run --separate-stderr upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_failure
  assert_stderr_contains "could not be confirmed: describing exampleinfraexamplerdsstaging failed"
}

@test "fails when the read-back is not JSON" {
  printf 'not json\n' | read_back_after_modify
  run --separate-stderr upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_failure
  assert_stderr_contains "could not be confirmed: exampleinfraexamplerdsstaging is unknown on unknown"
}

@test "says the upgrade may happen in this window when it is in progress" {
  stub_now 1795461000
  fixture_json rds-v1-upgrade-describe-db-instance-pending.json | read_back_after_modify
  run upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_success
  assert_output_contains "Next window: Mon 23 Nov 2026 19:00 UTC to Mon 23 Nov 2026 19:30 UTC (in progress)"
  assert_output_contains "It is applied in this maintenance window or the next one: Mon 23 Nov 2026 19:00 UTC"
}

@test "advises a config change with other environments" {
  fixture_json rds-v1-upgrade-describe-db-instance-pending.json | read_back_after_modify
  run upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_success
  assert_call_args aws rds describe-db-instances --filters Name=db-instance-id,Values=exampleinfraexamplerdsprod
  assert_output_contains "Change engine_version for examplerds"
  assert_output_contains "prod not found"
  assert_output_contains "Setting engine_version to 8.4"
  refute_output_line "  staging not found"
  refute_stub_called_with "dalmatian-refresh-config"
}

@test "lists the running version of other environments" {
  fixture_json rds-v1-upgrade-describe-db-instance-pending.json | read_back_after_modify
  unstub "$PROD"
  stub_response "$PROD" '{"DBInstances": [{"DBInstanceIdentifier": "exampleinfraexamplerdsprod", "EngineVersion": "8.4.3"}]}'
  run upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_success
  assert_output_contains "prod 8.4.3"
}

@test "carries on when another environment cannot be checked" {
  fixture_json rds-v1-upgrade-describe-db-instance-pending.json | read_back_after_modify
  stub_exit "$PROD" 254
  stub_stderr "$PROD" "An error occurred (AccessDenied) when calling the DescribeDBInstances operation: denied."
  run --separate-stderr upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_success
  assert_stderr_contains "  prod not checked"
  assert_stderr_contains "Config can only change once all of them run 8.4.10."
  assert_stderr_contains "AccessDenied"
  assert_stderr_contains "Could not check the engine version of examplerds in prod."
}

@test "says no config change is needed when config matches the target" {
  fixture_json rds-v1-upgrade-describe-db-instance-pending.json | read_back_after_modify
  config_with_engine_version examplerds 8.4.10
  run upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_success
  assert_output_contains "No config change is needed"
  refute_stub_called_with "describe-db-instances --filters"
}

@test "says config could not be read when it has no entry" {
  fixture_json rds-v1-upgrade-describe-db-instance-pending.json | read_back_after_modify
  config_with_engine_version otherrds 8.4.3
  run upgrade_engine -r "examplerds" -v 8.4.10 -y
  assert_success
  assert_output_contains "Could not read the configured version."
  refute_stub_called_with "describe-db-instances --filters"
}

@test "does not suggest major.minor for postgres" {
  fixture_json rds-v1-upgrade-describe-db-instances.json | jq '{DBInstances: [.DBInstances[1]]}' | stub_response "$PINNEDPG"
  fixture_json rds-v1-upgrade-describe-db-instances.json \
    | jq '{DBInstances: [.DBInstances[1] | .PendingModifiedValues = {EngineVersion: "16.10"}]}' \
    | read_back_after_modify "$PINNEDPG"
  stub_response "$ENGINE_VERSIONS" '{"DBEngineVersions": [{"Engine": "postgres", "EngineVersion": "16.8", "ValidUpgradeTarget": [{"Engine": "postgres", "EngineVersion": "16.10", "IsMajorVersionUpgrade": false}]}]}'
  run upgrade_engine -r "pinnedpg" -v 16.10 -y
  assert_success
  assert_output_contains "Change engine_version for pinnedpg"
  assert_output_contains "prod not found"
  case "$output" in
    *"Setting engine_version to"*) fail "expected no major.minor suggestion for postgres, got: $output" ;;
  esac
}

@test "picker fails without a terminal when -r is omitted" {
  run --separate-stderr upgrade_engine -v 8.4.10 -y < /dev/null
  assert_failure
  assert_call_args aws rds describe-db-instances
  assert_stderr_contains "Pass one explicitly with \`-r\`"
  assert_stderr_contains "examplerds"
  assert_stderr_contains "pinnedpg"
  case "$stderr" in
    *otherinfra*) fail "expected otherinfra to be filtered out, got: $stderr" ;;
  esac
  refute_stub_called_with "modify-db-instance"
}
