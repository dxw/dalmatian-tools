#!/usr/bin/env bats

load ../test_helper

# list-infrastructures shells back into the CLI twice for `terraform workspace
# list`: once for the infrastructure project (-i) and once for account
# bootstrap (-a). Both are answered here in terraform's own output format,
# including the `* ` marker on the selected workspace and the `default` entry
# that must never be treated as an account or infrastructure.
setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  stub_response dalmatian-terraform_dependencies-run_terraform_command-c-workspace_list-a-q <<'WS'
  default
  000000000001-eu-west-2-example-account
* 000000000002-eu-west-2-other-account
  000000000003-eu-west-2-empty-account
WS
  stub_response dalmatian-terraform_dependencies-run_terraform_command-c-workspace_list-i-q <<'WS'
  default
  000000000001-eu-west-2-example-account-example-infra-prod
* 000000000001-eu-west-2-example-account-example-infra-staging
  000000000001-eu-west-2-example-account-second-infra-staging
  000000000002-eu-west-2-other-account-other-infra-prod
WS
}

@test "list-infrastructures prints valid JSON with an accounts object" {
  run run_command bin/deploy/v2/list-infrastructures
  assert_success
  echo "$output" | jq -e '.accounts | type == "object"' > /dev/null
}

@test "list-infrastructures keeps every environment of an infrastructure" {
  run run_command bin/deploy/v2/list-infrastructures
  assert_success
  [ "$(echo "$output" | jq -c '.accounts["000000000001-eu-west-2-example-account"].infrastructures["example-infra"].environments')" = '["prod","staging"]' ]
  [ "$(echo "$output" | jq -c '.accounts["000000000001-eu-west-2-example-account"].infrastructures["example-infra"].workspaces')" = '["000000000001-eu-west-2-example-account-example-infra-prod","000000000001-eu-west-2-example-account-example-infra-staging"]' ]
}

@test "list-infrastructures keeps every infrastructure in an account" {
  run run_command bin/deploy/v2/list-infrastructures
  assert_success
  [ "$(echo "$output" | jq -r '.accounts["000000000001-eu-west-2-example-account"].infrastructures | keys | join(",")')" = "example-infra,second-infra" ]
  [ "$(echo "$output" | jq -c '.accounts["000000000001-eu-west-2-example-account"].infrastructures["second-infra"].environments')" = '["staging"]' ]
}

@test "list-infrastructures assigns each infrastructure to its own account" {
  run run_command bin/deploy/v2/list-infrastructures
  assert_success
  [ "$(echo "$output" | jq -r '.accounts["000000000002-eu-west-2-other-account"].infrastructures | keys | join(",")')" = "other-infra" ]
  [ "$(echo "$output" | jq -r '.accounts["000000000002-eu-west-2-other-account"].infrastructures["other-infra"].environments[0]')" = "prod" ]
}

@test "list-infrastructures omits accounts with no infrastructures and the default workspace" {
  run run_command bin/deploy/v2/list-infrastructures
  assert_success
  [ "$(echo "$output" | jq -r '.accounts | keys | join(",")')" = "000000000001-eu-west-2-example-account,000000000002-eu-west-2-other-account" ]
  case "$output" in
    *default*) fail "the default workspace leaked into the listing: $output" ;;
  esac
}

@test "list-infrastructures prints an empty accounts object when there are no infrastructures" {
  stub_response dalmatian-terraform_dependencies-run_terraform_command-c-workspace_list-i-q "* default"

  run run_command bin/deploy/v2/list-infrastructures
  assert_success
  [ "$(echo "$output" | jq -c .)" = '{"accounts":{}}' ]
}
