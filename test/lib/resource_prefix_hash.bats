#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
}

@test "resource_prefix_hash hashes project, infrastructure and environment" {
  run resource_prefix_hash -i "example-infra" -e "staging"
  assert_success
  assert_output "ccb69c87"
}

@test "resource_prefix_hash is sensitive to the environment" {
  run resource_prefix_hash -i "example-infra" -e "staging"
  local staging=$output

  run resource_prefix_hash -i "example-infra" -e "prod"
  assert_success
  [ "$output" != "$staging" ]
}

@test "resource_prefix_hash leaves a letter-leading hash alone with -l" {
  run resource_prefix_hash -i "example-infra" -e "staging" -l
  assert_success
  assert_output "ccb69c87"
}

@test "resource_prefix_hash prefixes a digit-leading hash with h given -l" {
  run resource_prefix_hash -i "infra1" -e "staging"
  assert_success
  assert_output "2823fd26"

  run resource_prefix_hash -i "infra1" -e "staging" -l
  assert_success
  assert_output "h2823fd26"
}

@test "resource_prefix_hash rejects a missing environment" {
  run --separate-stderr resource_prefix_hash -i "example-infra"
  assert_failure
  assert_stderr_contains "Invalid \`resource_prefix_hash\` function usage"
}

@test "resource_prefix_hash rejects a missing infrastructure" {
  run --separate-stderr resource_prefix_hash -e "staging"
  assert_failure
  assert_stderr_contains "Invalid \`resource_prefix_hash\` function usage"
}

@test "resource_prefix_hash rejects an unknown flag" {
  run --separate-stderr resource_prefix_hash -z "nope"
  assert_failure
  assert_stderr_contains "Invalid \`resource_prefix_hash\` function usage"
}

@test "resource_prefix_hash uses the resource override without changing project identity" {
  jq '.terraform_project_name = .project_name | .project_name = "installation-project"' "$CONFIG_SETUP_JSON_FILE" > "$SANDBOX/override.json"
  mv "$SANDBOX/override.json" "$CONFIG_SETUP_JSON_FILE"
  run resource_prefix_hash -i example-infra -e staging
  assert_success
  assert_output "ccb69c87"
}

@test "resource_prefix_hash falls back for an empty resource override" {
  jq '.terraform_project_name = ""' "$CONFIG_SETUP_JSON_FILE" > "$SANDBOX/override.json"
  mv "$SANDBOX/override.json" "$CONFIG_SETUP_JSON_FILE"
  run resource_prefix_hash -i example-infra -e staging
  assert_success
  assert_output "ccb69c87"
}
