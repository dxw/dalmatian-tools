#!/usr/bin/env bats

load ../test_helper

TARGET=8.0.mysql_aurora.3.10.3
CLUSTER_ARN=arn:aws:rds:eu-west-2:123456789012:cluster:exampleinfraexampleclusterstaging
MEMBER_ARN=arn:aws:rds:eu-west-2:123456789012:db:exampleinfraexampleclusterstaging-1

LIST=aws-rds-describe_db_clusters
STAGING=aws-rds-describe_db_clusters-db_cluster_identifier-exampleinfraexampleclusterstaging
PROD=aws-rds-describe_db_clusters-filters-Name_db_cluster_id_Values_exampleinfraexampleclusterprod
FILTERED=aws-rds-describe_db_clusters-filters
MEMBER=aws-rds-describe_db_instances-db_instance_identifier-exampleinfraexampleclusterstaging_1
ENGINE_VERSIONS=aws-rds-describe_db_engine_versions
CLUSTER_PENDING=aws-rds-describe_pending_maintenance_actions-resource_identifier-arn_aws_rds_eu_west_2_123456789012_cluster_exampleinfraexampleclusterstaging
MEMBER_PENDING=aws-rds-describe_pending_maintenance_actions-resource_identifier-arn_aws_rds_eu_west_2_123456789012_db_exampleinfraexampleclusterstaging_1

setup() {
  setup_sandbox
  use_stubs
  stub_cli
  export QUIET_MODE=0
  export DALMATIAN_CONFIG_PATH="$DALMATIAN_ROOT/test/fixtures/dalmatian-rds-upgrade.yml"
  stub_response_file "$LIST" aurora-v1-upgrade-describe-db-clusters.json
  stub_response "$STAGING" <<< "$(fixture_json aurora-v1-upgrade-describe-db-clusters.json | jq '{DBClusters: [.DBClusters[0]]}')"
  stub_response "$MEMBER" "{\"DBInstances\": [{\"DBInstanceIdentifier\": \"exampleinfraexampleclusterstaging-1\", \"DBInstanceArn\": \"$MEMBER_ARN\"}]}"
  stub_response_file "$ENGINE_VERSIONS" aurora-v1-upgrade-describe-db-engine-versions.json
  stub_response "$FILTERED" '{"DBClusters": []}'
}

upgrade_engine() {
  run_command bin/aurora/v1/upgrade-engine -i "example-infra" -e "staging" "$@"
}

# The describe after modify-db-cluster has the same argv as the one before
# it, so a shim in front of the aws stub restages the response (for staging
# examplecluster unless a key is given) as the modify call passes through. A
# $SANDBOX/read-back.exit written after this call makes the read-back fail
# with that status
read_back_after_modify() {
  local key=${1:-$STAGING}
  mkdir -p "$SANDBOX/dispatch"
  ln -sfn "$DALMATIAN_ROOT/test/stubs/_dispatch" "$SANDBOX/dispatch/aws"
  cat > "$SANDBOX/read-back.json"
  cat > "$SANDBOX/bin/aws" <<SHIM
#!/usr/bin/env bash
if [ "\${2-}" == "modify-db-cluster" ]
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

# Restages the cluster's pending maintenance response as the modify call
# passes through, for a read-back that differs from the one before the prompt.
# Reads the new response from stdin
pending_after_modify() {
  mkdir -p "$SANDBOX/dispatch"
  ln -sfn "$DALMATIAN_ROOT/test/stubs/_dispatch" "$SANDBOX/dispatch/aws"
  cat > "$SANDBOX/pending-after.json"
  cat > "$SANDBOX/bin/aws" <<SHIM
#!/usr/bin/env bash
if [ "\${2-}" == "modify-db-cluster" ]
then
  cp $(printf '%q' "$SANDBOX/pending-after.json") $(printf '%q' "$DALMATIAN_STUB_RESPONSES/$CLUSTER_PENDING.out")
fi
exec $(printf '%q' "$SANDBOX/dispatch/aws") "\$@"
SHIM
  chmod +x "$SANDBOX/bin/aws"
}

pending_action() {
  jq -n --arg arn "$CLUSTER_ARN" --arg action "$1" --arg desc "$2" \
    '{PendingMaintenanceActions: [{ResourceIdentifier: $arn, PendingMaintenanceActionDetails: [{Action: $action, Description: $desc}]}]}'
}

refute_list_called() {
  if grep -qFx "aws rds describe-db-clusters" "$DALMATIAN_STUB_ARGV_LOG"
  then
    fail "expected no unfiltered describe-db-clusters call when -r is given"
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
    aurora:
      - identifier: $1
        engine: aurora-mysql
        engine_version: $2
YAML
}

staging_with() {
  fixture_json aurora-v1-upgrade-describe-db-clusters.json | jq "{DBClusters: [.DBClusters[0] | $1]}"
}

staging_pending() {
  staging_with ".PendingModifiedValues = {EngineVersion: \"$TARGET\"}"
}

@test "aurora upgrade-engine prints usage with no arguments" {
  run --separate-stderr run_command bin/aurora/v1/upgrade-engine
  assert_failure 1
  assert_stderr_contains "Usage: upgrade-engine"
  assert_output_contains "-v <target_version>"
}

@test "aurora upgrade-engine requires an infrastructure" {
  run --separate-stderr run_command bin/aurora/v1/upgrade-engine -e "staging" -r "examplecluster"
  assert_failure 1
  assert_stderr_contains "Usage: upgrade-engine"
  refute_stub_called_with "aws"
}

@test "aurora upgrade-engine requires an environment" {
  run --separate-stderr run_command bin/aurora/v1/upgrade-engine -i "example-infra" -r "examplecluster"
  assert_failure 1
  assert_stderr_contains "Usage: upgrade-engine"
  refute_stub_called_with "aws"
}

@test "aurora upgrade-engine refuses names that are not identifier-like" {
  run --separate-stderr upgrade_engine -r 'example cluster' -v "$TARGET" -y
  assert_failure 1
  assert_stderr_contains "must be letters, digits"
  refute_stub_called_with "aws"
}

@test "declining the prompt changes nothing" {
  run upgrade_engine -r "examplecluster" -v "$TARGET" <<< "n"
  assert_success
  assert_output_contains "Current version: 8.0.mysql_aurora.3.05.2"
  assert_output_contains "Target version: $TARGET"
  assert_output_contains "Maintenance window: mon:19:00-mon:19:30 (UTC)"
  assert_output_contains "Next window: "
  assert_output_contains "Every instance in the cluster restarts during the upgrade."
  assert_output_contains "Nothing was changed"
  assert_call_args aws rds describe-db-clusters --db-cluster-identifier exampleinfraexampleclusterstaging
  assert_call_args aws rds describe-db-engine-versions --engine aurora-mysql --engine-version 8.0.mysql_aurora.3.05.2 --include-all
  assert_call_args aws rds describe-pending-maintenance-actions --resource-identifier "$CLUSTER_ARN"
  assert_call_args aws rds describe-db-instances --db-instance-identifier exampleinfraexampleclusterstaging-1
  assert_call_args aws rds describe-pending-maintenance-actions --resource-identifier "$MEMBER_ARN"
  refute_list_called
  refute_stub_called_with "modify-db-cluster"
}

@test "quiet mode still shows the summary on stderr before the prompt" {
  QUIET_MODE=1 run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" <<< "n"
  assert_success
  assert_stderr_contains "Current version: 8.0.mysql_aurora.3.05.2"
  assert_stderr_contains "Target version: $TARGET"
  assert_stderr_contains "Every instance in the cluster restarts during the upgrade."
  assert_stderr_contains "Take a manual snapshot first:"
  case "$output" in
    *"Target version:"*) fail "expected the summary on stderr only, got: $output" ;;
  esac
  refute_stub_called_with "modify-db-cluster"
}

@test "an empty answer declines" {
  run upgrade_engine -r "examplecluster" -v "$TARGET" <<< ""
  assert_success
  assert_output_contains "Nothing was changed"
  refute_stub_called_with "modify-db-cluster"
}

@test "the summary recommends a cluster snapshot with the command to take one" {
  run upgrade_engine -r "examplecluster" -v "$TARGET" <<< "n"
  assert_success
  assert_output_contains "dalmatian aws exec -i example-infra rds create-db-cluster-snapshot --db-cluster-identifier exampleinfraexampleclusterstaging --db-cluster-snapshot-identifier exampleinfraexampleclusterstaging-pre-8-0-mysql-aurora-3-10-3"
}

@test "the summary lists pending maintenance actions for the cluster and its members" {
  stub_response_file "$CLUSTER_PENDING" aurora-v1-upgrade-pending-maintenance.json
  stub_response "$MEMBER_PENDING" <<JSON
{
  "PendingMaintenanceActions": [
    {
      "ResourceIdentifier": "$MEMBER_ARN",
      "PendingMaintenanceActionDetails": [
        {"Action": "system-update", "Description": "New Operating System update is available"}
      ]
    }
  ]
}
JSON
  run upgrade_engine -r "examplecluster" -v "$TARGET" <<< "n"
  assert_success
  assert_output_contains "db-upgrade: Upgrade to Aurora MySQL $TARGET"
  assert_output_contains "dalmatian aws exec -i example-infra rds apply-pending-maintenance-action --resource-identifier $CLUSTER_ARN --apply-action db-upgrade --opt-in-type next-maintenance"
  assert_output_contains "system-update: New Operating System update is available"
  assert_output_contains "dalmatian aws exec -i example-infra rds apply-pending-maintenance-action --resource-identifier $MEMBER_ARN --apply-action system-update --opt-in-type next-maintenance"
  refute_stub_called_with "apply-pending-maintenance-action"
}

@test "carries on when a member's pending maintenance cannot be read" {
  stub_exit "$MEMBER_PENDING" 254
  stub_stderr "$MEMBER_PENDING" "An error occurred (AccessDenied) when calling the DescribePendingMaintenanceActions operation: denied."
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" <<< "n"
  assert_success
  assert_stderr_contains "Could not look up pending maintenance for cluster member exampleinfraexampleclusterstaging-1."
  assert_output_contains "Nothing was changed"
}

@test "carries on when a member cannot be described" {
  stub_exit "$MEMBER" 254
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" <<< "n"
  assert_success
  assert_stderr_contains "Could not look up pending maintenance for cluster member exampleinfraexampleclusterstaging-1."
  assert_output_contains "Nothing was changed"
}

@test "-y queues the upgrade for the next window" {
  staging_pending | read_back_after_modify
  run upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  assert_call_args aws rds modify-db-cluster --db-cluster-identifier exampleinfraexampleclusterstaging --engine-version "$TARGET" --no-apply-immediately
  refute_stub_called_with "--allow-major-version-upgrade"
  assert_output_contains "Next window: "
  assert_output_contains "Pending engine version: $TARGET"
  assert_output_contains "maintenance window"
  assert_output_contains "A deploy that changes this database for any other reason before the window applies the upgrade then."
}

@test "confirms a queued upgrade from a db-upgrade action that is new after the modify" {
  pending_action db-upgrade "Upgrade to Aurora MySQL" | pending_after_modify
  run upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  assert_call_args aws rds modify-db-cluster --db-cluster-identifier exampleinfraexampleclusterstaging --engine-version "$TARGET" --no-apply-immediately
  assert_output_contains "Pending engine version: $TARGET"
}

@test "confirms a queued upgrade from a stale action whose description names the full target" {
  pending_action db-upgrade "Upgrade to Aurora MySQL $TARGET" | stub_response "$CLUSTER_PENDING"
  run upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  assert_output_contains "Pending engine version: $TARGET"
}

@test "confirms a queued upgrade from a stale action whose description names the short target" {
  pending_action system-update "Aurora MySQL 3.10.3 is available" | stub_response "$CLUSTER_PENDING"
  run upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  assert_output_contains "Pending engine version: $TARGET"
}

@test "does not take a stale action naming a longer version as confirmation" {
  pending_action db-upgrade "Upgrade to Aurora MySQL 3.10.30" | stub_response "$CLUSTER_PENDING"
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "could not be confirmed"
}

@test "does not take a stale action naming a version with a longer prefix as confirmation" {
  pending_action db-upgrade "Upgrade to Aurora MySQL 13.10.3" | stub_response "$CLUSTER_PENDING"
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "could not be confirmed"
}

@test "does not take the same db-upgrade pending before and after as confirmation" {
  pending_action db-upgrade "Upgrade to Aurora MySQL" | stub_response "$CLUSTER_PENDING"
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "could not be confirmed"
}

@test "does not take an unrelated system-update as confirmation" {
  pending_action system-update "New Operating System update is available" | stub_response "$CLUSTER_PENDING"
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "could not be confirmed"
}

@test "does not take an unrelated system-update new after the modify as confirmation" {
  pending_action system-update "New Operating System update is available" | pending_after_modify
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "could not be confirmed"
}

@test "-a does not take a pending db-upgrade as confirmation" {
  pending_action db-upgrade "Upgrade to Aurora MySQL $TARGET" | pending_after_modify
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -a -y
  assert_failure
  assert_stderr_contains "could not be confirmed"
}

@test "confirms a queued upgrade AWS has already started" {
  staging_with '.Status = "upgrading"' | read_back_after_modify
  run upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  assert_output_contains "AWS started the upgrade straight away, in the current maintenance window."
}

@test "-a warns that other pending changes are applied too" {
  staging_with '.PendingModifiedValues = {BackupRetentionPeriod: 14}' | stub_response "$STAGING"
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -a <<< "n"
  assert_success
  assert_stderr_contains "Applying now also applies the other changes already pending on exampleinfraexampleclusterstaging: BackupRetentionPeriod."
  refute_stub_called_with "modify-db-"
}

@test "does not warn about other pending changes without -a" {
  staging_with '.PendingModifiedValues = {BackupRetentionPeriod: 14}' | stub_response "$STAGING"
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" <<< "n"
  assert_success
  [[ "$stderr" != *"other changes already pending"* ]]
}

@test "-a applies immediately" {
  staging_with '.Status = "upgrading"' | read_back_after_modify
  run upgrade_engine -r "examplecluster" -v "$TARGET" -a -y
  assert_success
  assert_call_args aws rds modify-db-cluster --db-cluster-identifier exampleinfraexampleclusterstaging --engine-version "$TARGET" --apply-immediately
  assert_output_contains "When: immediately"
  assert_output_contains "The database restarts now and is unavailable while it upgrades."
  assert_output_contains "Status: upgrading"
  case "$output" in
    *"Next window: "*) fail "expected no next window with -a, got: $output" ;;
    *"before the window applies the upgrade then"*) fail "expected no window warning with -a, got: $output" ;;
  esac
}

@test "-a fails when the immediate upgrade cannot be confirmed" {
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -a -y
  assert_failure
  assert_call_args aws rds modify-db-cluster --db-cluster-identifier exampleinfraexampleclusterstaging --engine-version "$TARGET" --apply-immediately
  assert_stderr_contains "could not be confirmed"
}

@test "refuses a version that is not a minor target" {
  run --separate-stderr upgrade_engine -r "examplecluster" -v 8.4.mysql_aurora.4.0.0 -y
  assert_failure
  assert_stderr_contains "8.4.mysql_aurora.4.0.0 is not a minor upgrade target"
  assert_stderr_contains "Major version upgrades are not supported"
  refute_stub_called_with "modify-db-cluster"
}

@test "refuses a target with a line of its own after a valid version" {
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET"$'\nx' -y
  assert_failure
  assert_stderr_contains "is not a minor upgrade target"
  refute_stub_called_with "modify-db-cluster"
}

@test "refuses a version AWS did not offer" {
  run --separate-stderr upgrade_engine -r "examplecluster" -v 8.0.mysql_aurora.3.99.9 -y
  assert_failure
  assert_stderr_contains "8.0.mysql_aurora.3.99.9 is not a minor upgrade target"
  refute_stub_called_with "modify-db-cluster"
}

@test "refuses a cluster that is not available" {
  staging_with '.Status = "modifying"' | stub_response "$STAGING"
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "modifying"
  refute_stub_called_with "describe-db-engine-versions"
  refute_stub_called_with "modify-db-cluster"
}

@test "refuses -v when AWS offers no minor targets" {
  stub_response "$ENGINE_VERSIONS" '{"DBEngineVersions": [{"Engine": "aurora-mysql", "EngineVersion": "8.0.mysql_aurora.3.05.2", "ValidUpgradeTarget": [{"EngineVersion": "8.4.mysql_aurora.4.0.0", "IsMajorVersionUpgrade": true}]}]}'
  run --separate-stderr upgrade_engine -r "examplecluster" -v 8.4.mysql_aurora.4.0.0 -y
  assert_failure
  assert_stderr_contains "8.4.mysql_aurora.4.0.0 is not a minor upgrade target"
  assert_stderr_contains "Major version upgrades are not supported"
  assert_stderr_contains "AWS offers no minor upgrade targets for aurora-mysql 8.0.mysql_aurora.3.05.2."
  [[ "$output" != *"already on the latest minor version"* ]]
  refute_stub_called_with "modify-db-cluster"
}

@test "fails when AWS has no record of the current version" {
  stub_response "$ENGINE_VERSIONS" '{"DBEngineVersions": []}'
  run --separate-stderr upgrade_engine -r "examplecluster" -y
  assert_failure
  assert_stderr_contains "AWS returned no record of"
  refute_stub_called_with "modify-db-cluster"
}

@test "says when there is nothing to upgrade to" {
  stub_response "$ENGINE_VERSIONS" '{"DBEngineVersions": [{"Engine": "aurora-mysql", "EngineVersion": "8.0.mysql_aurora.3.05.2", "ValidUpgradeTarget": []}]}'
  run upgrade_engine -r "examplecluster" -y
  assert_success
  assert_output_contains "already on the latest minor version"
  refute_stub_called_with "modify-db-cluster"
}

@test "warns about an upgrade already pending" {
  staging_pending | stub_response "$STAGING"
  run upgrade_engine -r "examplecluster" -v 8.0.mysql_aurora.3.06.0 <<< "n"
  assert_success
  local before_prompt="${output%%Nothing was changed*}"
  case "$before_prompt" in
    *"already has a pending upgrade to $TARGET"*) ;;
    *) fail "expected the pending upgrade warning before the prompt, got: $output" ;;
  esac
}

@test "fails when the upgrade cannot be confirmed" {
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_failure
  assert_call_args aws rds modify-db-cluster --db-cluster-identifier exampleinfraexampleclusterstaging --engine-version "$TARGET" --no-apply-immediately
  assert_stderr_contains "could not be confirmed"
}

@test "fails when the read-back describe fails" {
  printf '' | read_back_after_modify
  printf '255\n' > "$SANDBOX/read-back.exit"
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "could not be confirmed: describing exampleinfraexampleclusterstaging failed"
}

@test "advises a config change with other environments" {
  config_with_engine_version examplecluster 8.0.mysql_aurora.3.05.2
  staging_pending | read_back_after_modify
  run upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  assert_call_args aws rds describe-db-clusters --filters Name=db-cluster-id,Values=exampleinfraexampleclusterprod
  assert_output_contains "Change engine_version for examplecluster in the aurora block"
  assert_output_contains "prod not found"
  assert_output_contains "Setting engine_version to 8.0 "
  refute_output_line "  staging not found"
}

@test "lists the running version of other environments" {
  config_with_engine_version examplecluster 8.0.mysql_aurora.3.05.2
  staging_pending | read_back_after_modify
  unstub "$PROD"
  stub_response "$PROD" '{"DBClusters": [{"DBClusterIdentifier": "exampleinfraexampleclusterprod", "EngineVersion": "8.0.mysql_aurora.3.05.2"}]}'
  run upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  assert_output_contains "prod 8.0.mysql_aurora.3.05.2"
}

@test "carries on when another environment cannot be checked" {
  config_with_engine_version examplecluster 8.0.mysql_aurora.3.05.2
  staging_pending | read_back_after_modify
  stub_exit "$PROD" 254
  stub_stderr "$PROD" "An error occurred (AccessDenied) when calling the DescribeDBClusters operation: denied."
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  assert_stderr_contains "  prod not checked"
  assert_stderr_contains "Config can only change once all of them run $TARGET."
  assert_stderr_contains "AccessDenied"
  assert_stderr_contains "Could not check the engine version of examplecluster in prod."
}

@test "says no config change is needed when config is a prefix of the target" {
  staging_pending | read_back_after_modify
  run upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  assert_output_contains "No config change is needed"
  refute_stub_called_with "describe-db-clusters --filters"
}

@test "says config could not be read when it has no entry" {
  config_with_engine_version othercluster 8.0.mysql_aurora.3.05.2
  staging_pending | read_back_after_modify
  run upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  assert_output_contains "Could not read the configured version."
  refute_stub_called_with "describe-db-clusters --filters"
}

@test "-a with a config change needed does not warn about a window" {
  config_with_engine_version examplecluster 8.0.mysql_aurora.3.05.2
  staging_with '.Status = "upgrading"' | read_back_after_modify
  run upgrade_engine -r "examplecluster" -v "$TARGET" -a -y
  assert_success
  assert_output_contains "Change engine_version for examplecluster"
  case "$output" in
    *"before the window applies the upgrade then"*) fail "expected no window warning with -a, got: $output" ;;
  esac
}

@test "fails when the read-back is not JSON" {
  printf 'not json\n' | read_back_after_modify
  run --separate-stderr upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "could not be confirmed: exampleinfraexampleclusterstaging is unknown on unknown"
}

@test "says the upgrade may happen in this window when it is in progress" {
  stub_now 1795461000
  staging_pending | read_back_after_modify
  run upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  assert_output_contains "Next window: Mon 23 Nov 2026 19:00 UTC to Mon 23 Nov 2026 19:30 UTC (in progress)"
  assert_output_contains "It is applied in this maintenance window or the next one: Mon 23 Nov 2026 19:00 UTC"
}

@test "does not refresh the config itself" {
  config_with_engine_version examplecluster 8.0.mysql_aurora.3.05.2
  staging_pending | read_back_after_modify
  run upgrade_engine -r "examplecluster" -v "$TARGET" -y
  assert_success
  refute_stub_called_with "dalmatian-refresh-config"
}

@test "picker fails without a terminal when -r is omitted" {
  run --separate-stderr upgrade_engine -v "$TARGET" -y < /dev/null
  assert_failure
  assert_call_args aws rds describe-db-clusters
  assert_stderr_contains "Pass one explicitly with \`-r\`"
  assert_stderr_contains "examplecluster"
  assert_stderr_contains "secondcluster"
  case "$stderr" in
    *otherinfra*) fail "expected otherinfra to be filtered out, got: $stderr" ;;
  esac
  refute_stub_called_with "modify-db-cluster"
}
