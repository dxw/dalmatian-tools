#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
  export APP_ROOT="$SANDBOX/app"
  mkdir -p "$APP_ROOT/tmp"
  installation_sandbox
}

legacy_working_copies() {
  mkdir -p "$APP_ROOT/tmp/terraform-dxw-dalmatian-account-bootstrap/.terraform"
  mkdir -p "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure/.terraform"
  mkdir -p "$APP_ROOT/tmp/service-environment-files"
  printf 'x\n' > "$APP_ROOT/tmp/service-environment-files/example.env"
}

@test "adopt_legacy_working_copies does nothing when tmp/ holds no legacy items" {
  run adopt_legacy_working_copies
  assert_success
  assert_output ""
  [ ! -e "$APP_ROOT/tmp/example-project" ]
}

@test "adopt_legacy_working_copies copes with no tmp directory at all" {
  rm -rf "$APP_ROOT/tmp"

  run adopt_legacy_working_copies
  assert_success
  [ ! -e "$APP_ROOT/tmp" ]
}

@test "adopt_legacy_working_copies moves the legacy items into the default installation's tmp" {
  legacy_working_copies

  run adopt_legacy_working_copies
  assert_success
  [ -d "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-account-bootstrap/.terraform" ]
  [ -d "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-infrastructure/.terraform" ]
  [ -f "$APP_ROOT/tmp/example-project/service-environment-files/example.env" ]
  [ ! -e "$APP_ROOT/tmp/terraform-dxw-dalmatian-account-bootstrap" ]
  [ ! -e "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure" ]
  [ ! -e "$APP_ROOT/tmp/service-environment-files" ]
}

@test "adopt_legacy_working_copies logs what it moved" {
  legacy_working_copies

  run adopt_legacy_working_copies
  assert_success
  assert_output_contains "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure"
  assert_output_contains "installation 'example-project'"
}

@test "adopt_legacy_working_copies is silent in quiet mode" {
  legacy_working_copies
  export QUIET_MODE=1

  run adopt_legacy_working_copies
  assert_success
  assert_output ""
}

@test "adopt_legacy_working_copies skips legacy items that do not exist" {
  mkdir -p "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure"

  run adopt_legacy_working_copies
  assert_success
  [ -d "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-infrastructure" ]
  [ ! -e "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-account-bootstrap" ]
}

# The legacy layout predates installations, so its working copies belong to
# the installation the migration created, which became the default -- not to
# whichever installation DALMATIAN_INSTALLATION happens to select now
@test "adopt_legacy_working_copies moves into the default even when another installation is selected" {
  legacy_working_copies
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/other"
  export DALMATIAN_INSTALLATION=other

  run adopt_legacy_working_copies
  assert_success
  [ -d "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-infrastructure" ]
  [ ! -e "$APP_ROOT/tmp/other" ]
}

@test "adopt_legacy_working_copies warns and leaves a legacy item alone when the destination is occupied" {
  mkdir -p "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure/.terraform"
  mkdir -p "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-infrastructure"
  printf 'keep\n' > "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-infrastructure/marker"

  run --separate-stderr adopt_legacy_working_copies
  assert_success
  assert_stderr_contains "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure"
  assert_stderr_contains "no longer used"
  [ -d "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure/.terraform" ]
  run cat "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-infrastructure/marker"
  assert_output "keep"
}

@test "adopt_legacy_working_copies still moves the other items when one destination is occupied" {
  legacy_working_copies
  mkdir -p "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-infrastructure"

  run adopt_legacy_working_copies
  assert_success
  [ -d "$APP_ROOT/tmp/example-project/terraform-dxw-dalmatian-account-bootstrap/.terraform" ]
  [ -f "$APP_ROOT/tmp/example-project/service-environment-files/example.env" ]
  [ -d "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure/.terraform" ]
}

@test "adopt_legacy_working_copies does nothing when no default installation is recorded" {
  legacy_working_copies
  rm -f "$CONFIG_INSTALLATIONS_JSON_FILE"

  run adopt_legacy_working_copies
  assert_success
  [ -d "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure/.terraform" ]
  [ ! -e "$APP_ROOT/tmp/example-project" ]
}

@test "adopt_legacy_working_copies does nothing when the default installation's directory is missing" {
  legacy_working_copies
  rm -rf "$CONFIG_INSTALLATION_DIR"

  run adopt_legacy_working_copies
  assert_success
  [ -d "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure/.terraform" ]
  [ ! -e "$APP_ROOT/tmp/example-project" ]
}

# Moving tmp/<item> into tmp/<item>/<item> would move it inside itself. Only
# that item is affected; the others still belong under tmp/<name>/
@test "adopt_legacy_working_copies skips only the legacy item that shares the default installation's name" {
  legacy_working_copies
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/service-environment-files"
  set_installation_default service-environment-files

  run --separate-stderr adopt_legacy_working_copies
  assert_success
  assert_stderr_contains "$APP_ROOT/tmp/service-environment-files"
  assert_stderr_contains "inside itself"
  [ -f "$APP_ROOT/tmp/service-environment-files/example.env" ]
  [ ! -e "$APP_ROOT/tmp/service-environment-files/service-environment-files" ]
  [ -d "$APP_ROOT/tmp/service-environment-files/terraform-dxw-dalmatian-account-bootstrap/.terraform" ]
  [ -d "$APP_ROOT/tmp/service-environment-files/terraform-dxw-dalmatian-infrastructure/.terraform" ]
  [ ! -e "$APP_ROOT/tmp/terraform-dxw-dalmatian-account-bootstrap" ]
  [ ! -e "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure" ]
}

# With DALMATIAN_INSTALLATION set, resolve_installation validates that name
# and never the recorded default, so the default is checked here before it is
# used to build a destination path
@test "adopt_legacy_working_copies does nothing when the recorded default is not a valid name" {
  legacy_working_copies
  printf '%s\n' '{"default": "../escape"}' > "$CONFIG_INSTALLATIONS_JSON_FILE"
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/../escape"
  export DALMATIAN_INSTALLATION=example-project

  run adopt_legacy_working_copies
  assert_success
  [ -d "$APP_ROOT/tmp/terraform-dxw-dalmatian-infrastructure/.terraform" ]
  [ ! -e "$APP_ROOT/tmp/../escape" ]
}
