#!/usr/bin/env bats

load ../test_helper

# Chosen per test so a tunnel left open on the machine cannot collide
ML_PORT="$(free_local_port)"

HOST="ip-10-0-1-10.eu-west-2.compute.internal"

setup() {
  setup_sandbox
  use_stubs
  stub_dalmatian
  load_all_functions
  export QUIET_MODE=1
  export DALMATIAN_MARKLOGIC_LOCAL_PORT="$ML_PORT"
  export DALMATIAN_MARKLOGIC_TUNNEL_ATTEMPTS=3
  stub_hold dalmatian-aws-run_command-p-example_account-ssm-start_session
  stub_marklogic_api GET "/manage/v2/forests?host-id=$HOST&format=json" marklogic-manage-forests-host-1.json
  stub_marklogic_api GET "/manage/v2/forests/Documents-1?view=status&format=json" marklogic-manage-forest-status-open.json
  stub_marklogic_api GET "/manage/v2/forests/Documents-2-replica?view=status&format=json" marklogic-manage-forest-status-replica.json
  stub_marklogic_api GET "/manage/v2/forests/9001?view=status&format=json" marklogic-manage-forest-status-9001.json

  marklogic_tunnel_open -p example-account -I i-0bbbbbbbbbbbbbbbb -P 8002
}

teardown() {
  marklogic_tunnel_close
}

forests() {
  marklogic_host_forests -H "$HOST" -u example-user -c 'user = "example-user:examplepassword"'
}

@test "marklogic_host_forests lists each forest on the host with its state and its replicas' states" {
  run forests
  assert_success
  assert_line 0 '{"name":"Documents-1","state":"open","replicas":[{"id":"9001","state":"sync replicating"}]}'
  assert_line 1 '{"name":"Documents-2-replica","state":"sync replicating","replicas":[]}'
}

@test "marklogic_host_forests gives an empty state it cannot read rather than guessing" {
  printf '{"forest-status": {"name": "Documents-1"}}\n200\n' \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_forests_Documents_1_view_status_format_json.out"

  run forests
  assert_success
  assert_line 0 '{"name":"Documents-1","state":"","replicas":[]}'
}

@test "marklogic_host_forests prints nothing for a host with no forests" {
  printf '{"forest-default-list": {"list-items": {"list-count": {"value": 0}}}}\n200\n' \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_forests_host_id_ip_10_0_1_10_eu_west_2_compute_internal_format_json.out"

  run forests
  assert_success
  assert_output ""
}

@test "marklogic_host_forests fails when a forest's status cannot be read" {
  stub_marklogic_api GET "/manage/v2/forests/Documents-1?view=status&format=json" - 500

  run --separate-stderr forests
  assert_failure
  assert_stderr_contains "Manage API returned HTTP 500 for the status of forest 'Documents-1'"
}

@test "marklogic_host_forests rejects missing arguments" {
  run --separate-stderr marklogic_host_forests -H "$HOST"
  assert_failure
  assert_stderr_contains "Invalid \`marklogic_host_forests\` function usage"
}
