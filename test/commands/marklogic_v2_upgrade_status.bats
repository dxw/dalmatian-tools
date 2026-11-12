#!/usr/bin/env bats

load ../test_helper

# Chosen per test so a tunnel left open on the machine cannot collide
ML_PORT="$(free_local_port)"

# marklogic/v2/upgrade-status reads each host's software version and the
# cluster's effective version through one tunnel, and says whether an upgrade
# is committed, waiting to be committed, or still part-way across the hosts.
#
# MarkLogic gives versions either as an encoded number (11.3.7 is 11030700)
# or as a dotted string, so the fixtures mix the two.

STACK="cf-ccb69c87-marklogic-cluster"
KEY_PREFIX="dalmatian-aws-run_command-p-example_account"

stub_host_version() {
  local n=$1 version=$2
  jq --argjson v "$version" '.["host-status"]["status-properties"]["software-version"].value = $v' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-host-upgrade-$n.json" > "$SANDBOX/upgrade-$n.json"
  { cat "$SANDBOX/upgrade-$n.json"; echo 200; } \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts_ip_10_0_${n}_10_eu_west_2_compute_internal_view_status_format_json.out"
}

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  stub_response_file dalmatian-deploy-list_infrastructures list-infrastructures.json
  stub_response aws-configure-list_profiles "example-account"
  export MARKLOGIC_PASSWORD="examplepassword"
  export MARKLOGIC_USER="example-user"
  export DALMATIAN_MARKLOGIC_LOCAL_PORT="$ML_PORT"
  export DALMATIAN_MARKLOGIC_TUNNEL_ATTEMPTS=3

  stub_hold "$KEY_PREFIX-ssm-start_session"
  stub_response_file "$KEY_PREFIX-ec2-describe_instances" marklogic-describe-instances.json
  stub_response_file "$KEY_PREFIX-cloudformation-describe_stacks" marklogic-describe-stacks.json
  stub_marklogic_api GET "/manage/v2?format=json" marklogic-manage-cluster.json
  stub_marklogic_api GET "/manage/v2/hosts?format=json" marklogic-manage-hosts.json
  local n
  for n in 1 2 3
  do
    stub_marklogic_api GET "/manage/v2/hosts/ip-10-0-$n-10.eu-west-2.compute.internal?view=status&format=json" "marklogic-manage-host-upgrade-$n.json"
  done
}

upgrade_status() {
  run_command bin/marklogic/v2/upgrade-status -i "example-infra" -e "staging" -s "marklogic-cluster" "$@"
}

@test "upgrade-status prints usage with no arguments" {
  run --separate-stderr run_command bin/marklogic/v2/upgrade-status
  assert_failure 1
  assert_stderr_contains "Usage: upgrade-status"
  assert_output_contains "-s <stack>"
  assert_output_contains "-A "
}

@test "upgrade-status requires the stack key" {
  run --separate-stderr run_command bin/marklogic/v2/upgrade-status -i "example-infra" -e "staging"
  assert_failure 1
  assert_stderr_contains "Usage: upgrade-status"
}

@test "upgrade-status reports each host's version and a committed upgrade" {
  run --separate-stderr upgrade_status
  assert_success
  assert_line 0 "HOST | INSTANCE | SOFTWARE VERSION"
  assert_output_contains "ip-10-0-1-10.eu-west-2.compute.internal | i-0aaaaaaaaaaaaaaaa (marklogic-1) | 11.3.7 (11030700)"
  assert_output_contains "ip-10-0-2-10.eu-west-2.compute.internal | i-0bbbbbbbbbbbbbbbb (No Name) | 11.3.7 (11030700)"
  assert_output_contains "Effective version: 11.3.7 (11030700)"
  assert_output_contains "State: committed"
  assert_call_args dalmatian aws run-command -p example-account ssm start-session --document-name AWS-StartPortForwardingSession --target i-0aaaaaaaaaaaaaaaa --parameters "portNumber=8002,localPortNumber=${ML_PORT}"
}

@test "upgrade-status points out the Security database step, which it cannot check" {
  local QUIET_MODE=0

  run --separate-stderr upgrade_status
  assert_success
  assert_output_contains "Security database upgrade that follows a commit has no REST status"
}

@test "upgrade-status reports an upgrade still part-way across the hosts" {
  stub_host_version 3 11030600

  run --separate-stderr upgrade_status
  assert_failure 1
  assert_output_contains "ip-10-0-3-10.eu-west-2.compute.internal | i-0ccccccccccccccccc (marklogic-3) | 11.3.6 (11030600)"
  assert_output_contains "State: in progress, hosts are on different versions"
}

@test "upgrade-status reports hosts upgraded but the new version not yet committed" {
  jq '.["local-cluster-default"]["effective-version"] = 11030600' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-cluster.json" > "$SANDBOX/cluster.json"
  { cat "$SANDBOX/cluster.json"; echo 200; } \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_format_json.out"

  run --separate-stderr upgrade_status
  assert_failure 1
  assert_output_contains "Effective version: 11.3.6 (11030600)"
  assert_output_contains "State: waiting to commit, every host is on 11.3.7 but the cluster runs as 11.3.6"
}

@test "upgrade-status understands versions given as dotted strings" {
  stub_host_version 1 '"11.3.7"'
  stub_host_version 2 '"11.3.7"'
  stub_host_version 3 '"11.3.7"'

  run --separate-stderr upgrade_status
  assert_success
  assert_line 1 "ip-10-0-1-10.eu-west-2.compute.internal | i-0aaaaaaaaaaaaaaaa (marklogic-1) | 11.3.7"
  assert_output_contains "State: committed"
}

@test "upgrade-status reports a version it cannot read rather than guessing" {
  jq 'del(.["host-status"]["status-properties"]["software-version"])' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-host-upgrade-2.json" > "$SANDBOX/upgrade-2.json"
  { cat "$SANDBOX/upgrade-2.json"; echo 200; } \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts_ip_10_0_2_10_eu_west_2_compute_internal_view_status_format_json.out"

  run --separate-stderr upgrade_status
  assert_failure 1
  assert_output_contains "| i-0bbbbbbbbbbbbbbbb (No Name) | unknown"
  assert_output_contains "State: unknown"
}

@test "upgrade-status exits 2 when no node is reachable" {
  stub_exit "$KEY_PREFIX-ssm-start_session" 1

  run --separate-stderr upgrade_status
  assert_failure 2
  assert_stderr_contains "No node of stack '$STACK' is reachable through Systems Manager"
}

@test "upgrade-status refuses to run with no username" {
  unset MARKLOGIC_USER

  run --separate-stderr upgrade_status < /dev/null
  assert_failure 1
  assert_stderr_contains "No MarkLogic username given"
  refute_stub_called_with "start-session"
}

@test "upgrade-status never puts the password on a command line" {
  run upgrade_status
  assert_success
  refute_stub_called_with "examplepassword"
  assert_stub_called_with "--config /dev/fd/"
}
