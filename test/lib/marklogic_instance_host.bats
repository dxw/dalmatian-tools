#!/usr/bin/env bats

load ../test_helper

# Chosen per test so a tunnel left open on the machine cannot collide
ML_PORT="$(free_local_port)"

setup() {
  setup_sandbox
  use_stubs
  stub_dalmatian
  load_all_functions
  export QUIET_MODE=1
  export DALMATIAN_MARKLOGIC_LOCAL_PORT="$ML_PORT"
  export DALMATIAN_MARKLOGIC_TUNNEL_ATTEMPTS=3
  stub_hold dalmatian-aws-run_command-p-example_account-ssm-start_session
  stub_marklogic_api GET "/manage/v2/hosts?format=json" marklogic-manage-hosts.json

  marklogic_tunnel_open -p example-account -I i-0bbbbbbbbbbbbbbbb -P 8002
}

teardown() {
  marklogic_tunnel_close
}

host_of() {
  marklogic_instance_host -j "$(fixture_json marklogic-describe-instances.json)" -I "$1" -u example-user -c 'user = "example-user:examplepassword"'
}

@test "marklogic_instance_host finds the host named after the node's managed network interface" {
  run host_of i-0aaaaaaaaaaaaaaaa
  assert_success
  assert_output "ip-10-0-1-10.eu-west-2.compute.internal"
}

@test "marklogic_instance_host finds a host named after the node's primary address" {
  run host_of i-0bbbbbbbbbbbbbbbb
  assert_success
  assert_output "ip-10-0-2-10.eu-west-2.compute.internal"
}

@test "marklogic_instance_host fails when no MarkLogic host matches the node" {
  jq '.["host-default-list"]["list-items"]["list-item"] |= map(select(.nameref != "ip-10-0-3-10.eu-west-2.compute.internal"))' \
    "$DALMATIAN_ROOT/test/fixtures/marklogic-manage-hosts.json" > "$SANDBOX/hosts.json"
  { cat "$SANDBOX/hosts.json"; echo 200; } \
    > "$DALMATIAN_STUB_RESPONSES/curl-request-GET-url-http___localhost_${ML_PORT}_manage_v2_hosts_format_json.out"

  run --separate-stderr host_of i-0ccccccccccccccccc
  assert_failure
  assert_stderr_contains "No MarkLogic host in the cluster matches i-0ccccccccccccccccc"
}

@test "marklogic_instance_host fails when the host list is refused" {
  stub_marklogic_api GET "/manage/v2/hosts?format=json" - 401

  run --separate-stderr host_of i-0aaaaaaaaaaaaaaaa
  assert_failure
  assert_stderr_contains "Manage API returned HTTP 401 for user 'example-user' when listing hosts"
}

@test "marklogic_instance_host rejects missing arguments" {
  run --separate-stderr marklogic_instance_host -I i-0aaaaaaaaaaaaaaaa
  assert_failure
  assert_stderr_contains "Invalid \`marklogic_instance_host\` function usage"
}
