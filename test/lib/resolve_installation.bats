#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
  export APP_ROOT="$SANDBOX/app"
  mkdir -p "$APP_ROOT/tmp"
  unset DALMATIAN_INSTALLATION
}

make_installation() {
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/$1"
  install_fixture setup.json "$CONFIG_INSTALLATIONS_DIR/$1/setup.json"
}

@test "resolve_installation exports empty values when nothing is configured" {
  resolve_installation probe
  [ "$DALMATIAN_INSTALLATION" = "" ]
  [ "$CONFIG_INSTALLATION_DIR" = "" ]
}

@test "resolve_installation uses the default from installations.json" {
  make_installation example-project
  set_installation_default example-project

  resolve_installation probe
  [ "$DALMATIAN_INSTALLATION" = "example-project" ]
  [ "$CONFIG_INSTALLATION_DIR" = "$CONFIG_INSTALLATIONS_DIR/example-project" ]
}

@test "resolve_installation prefers DALMATIAN_INSTALLATION over the default" {
  make_installation example-project
  make_installation other
  set_installation_default example-project
  export DALMATIAN_INSTALLATION=other

  resolve_installation probe
  [ "$DALMATIAN_INSTALLATION" = "other" ]
  [ "$CONFIG_INSTALLATION_DIR" = "$CONFIG_INSTALLATIONS_DIR/other" ]
}

@test "resolve_installation treats an empty DALMATIAN_INSTALLATION as unset" {
  make_installation example-project
  set_installation_default example-project
  export DALMATIAN_INSTALLATION=""

  resolve_installation probe
  [ "$DALMATIAN_INSTALLATION" = "example-project" ]
}

@test "resolve_installation exports the variables so child processes see them" {
  make_installation example-project
  set_installation_default example-project

  resolve_installation probe
  run bash -c 'printf "%s\n%s\n" "$DALMATIAN_INSTALLATION" "$CONFIG_INSTALLATION_DIR"'
  assert_line 0 "example-project"
  assert_line 1 "$CONFIG_INSTALLATIONS_DIR/example-project"
}

@test "resolve_installation fails when the environment selects a missing installation" {
  export DALMATIAN_INSTALLATION=nope

  run --separate-stderr resolve_installation probe
  assert_failure 1
  assert_stderr_contains "Dalmatian installation 'nope' does not exist"
  assert_stderr_contains "DALMATIAN_INSTALLATION environment variable"
  assert_stderr_contains "dalmatian installation list"
}

@test "resolve_installation fails when the default selects a missing installation" {
  set_installation_default nope

  run --separate-stderr resolve_installation probe
  assert_failure 1
  assert_stderr_contains "Dalmatian installation 'nope' does not exist"
  assert_stderr_contains "the default in $CONFIG_INSTALLATIONS_JSON_FILE"
  assert_stderr_contains "dalmatian installation list"
}

@test "resolve_installation rejects an invalid name from the environment" {
  export DALMATIAN_INSTALLATION="../escape"

  run --separate-stderr resolve_installation probe
  assert_failure 1
  assert_stderr_contains "'../escape' is not a valid installation name"
}

@test "resolve_installation lets setup, installation and update run against a missing installation" {
  export DALMATIAN_INSTALLATION=new-one

  for subcommand in setup installation update
  do
    run resolve_installation "$subcommand"
    assert_success
  done
}

@test "resolve_installation still exports the selected name for exempt subcommands" {
  export DALMATIAN_INSTALLATION=new-one

  resolve_installation setup
  [ "$DALMATIAN_INSTALLATION" = "new-one" ]
  [ "$CONFIG_INSTALLATION_DIR" = "$CONFIG_INSTALLATIONS_DIR/new-one" ]
}

@test "resolve_installation skips resolution for version" {
  export DALMATIAN_INSTALLATION=nope

  run resolve_installation version
  assert_success
}

@test "resolve_installation does not migrate for version" {
  legacy_config_sandbox

  run resolve_installation version
  assert_success
  [ -f "$CONFIG_DIR/setup.json" ]
  [ ! -e "$CONFIG_INSTALLATIONS_JSON_FILE" ]
}

@test "resolve_installation migrates a legacy layout and selects it" {
  legacy_config_sandbox

  resolve_installation probe
  [ "$DALMATIAN_INSTALLATION" = "example-project" ]
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json" ]
  [ ! -e "$CONFIG_DIR/setup.json" ]
}

@test "resolve_installation migrates even when the environment selects another installation" {
  legacy_config_sandbox
  make_installation other
  export DALMATIAN_INSTALLATION=other

  resolve_installation probe
  [ "$DALMATIAN_INSTALLATION" = "other" ]
  [ -f "$CONFIG_INSTALLATIONS_DIR/example-project/setup.json" ]
}
