#!/usr/bin/env bats

load ../test_helper

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
  write_setup_json
}

write_setup_json() {
  cat > "$CONFIG_SETUP_JSON_FILE" <<'JSON'
{
  "project_name": "example-project",
  "main_dalmatian_account_id": "111111111111",
  "default_region": "eu-west-2",
  "aws_sso": {
    "start_url": "https://example.awsapps.com/start",
    "region": "eu-west-2",
    "registration_scopes": "sso:account:access",
    "default_admin_role_name": "AdministratorAccess"
  }
}
JSON
}

# What `terraform workspace list` prints for the account-bootstrap project: the
# main account, an account inside the SSO organisation and one onboarded with
# `account-init -e`, whose ID carries the E prefix
stub_workspaces() {
  stub_response dalmatian-terraform_dependencies-run_terraform_command-c-workspace_list-a-q <<'LIST'
* default
  111111111111-eu-west-2-dalmatian-main
  222222222222-eu-west-2-example-account
  E333333333333-eu-west-2-external-account
LIST
}

# An existing configuration from an earlier setup: stale bootstrap profiles
# followed by an account profile that must survive a failed run
seed_existing_config() {
  cat > "$CONFIG_AWS_SSO_FILE" <<'CONFIG'
# hand-written note that must survive
[profile dalmatian-login]
sso_start_url = https://old.awsapps.com/start
sso_region = eu-west-1
sso_registration_scopes = sso:account:access

[profile dalmatian-main]
sso_start_url = https://old.awsapps.com/start
sso_region = eu-west-1
sso_account_id = 999999999999
sso_role_name = AdministratorAccess
region = eu-west-1
[profile example-account]
sso_start_url = https://old.awsapps.com/start
sso_region = eu-west-1
sso_account_id = 888888888888
sso_role_name = AdministratorAccess
region = eu-west-1
[profile keep-me]
sso_session = keep-me-session
region = eu-west-2
[sso-session keep-me-session]
sso_start_url = https://example.awsapps.com/start
sso_region = eu-west-2
CONFIG
}

assert_no_temp_config_files() {
  run find "$CONFIG_INSTALLATION_DIR" -name '.dalmatian-sso.config.*'
  assert_output ""
}

@test "generate-config -h shows usage without touching the configuration" {
  seed_existing_config

  run --separate-stderr run_command bin/aws/v2/generate-config -h
  assert_failure 1
  assert_stderr_contains "Usage: generate-config"
  assert_stderr_contains "Generate the AWS SSO profiles"
  grep -q '^\[profile keep-me\]' "$CONFIG_AWS_SSO_FILE"
  refute_stub_called_with "aws login"
  refute_stub_called_with "terraform-dependencies"
}

@test "generate-config rejects unknown options" {
  seed_existing_config

  run --separate-stderr run_command bin/aws/v2/generate-config -x
  assert_failure 1
  assert_stderr_contains "Usage: generate-config"
  grep -q '^\[profile keep-me\]' "$CONFIG_AWS_SSO_FILE"
  refute_stub_called_with "aws login"
}

@test "generate-config rejects trailing arguments" {
  seed_existing_config

  run --separate-stderr run_command bin/aws/v2/generate-config example-project
  assert_failure 1
  assert_stderr_contains "Usage: generate-config"
  grep -q '^\[profile keep-me\]' "$CONFIG_AWS_SSO_FILE"
  refute_stub_called_with "aws login"
}

@test "generate-config writes a profile for every account workspace" {
  stub_workspaces

  run run_command bin/aws/v2/generate-config
  assert_success

  assert_stub_called_with "dalmatian aws login -p dalmatian-login"
  assert_stub_called_with "dalmatian terraform-dependencies clone"
  assert_stub_called_with "dalmatian terraform-dependencies initialise"

  grep -q '^\[profile dalmatian-login\]' "$CONFIG_AWS_SSO_FILE"
  grep -q '^sso_registration_scopes = sso:account:access$' "$CONFIG_AWS_SSO_FILE"
  grep -q '^\[profile dalmatian-main\]' "$CONFIG_AWS_SSO_FILE"
  grep -q '^sso_account_id = 111111111111$' "$CONFIG_AWS_SSO_FILE"
  grep -q '^\[profile example-account\]' "$CONFIG_AWS_SSO_FILE"
  grep -q '^sso_account_id = 222222222222$' "$CONFIG_AWS_SSO_FILE"
  grep -q '^\[profile external-account\]' "$CONFIG_AWS_SSO_FILE"
  grep -q '^source_profile = dalmatian-main$' "$CONFIG_AWS_SSO_FILE"
  grep -q '^role_arn = arn:aws:iam::333333333333:role/111111111111-dalmatian-access$' "$CONFIG_AWS_SSO_FILE"
  run ! grep -q '^\[profile default\]' "$CONFIG_AWS_SSO_FILE"
  assert_no_temp_config_files
}

@test "generate-config regenerates the profiles it owns and keeps every other section" {
  seed_existing_config
  stub_workspaces

  run run_command bin/aws/v2/generate-config
  assert_success

  # Generated profiles are replaced, once each, with the current values
  for profile in dalmatian-login dalmatian-main example-account external-account
  do
    run grep -c "^\[profile $profile\]" "$CONFIG_AWS_SSO_FILE"
    assert_output "1"
  done
  grep -q '^sso_account_id = 222222222222$' "$CONFIG_AWS_SSO_FILE"
  run ! grep -q '888888888888' "$CONFIG_AWS_SSO_FILE"
  run ! grep -q 'old.awsapps.com' "$CONFIG_AWS_SSO_FILE"

  # Everything the user put there is carried over
  grep -q '^# hand-written note that must survive$' "$CONFIG_AWS_SSO_FILE"
  grep -q '^\[profile keep-me\]' "$CONFIG_AWS_SSO_FILE"
  grep -q '^sso_session = keep-me-session$' "$CONFIG_AWS_SSO_FILE"
  grep -q '^\[sso-session keep-me-session\]' "$CONFIG_AWS_SSO_FILE"
  assert_no_temp_config_files
}

@test "generate-config is stable across repeated runs" {
  seed_existing_config
  stub_workspaces

  run run_command bin/aws/v2/generate-config
  assert_success
  run run_command bin/aws/v2/generate-config
  assert_success

  for profile in dalmatian-login dalmatian-main example-account external-account keep-me
  do
    run grep -c "^\[profile $profile\]" "$CONFIG_AWS_SSO_FILE"
    assert_output "1"
  done
  run grep -c '^\[sso-session keep-me-session\]' "$CONFIG_AWS_SSO_FILE"
  assert_output "1"
  run grep -c '^# hand-written note that must survive$' "$CONFIG_AWS_SSO_FILE"
  assert_output "1"
  assert_no_temp_config_files
}

@test "generate-config keeps the existing account profiles when initialise fails" {
  seed_existing_config
  stub_workspaces
  stub_exit dalmatian-terraform_dependencies-initialise 1

  run run_command bin/aws/v2/generate-config
  assert_failure 1
  grep -q '^\[profile keep-me\]' "$CONFIG_AWS_SSO_FILE"
  grep -q '^sso_account_id = 888888888888$' "$CONFIG_AWS_SSO_FILE"
  run ! grep -q '^\[profile external-account\]' "$CONFIG_AWS_SSO_FILE"
  assert_no_temp_config_files
}

@test "generate-config refreshes the bootstrap profiles from setup.json before logging in" {
  seed_existing_config
  stub_workspaces
  stub_exit dalmatian-terraform_dependencies-initialise 1

  run run_command bin/aws/v2/generate-config
  assert_failure 1
  assert_stub_called_with "dalmatian aws login -p dalmatian-login"
  grep -q '^sso_start_url = https://example.awsapps.com/start$' "$CONFIG_AWS_SSO_FILE"
  grep -q '^sso_account_id = 111111111111$' "$CONFIG_AWS_SSO_FILE"
  run ! grep -q '999999999999' "$CONFIG_AWS_SSO_FILE"
  run grep -c '^\[profile dalmatian-login\]' "$CONFIG_AWS_SSO_FILE"
  assert_output "1"
  run grep -c '^\[profile dalmatian-main\]' "$CONFIG_AWS_SSO_FILE"
  assert_output "1"
  grep -q '^\[profile keep-me\]' "$CONFIG_AWS_SSO_FILE"
  grep -q '^sso_session = keep-me-session$' "$CONFIG_AWS_SSO_FILE"
  grep -q '^\[sso-session keep-me-session\]' "$CONFIG_AWS_SSO_FILE"
  grep -q '^# hand-written note that must survive$' "$CONFIG_AWS_SSO_FILE"
}

@test "generate-config keeps the existing configuration when the workspace list fails" {
  seed_existing_config
  stub_exit dalmatian-terraform_dependencies-run_terraform_command-c-workspace_list-a-q 1

  run run_command bin/aws/v2/generate-config
  assert_failure 1
  grep -q '^\[profile keep-me\]' "$CONFIG_AWS_SSO_FILE"
  grep -q '^sso_account_id = 888888888888$' "$CONFIG_AWS_SSO_FILE"
  run ! grep -q '^\[profile external-account\]' "$CONFIG_AWS_SSO_FILE"
  assert_no_temp_config_files
}

@test "generate-config seeds a missing configuration with the profiles the login needs" {
  stub_workspaces
  stub_exit dalmatian-terraform_dependencies-initialise 1

  run run_command bin/aws/v2/generate-config
  assert_failure 1
  grep -q '^\[profile dalmatian-login\]' "$CONFIG_AWS_SSO_FILE"
  grep -q '^\[profile dalmatian-main\]' "$CONFIG_AWS_SSO_FILE"
  run ! grep -q '^\[profile example-account\]' "$CONFIG_AWS_SSO_FILE"
  assert_no_temp_config_files
}
