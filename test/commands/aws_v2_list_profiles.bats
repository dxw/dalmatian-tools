#!/usr/bin/env bats

load ../test_helper

# list-profiles has no getopts/usage() at all, so there is nothing to
# validate here: every test exercises the workspace-filtering logic instead.

setup() {
  setup_sandbox
  use_stubs
  export QUIET_MODE=1
  stub_cli
}

@test "list-profiles extracts account names from terraform workspaces" {
  stub_response dalmatian-terraform_dependencies-run_terraform_command <<'WORKSPACES'
  default
* dalmatian-aws-account-000-example-account
  dalmatian-aws-account-111-other-account
WORKSPACES

  run run_command bin/aws/v2/list-profiles
  assert_success
  assert_line 0 "example-account"
  assert_line 1 "other-account"
}

@test "list-profiles excludes the default workspace" {
  stub_response dalmatian-terraform_dependencies-run_terraform_command <<'WORKSPACES'
* default
  dalmatian-aws-account-000-example-account
WORKSPACES

  run run_command bin/aws/v2/list-profiles
  assert_success
  refute_output_line "default"
}

@test "list-profiles excludes a workspace matching MAIN_WORKSPACE_NAME" {
  export MAIN_WORKSPACE_NAME="dalmatian-aws-account-000-example-account"
  stub_response dalmatian-terraform_dependencies-run_terraform_command <<'WORKSPACES'
  default
* dalmatian-aws-account-000-example-account
  dalmatian-aws-account-111-other-account
WORKSPACES

  run run_command bin/aws/v2/list-profiles
  assert_success
  refute_output_line "example-account"
  assert_line 0 "other-account"
}

@test "list-profiles asks the CLI for the workspace list" {
  stub_response dalmatian-terraform_dependencies-run_terraform_command "* default"

  run run_command bin/aws/v2/list-profiles
  assert_success
  assert_stub_called_with "terraform-dependencies run-terraform-command -c workspace list -a -q"
}

@test "list-profiles prints nothing and still exits 0 when the CLI call fails" {
  # The workspace list is read through \`< <(...)\` process substitution, so
  # a non-zero exit from the dalmatian call is invisible to \`set -e\` here:
  # the loop simply sees no lines and the script exits 0 regardless.
  stub_exit dalmatian-terraform_dependencies-run_terraform_command 1

  run run_command bin/aws/v2/list-profiles
  assert_success
  assert_output ""
}
