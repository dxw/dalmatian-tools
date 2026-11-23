#!/usr/bin/env bats

load ../test_helper

# ccb69c87 is the resource prefix hash for example-project / example-infra /
# staging, as pinned by test/lib/resource_prefix_hash.bats.
P=dalmatian-aws-run_command-p-example_account-rds
INSTANCES=$P-describe_db_instances
CLUSTERS=$P-describe_db_clusters
RDS_AS_CLUSTER=$P-describe_db_clusters-db_cluster_identifier-ccb69c87_example_rds
RDS=$P-describe_db_instances-db_instance_identifier-ccb69c87_example_rds
CLUSTER=$P-describe_db_clusters-db_cluster_identifier-ccb69c87_example_cluster
MEMBER=$P-describe_db_instances-db_instance_identifier-ccb69c87_example_cluster_1
MYSQL_VERSIONS=$P-describe_db_engine_versions-engine-mysql
AURORA_VERSIONS=$P-describe_db_engine_versions-engine-aurora_mysql
RDS_ARN=arn:aws:rds:eu-west-2:123456789012:db:ccb69c87-example-rds
CLUSTER_ARN=arn:aws:rds:eu-west-2:123456789012:cluster:ccb69c87-example-cluster
MEMBER_ARN=arn:aws:rds:eu-west-2:123456789012:db:ccb69c87-example-cluster-1
CLUSTER_PENDING=$P-describe_pending_maintenance_actions-resource_identifier-arn_aws_rds_eu_west_2_123456789012_cluster_ccb69c87_example_cluster
MEMBER_PENDING=$P-describe_pending_maintenance_actions-resource_identifier-arn_aws_rds_eu_west_2_123456789012_db_ccb69c87_example_cluster_1
RDS_PENDING=$P-describe_pending_maintenance_actions-resource_identifier-arn_aws_rds_eu_west_2_123456789012_db_ccb69c87_example_rds
TARGET=8.0.mysql_aurora.3.10.3

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=0
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  stub_response_file "$INSTANCES" v2-rds-upgrade-describe-db-instances.json
  stub_response_file "$CLUSTERS" v2-rds-upgrade-describe-db-clusters.json
  stub_rds_not_found "$RDS_AS_CLUSTER" DBClusterNotFoundFault
  rds_with '.' | stub_response "$RDS"
  cluster_with '.' | stub_response "$CLUSTER"
  stub_response "$MEMBER" "{\"DBInstances\": [{\"DBInstanceIdentifier\": \"ccb69c87-example-cluster-1\", \"DBInstanceArn\": \"$MEMBER_ARN\"}]}"
  stub_response_file "$MYSQL_VERSIONS" rds-describe-db-engine-versions-mysql.json
  stub_response_file "$AURORA_VERSIONS" aurora-v1-upgrade-describe-db-engine-versions.json
}

upgrade_engine() {
  run_command bin/rds/v2/upgrade-engine -i "example-infra" -e "staging" "$@"
}

rds_with() {
  fixture_json v2-rds-upgrade-describe-db-instances.json | jq "{DBInstances: [.DBInstances[0] | $1]}"
}

cluster_with() {
  fixture_json v2-rds-upgrade-describe-db-clusters.json | jq "{DBClusters: [.DBClusters[0] | $1]}"
}

pending_action() {
  jq -n --arg arn "$CLUSTER_ARN" --arg action "$1" --arg desc "$2" \
    '{PendingMaintenanceActions: [{ResourceIdentifier: $arn, PendingMaintenanceActionDetails: [{Action: $action, Description: $desc}]}]}'
}

# The describes after the modify have the same argv as the ones before it, so
# a wrapper in front of the CLI stub restages the response for <key> (read
# from stdin) as the modify call passes through. Each call adds one
# restaging. A $SANDBOX/restage-<key>.exit written after this call makes that
# read-back fail with its status
restage_on_modify() {
  local key=$1
  cat > "$SANDBOX/restage-$key.json"
  printf '%s\n' "$key" >> "$SANDBOX/restage.keys"
  if [ ! -L "$SANDBOX/cli/dispatch/dalmatian" ]
  then
    mkdir -p "$SANDBOX/cli/dispatch"
    ln -sfn "$DALMATIAN_ROOT/test/stubs/_dispatch" "$SANDBOX/cli/dispatch/dalmatian"
    # bin/dalmatian is a symlink to _dispatch: writing through it would
    # overwrite _dispatch itself
    rm -f "$SANDBOX/cli/bin/dalmatian"
    cat > "$SANDBOX/cli/bin/dalmatian" <<WRAPPER
#!/usr/bin/env bash
for arg in "\$@"
do
  if [ "\$arg" == "modify-db-instance" ] || [ "\$arg" == "modify-db-cluster" ]
  then
    while IFS= read -r key
    do
      cp "$SANDBOX/restage-\$key.json" "$DALMATIAN_STUB_RESPONSES/\$key.out"
      if [ -f "$SANDBOX/restage-\$key.exit" ]
      then
        cp "$SANDBOX/restage-\$key.exit" "$DALMATIAN_STUB_RESPONSES/\$key.exit"
      fi
    done < "$SANDBOX/restage.keys"
  fi
done
exec "$SANDBOX/cli/dispatch/dalmatian" "\$@"
WRAPPER
    chmod +x "$SANDBOX/cli/bin/dalmatian"
  fi
}

refute_list_called() {
  if grep -qFx "dalmatian aws run-command -p example-account rds describe-db-instances" "$DALMATIAN_STUB_ARGV_LOG" \
    || grep -qFx "dalmatian aws run-command -p example-account rds describe-db-clusters" "$DALMATIAN_STUB_ARGV_LOG"
  then
    fail "expected no unfiltered describe call when -r is given"
  fi
}

@test "upgrade-engine prints usage with no arguments" {
  run --separate-stderr run_command bin/rds/v2/upgrade-engine
  assert_failure 1
  assert_stderr_contains "Usage: upgrade-engine"
  assert_output_contains "-v <target_version>"
}

@test "upgrade-engine requires an infrastructure" {
  run --separate-stderr run_command bin/rds/v2/upgrade-engine -e "staging" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "Usage: upgrade-engine"
  refute_stub_called_with "dalmatian"
}

@test "upgrade-engine requires an environment" {
  run --separate-stderr run_command bin/rds/v2/upgrade-engine -i "example-infra" -r "example-rds"
  assert_failure 1
  assert_stderr_contains "Usage: upgrade-engine"
  refute_stub_called_with "dalmatian"
}

@test "rejects an RDS name that is not identifier-like before any AWS call" {
  run --separate-stderr upgrade_engine -r 'x;y' -v 8.4.10 -y
  assert_failure 1
  assert_stderr_contains "must be letters, digits"
  refute_stub_called_with "run-command"
}

@test "rejects an environment name that is not identifier-like before any AWS call" {
  run --separate-stderr run_command bin/rds/v2/upgrade-engine -i "example-infra" -e 'staging;x' -v 8.4.10 -y
  assert_failure 1
  assert_stderr_contains "must be letters, digits"
  refute_stub_called_with "run-command"
}

@test "declining the prompt changes nothing" {
  run upgrade_engine -r "example-rds" -v 8.4.10 <<< "n"
  assert_success
  assert_output_contains "RDS instance: ccb69c87-example-rds (example-infra staging)"
  assert_output_contains "Current version: 8.4.3"
  assert_output_contains "Target version: 8.4.10"
  assert_output_contains "Maintenance window: Mon:19:00-Mon:22:00 (UTC)"
  assert_output_contains "Next window: "
  assert_output_contains "Nothing was changed"
  assert_call_args dalmatian aws run-command -p example-account rds describe-db-instances --db-instance-identifier ccb69c87-example-rds
  assert_call_args dalmatian aws run-command -p example-account rds describe-db-engine-versions --engine mysql --engine-version 8.4.3 --include-all
  assert_call_args dalmatian aws run-command -p example-account rds describe-pending-maintenance-actions --resource-identifier "$RDS_ARN"
  refute_list_called
  refute_stub_called_with "modify-db-"
}

@test "quiet mode still shows the summary on stderr before the prompt" {
  QUIET_MODE=1 run --separate-stderr upgrade_engine -r "example-rds" -v 8.4.10 <<< "n"
  assert_success
  assert_stderr_contains "Current version: 8.4.3"
  assert_stderr_contains "Target version: 8.4.10"
  assert_stderr_contains "Next window: "
  assert_stderr_contains "Take a manual snapshot first:"
  case "$output" in
    *"Target version:"*) fail "expected the summary on stderr only, got: $output" ;;
  esac
  refute_stub_called_with "modify-db-"
}

@test "an empty answer declines" {
  run upgrade_engine -r "example-rds" -v 8.4.10 <<< ""
  assert_success
  assert_output_contains "Nothing was changed"
  refute_stub_called_with "modify-db-"
}

@test "the summary recommends a snapshot with the command to take one" {
  run upgrade_engine -r "example-rds" -v 8.4.10 <<< "n"
  assert_success
  assert_output_contains "dalmatian aws exec -i example-infra -e staging rds create-db-snapshot --db-instance-identifier ccb69c87-example-rds --db-snapshot-identifier ccb69c87-example-rds-pre-8-4-10"
}

@test "the summary lists pending maintenance actions with the command to opt in" {
  stub_response "$RDS_PENDING" <<JSON
{
  "PendingMaintenanceActions": [
    {
      "ResourceIdentifier": "$RDS_ARN",
      "PendingMaintenanceActionDetails": [
        {"Action": "system-update", "Description": "New Operating System update is available"}
      ]
    }
  ]
}
JSON
  run upgrade_engine -r "example-rds" -v 8.4.10 <<< "n"
  assert_success
  assert_output_contains "system-update: New Operating System update is available"
  assert_output_contains "dalmatian aws exec -i example-infra -e staging rds apply-pending-maintenance-action --resource-identifier $RDS_ARN --apply-action system-update --opt-in-type next-maintenance"
  refute_stub_called_with "apply-pending-maintenance-action"
}

@test "-y queues an instance upgrade for the next window" {
  rds_with '.PendingModifiedValues = {EngineVersion: "8.4.10"}' | restage_on_modify "$RDS"
  run upgrade_engine -r "example-rds" -v 8.4.10 -y
  assert_success
  assert_call_args dalmatian aws run-command -p example-account rds modify-db-instance --db-instance-identifier ccb69c87-example-rds --engine-version 8.4.10 --no-apply-immediately
  refute_stub_called_with "--allow-major-version-upgrade"
  refute_stub_called_with "modify-db-cluster"
  assert_output_contains "Pending engine version: 8.4.10"
  assert_output_contains "maintenance window"
}

@test "confirms a queued instance upgrade AWS has already started" {
  rds_with '.DBInstanceStatus = "upgrading"' | restage_on_modify "$RDS"
  run upgrade_engine -r "example-rds" -v 8.4.10 -y
  assert_success
  assert_output_contains "AWS started the upgrade straight away, in the current maintenance window."
}

@test "-a warns that other pending changes are applied too" {
  rds_with '.PendingModifiedValues = {DBInstanceClass: "db.t3.large"}' | stub_response "$RDS"
  run --separate-stderr upgrade_engine -r "example-rds" -v 8.4.10 -a <<< "n"
  assert_success
  assert_stderr_contains "Applying now also applies the other changes already pending on ccb69c87-example-rds: DBInstanceClass."
  refute_stub_called_with "modify-db-"
}

@test "does not warn about other pending changes without -a" {
  rds_with '.PendingModifiedValues = {DBInstanceClass: "db.t3.large"}' | stub_response "$RDS"
  run --separate-stderr upgrade_engine -r "example-rds" -v 8.4.10 <<< "n"
  assert_success
  [[ "$stderr" != *"other changes already pending"* ]]
}

@test "-a applies an instance upgrade immediately" {
  rds_with '.DBInstanceStatus = "upgrading"' | restage_on_modify "$RDS"
  run upgrade_engine -r "example-rds" -v 8.4.10 -a -y
  assert_success
  assert_call_args dalmatian aws run-command -p example-account rds modify-db-instance --db-instance-identifier ccb69c87-example-rds --engine-version 8.4.10 --apply-immediately
  assert_output_contains "When: immediately"
  assert_output_contains "The database restarts now and is unavailable while it upgrades."
  assert_output_contains "Status: upgrading"
  case "$output" in
    *"Next window: "*) fail "expected no next window with -a, got: $output" ;;
    *"before the window applies the upgrade then"*) fail "expected no window warning with -a, got: $output" ;;
  esac
}

@test "-a fails when the immediate instance upgrade cannot be confirmed" {
  run --separate-stderr upgrade_engine -r "example-rds" -v 8.4.10 -a -y
  assert_failure
  assert_call_args dalmatian aws run-command -p example-account rds modify-db-instance --db-instance-identifier ccb69c87-example-rds --engine-version 8.4.10 --apply-immediately
  assert_stderr_contains "could not be confirmed"
}

@test "fails when the instance upgrade cannot be confirmed" {
  run --separate-stderr upgrade_engine -r "example-rds" -v 8.4.10 -y
  assert_failure
  assert_stderr_contains "could not be confirmed: ccb69c87-example-rds is available on 8.4.3 with no pending upgrade to 8.4.10."
  assert_stderr_contains "dalmatian aws exec -i example-infra -e staging rds describe-db-instances --db-instance-identifier ccb69c87-example-rds"
}

@test "fails when the read-back describe fails" {
  printf '' | restage_on_modify "$RDS"
  printf '255\n' > "$SANDBOX/restage-$RDS.exit"
  run --separate-stderr upgrade_engine -r "example-rds" -v 8.4.10 -y
  assert_failure
  assert_stderr_contains "could not be confirmed: describing ccb69c87-example-rds failed"
}

@test "refuses a version that is not a minor target" {
  run --separate-stderr upgrade_engine -r "example-rds" -v 9.0.1 -y
  assert_failure
  assert_stderr_contains "9.0.1 is not a minor upgrade target"
  assert_stderr_contains "Major version upgrades are not supported"
  refute_stub_called_with "modify-db-"
}

@test "refuses a target with a line of its own after a valid version" {
  run --separate-stderr upgrade_engine -r "example-rds" -v $'8.4.10\nx' -y
  assert_failure
  assert_stderr_contains "is not a minor upgrade target"
  refute_stub_called_with "modify-db-"
}

@test "says the upgrade may happen in this window when it is in progress" {
  stub_now 1795461000
  rds_with '.PendingModifiedValues = {EngineVersion: "8.4.10"}' | restage_on_modify "$RDS"
  run upgrade_engine -r "example-rds" -v 8.4.10 -y
  assert_success
  assert_output_contains "Next window: Mon 23 Nov 2026 19:00 UTC to Mon 23 Nov 2026 22:00 UTC (in progress)"
  assert_output_contains "It is applied in this maintenance window or the next one: Mon 23 Nov 2026 19:00 UTC"
}

@test "refuses a version AWS did not offer" {
  run --separate-stderr upgrade_engine -r "example-rds" -v 8.4.99 -y
  assert_failure
  assert_stderr_contains "8.4.99 is not a minor upgrade target"
  case "$stderr" in
    *"Major version upgrades"*) fail "expected no major upgrade message, got: $stderr" ;;
  esac
  refute_stub_called_with "modify-db-"
}

@test "refuses a database that is not available" {
  rds_with '.DBInstanceStatus = "modifying"' | stub_response "$RDS"
  run --separate-stderr upgrade_engine -r "example-rds" -v 8.4.10 -y
  assert_failure
  assert_stderr_contains "ccb69c87-example-rds is modifying"
  refute_stub_called_with "describe-db-engine-versions"
  refute_stub_called_with "modify-db-"
}

@test "refuses -v when AWS offers no minor targets" {
  stub_response "$MYSQL_VERSIONS" '{"DBEngineVersions": [{"Engine": "mysql", "EngineVersion": "8.4.3", "ValidUpgradeTarget": [{"EngineVersion": "9.0.1", "IsMajorVersionUpgrade": true}]}]}'
  run --separate-stderr upgrade_engine -r "example-rds" -v 9.0.1 -y
  assert_failure
  assert_stderr_contains "9.0.1 is not a minor upgrade target"
  assert_stderr_contains "Major version upgrades are not supported"
  assert_stderr_contains "AWS offers no minor upgrade targets for mysql 8.4.3."
  [[ "$output" != *"already on the latest minor version"* ]]
  refute_stub_called_with "modify-db-"
}

@test "fails when AWS has no record of the current version" {
  stub_response "$MYSQL_VERSIONS" '{"DBEngineVersions": []}'
  run --separate-stderr upgrade_engine -r "example-rds" -y
  assert_failure
  assert_stderr_contains "AWS returned no record of"
  refute_stub_called_with "modify-db-"
}

@test "says when there is nothing to upgrade to" {
  stub_response "$MYSQL_VERSIONS" '{"DBEngineVersions": [{"Engine": "mysql", "EngineVersion": "8.4.3", "ValidUpgradeTarget": []}]}'
  run upgrade_engine -r "example-rds" -y
  assert_success
  assert_output_contains "already on the latest minor version"
  refute_stub_called_with "modify-db-"
}

@test "warns about an upgrade already pending" {
  rds_with '.PendingModifiedValues = {EngineVersion: "8.4.10"}' | stub_response "$RDS"
  run upgrade_engine -r "example-rds" -v 8.4.4 <<< "n"
  assert_success
  local before_prompt="${output%%Nothing was changed*}"
  case "$before_prompt" in
    *"already has a pending upgrade to 8.4.10"*) ;;
    *) fail "expected the pending upgrade warning before the prompt, got: $output" ;;
  esac
}

@test "fails when the RDS does not exist" {
  stub_rds_not_found "$P-describe_db_clusters-db_cluster_identifier-ccb69c87_missing" DBClusterNotFoundFault
  stub_rds_not_found "$P-describe_db_instances-db_instance_identifier-ccb69c87_missing" DBInstanceNotFound
  run --separate-stderr upgrade_engine -r "missing" -v 8.4.10 -y
  assert_failure
  assert_stderr_contains "RDS ccb69c87-missing does not exist"
  refute_stub_called_with "modify-db-"
}

@test "gives the v2 config advice after the upgrade" {
  rds_with '.PendingModifiedValues = {EngineVersion: "8.4.10"}' | restage_on_modify "$RDS"
  run upgrade_engine -r "example-rds" -v 8.4.10 -y
  assert_success
  assert_output_contains "v2 config should give engine_version as major.minor (mysql) or major (postgres); if so, no change is needed."
  assert_output_contains "The configured version was not checked. If engine_version for example-rds in the example-infra staging tfvars (dalmatian terraform-dependencies view-tfvars / set-tfvars) is a full version, change it to 8.4.10 after the upgrade has happened and before the next deploy."
  assert_output_contains "If it is a full version, changing it before then makes the next deploy apply the upgrade immediately."
  assert_output_contains "If it is a full version, leaving it unchanged after the upgrade makes the next deploy fail: AWS will not downgrade."
  assert_output_contains "A deploy that changes this database for any other reason before the window applies the upgrade then."
  refute_stub_called_with "describe-db-instances --filters"
}

@test "gives the v2 config advice in quiet mode" {
  rds_with '.PendingModifiedValues = {EngineVersion: "8.4.10"}' | restage_on_modify "$RDS"
  QUIET_MODE=1 run --separate-stderr upgrade_engine -r "example-rds" -v 8.4.10 -y
  assert_success
  assert_stderr_contains "v2 config should give engine_version as major.minor (mysql) or major (postgres); if so, no change is needed."
  assert_stderr_contains "The configured version was not checked."
  case "$output$stderr" in
    *"Current version:"*) fail "expected -y in quiet mode to leave the summary out, got: $output $stderr" ;;
  esac
}

@test "declining the cluster prompt changes nothing" {
  run upgrade_engine -r "example-cluster" -v "$TARGET" <<< "n"
  assert_success
  assert_output_contains "Aurora cluster: ccb69c87-example-cluster (example-infra staging)"
  assert_output_contains "Current version: 8.0.mysql_aurora.3.05.2"
  assert_output_contains "Maintenance window: mon:19:00-mon:22:00 (UTC)"
  assert_output_contains "Every instance in the cluster restarts during the upgrade."
  assert_output_contains "Nothing was changed"
  assert_call_args dalmatian aws run-command -p example-account rds describe-db-clusters --db-cluster-identifier ccb69c87-example-cluster
  assert_call_args dalmatian aws run-command -p example-account rds describe-db-engine-versions --engine aurora-mysql --engine-version 8.0.mysql_aurora.3.05.2 --include-all
  assert_call_args dalmatian aws run-command -p example-account rds describe-pending-maintenance-actions --resource-identifier "$CLUSTER_ARN"
  assert_call_args dalmatian aws run-command -p example-account rds describe-db-instances --db-instance-identifier ccb69c87-example-cluster-1
  assert_call_args dalmatian aws run-command -p example-account rds describe-pending-maintenance-actions --resource-identifier "$MEMBER_ARN"
  refute_list_called
  refute_stub_called_with "modify-db-"
}

@test "the cluster summary recommends a cluster snapshot" {
  run upgrade_engine -r "example-cluster" -v "$TARGET" <<< "n"
  assert_success
  assert_output_contains "dalmatian aws exec -i example-infra -e staging rds create-db-cluster-snapshot --db-cluster-identifier ccb69c87-example-cluster --db-cluster-snapshot-identifier ccb69c87-example-cluster-pre-8-0-mysql-aurora-3-10-3"
}

@test "the cluster summary lists pending actions for the cluster and its members" {
  pending_action db-upgrade "Upgrade to Aurora MySQL $TARGET" | stub_response "$CLUSTER_PENDING"
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
  run upgrade_engine -r "example-cluster" -v "$TARGET" <<< "n"
  assert_success
  assert_output_contains "db-upgrade: Upgrade to Aurora MySQL $TARGET"
  assert_output_contains "dalmatian aws exec -i example-infra -e staging rds apply-pending-maintenance-action --resource-identifier $CLUSTER_ARN --apply-action db-upgrade --opt-in-type next-maintenance"
  assert_output_contains "dalmatian aws exec -i example-infra -e staging rds apply-pending-maintenance-action --resource-identifier $MEMBER_ARN --apply-action system-update --opt-in-type next-maintenance"
  refute_stub_called_with "apply-pending-maintenance-action"
}

@test "carries on when a member cannot be described" {
  stub_exit "$MEMBER" 254
  run --separate-stderr upgrade_engine -r "example-cluster" -v "$TARGET" <<< "n"
  assert_success
  assert_stderr_contains "Could not look up pending maintenance for cluster member ccb69c87-example-cluster-1."
  assert_output_contains "Nothing was changed"
}

@test "-y queues a cluster upgrade with modify-db-cluster" {
  cluster_with ".PendingModifiedValues = {EngineVersion: \"$TARGET\"}" | restage_on_modify "$CLUSTER"
  run upgrade_engine -r "example-cluster" -v "$TARGET" -y
  assert_success
  assert_call_args dalmatian aws run-command -p example-account rds modify-db-cluster --db-cluster-identifier ccb69c87-example-cluster --engine-version "$TARGET" --no-apply-immediately
  refute_stub_called_with "--allow-major-version-upgrade"
  refute_stub_called_with "modify-db-instance"
  assert_output_contains "Pending engine version: $TARGET"
  assert_output_contains "v2 config should give engine_version as major.minor (mysql) or major (postgres); if so, no change is needed."
}

@test "confirms a queued cluster upgrade AWS has already finished" {
  cluster_with ".EngineVersion = \"$TARGET\"" | restage_on_modify "$CLUSTER"
  run upgrade_engine -r "example-cluster" -v "$TARGET" -y
  assert_success
  assert_output_contains "AWS started the upgrade straight away, in the current maintenance window."
}

@test "-a applies a cluster upgrade immediately" {
  cluster_with '.Status = "upgrading"' | restage_on_modify "$CLUSTER"
  run upgrade_engine -r "example-cluster" -v "$TARGET" -a -y
  assert_success
  assert_call_args dalmatian aws run-command -p example-account rds modify-db-cluster --db-cluster-identifier ccb69c87-example-cluster --engine-version "$TARGET" --apply-immediately
  assert_output_contains "Status: upgrading"
  case "$output" in
    *"before the window applies the upgrade then"*) fail "expected no window warning with -a, got: $output" ;;
  esac
}

@test "confirms a queued cluster upgrade from a db-upgrade action new after the modify" {
  pending_action db-upgrade "Upgrade to Aurora MySQL" | restage_on_modify "$CLUSTER_PENDING"
  run upgrade_engine -r "example-cluster" -v "$TARGET" -y
  assert_success
  assert_output_contains "Pending engine version: $TARGET"
}

@test "confirms a queued cluster upgrade from a stale action naming the short target" {
  pending_action system-update "Aurora MySQL 3.10.3 is available" | stub_response "$CLUSTER_PENDING"
  run upgrade_engine -r "example-cluster" -v "$TARGET" -y
  assert_success
  assert_output_contains "Pending engine version: $TARGET"
}

@test "confirms a queued cluster upgrade from a stale action naming the full target" {
  pending_action db-upgrade "Upgrade to Aurora MySQL $TARGET" | stub_response "$CLUSTER_PENDING"
  run upgrade_engine -r "example-cluster" -v "$TARGET" -y
  assert_success
  assert_output_contains "Pending engine version: $TARGET"
}

@test "does not take a stale action naming a longer version as confirmation" {
  pending_action db-upgrade "Upgrade to Aurora MySQL 3.10.30" | stub_response "$CLUSTER_PENDING"
  run --separate-stderr upgrade_engine -r "example-cluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "could not be confirmed"
}

@test "does not take a stale action naming a longer dotted version as confirmation" {
  pending_action db-upgrade "Upgrade to Aurora MySQL 3.10.3.1 and $TARGET.2" | stub_response "$CLUSTER_PENDING"
  run --separate-stderr upgrade_engine -r "example-cluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "could not be confirmed"
}

@test "does not take the same db-upgrade pending before and after as confirmation" {
  pending_action db-upgrade "Upgrade to Aurora MySQL" | stub_response "$CLUSTER_PENDING"
  run --separate-stderr upgrade_engine -r "example-cluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "could not be confirmed"
}

@test "does not take an unrelated system-update new after the modify as cluster confirmation" {
  pending_action system-update "New Operating System update is available" | restage_on_modify "$CLUSTER_PENDING"
  run --separate-stderr upgrade_engine -r "example-cluster" -v "$TARGET" -y
  assert_failure
  assert_stderr_contains "could not be confirmed"
}

@test "-a does not take a pending db-upgrade as cluster confirmation" {
  pending_action db-upgrade "Upgrade to Aurora MySQL $TARGET" | restage_on_modify "$CLUSTER_PENDING"
  run --separate-stderr upgrade_engine -r "example-cluster" -v "$TARGET" -a -y
  assert_failure
  assert_stderr_contains "could not be confirmed"
}

@test "refuses a major cluster target" {
  run --separate-stderr upgrade_engine -r "example-cluster" -v 8.4.mysql_aurora.4.0.0 -y
  assert_failure
  assert_stderr_contains "Major version upgrades are not supported"
  refute_stub_called_with "modify-db-"
}

@test "picker excludes Aurora members and other infrastructures" {
  run --separate-stderr upgrade_engine -v 8.4.10 -y < /dev/null
  assert_failure
  assert_call_args dalmatian aws run-command -p example-account rds describe-db-clusters
  assert_call_args dalmatian aws run-command -p example-account rds describe-db-instances
  assert_stderr_contains "Pass one explicitly with \`-r\`"
  assert_stderr_contains "example-rds instance mysql 8.4.3"
  assert_stderr_contains "example-cluster cluster aurora-mysql 8.0.mysql_aurora.3.05.2"
  case "$stderr" in
    *example-cluster-1*) fail "expected the Aurora member to be filtered out, got: $stderr" ;;
    *deadbeef*) fail "expected other infrastructures to be filtered out, got: $stderr" ;;
  esac
  refute_stub_called_with "modify-db-"
}

@test "picker returns the only candidate without prompting" {
  stub_response "$CLUSTERS" '{"DBClusters": []}'
  rds_with '.PendingModifiedValues = {EngineVersion: "8.4.10"}' | restage_on_modify "$RDS"
  run upgrade_engine -v 8.4.10 -y < /dev/null
  assert_success
  assert_call_args dalmatian aws run-command -p example-account rds modify-db-instance --db-instance-identifier ccb69c87-example-rds --engine-version 8.4.10 --no-apply-immediately
}
