#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
}

@test "dalmatian_v1_sso_available is false with no configuration at all" {
  run dalmatian_v1_sso_available
  assert_failure
}

@test "dalmatian_v1_sso_available is false with setup.json but no sso config" {
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"

  run dalmatian_v1_sso_available
  assert_failure
}

@test "dalmatian_v1_sso_available is false with an sso config but no setup.json" {
  install_fixture dalmatian-sso.config "$CONFIG_AWS_SSO_FILE"

  run dalmatian_v1_sso_available
  assert_failure
}

@test "dalmatian_v1_sso_available is true with both files present and valid" {
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  install_fixture dalmatian-sso.config "$CONFIG_AWS_SSO_FILE"

  run dalmatian_v1_sso_available
  assert_success
}

@test "dalmatian_v1_sso_available is false without a start_url" {
  printf '%s\n' '{"project_name": "example-project"}' > "$CONFIG_SETUP_JSON_FILE"
  install_fixture dalmatian-sso.config "$CONFIG_AWS_SSO_FILE"

  run dalmatian_v1_sso_available
  assert_failure
}

@test "dalmatian_v1_sso_available is false when start_url is not a string" {
  printf '%s\n' '{"aws_sso": {"start_url": 42}}' > "$CONFIG_SETUP_JSON_FILE"
  install_fixture dalmatian-sso.config "$CONFIG_AWS_SSO_FILE"

  run dalmatian_v1_sso_available
  assert_failure
}

@test "dalmatian_v1_sso_available is false on unparseable setup.json" {
  printf '%s\n' 'not json at all' > "$CONFIG_SETUP_JSON_FILE"
  install_fixture dalmatian-sso.config "$CONFIG_AWS_SSO_FILE"

  run dalmatian_v1_sso_available
  assert_failure
}

@test "dalmatian_v1_sso_available is false without a dalmatian-main profile" {
  install_fixture setup.json "$CONFIG_SETUP_JSON_FILE"
  printf '%s\n' '[profile dalmatian-login]' > "$CONFIG_AWS_SSO_FILE"

  run dalmatian_v1_sso_available
  assert_failure
}
