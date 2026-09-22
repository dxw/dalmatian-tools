#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

load ../test_helper

setup() {
  setup_sandbox
  load_all_functions
  # Start from the state a script run by path sees: nothing resolved yet
  unset DALMATIAN_INSTALLATION CONFIG_INSTALLATION_DIR \
        CONFIG_SETUP_JSON_FILE CONFIG_AWS_SSO_FILE \
        CONFIG_DIR CONFIG_INSTALLATIONS_DIR CONFIG_INSTALLATIONS_JSON_FILE
}

@test "export_installation_config points the config paths at the default installation" {
  mkdir -p "$HOME/.config/dalmatian/installations/example-project"
  printf '{"default": "example-project"}\n' > "$HOME/.config/dalmatian/installations.json"

  export_installation_config aws

  [ "$DALMATIAN_INSTALLATION" = "example-project" ]
  [ "$CONFIG_DIR" = "$HOME/.config/dalmatian" ]
  [ "$CONFIG_SETUP_JSON_FILE" = "$HOME/.config/dalmatian/installations/example-project/setup.json" ]
  [ "$CONFIG_AWS_SSO_FILE" = "$HOME/.config/dalmatian/installations/example-project/dalmatian-sso.config" ]
}

@test "export_installation_config follows DALMATIAN_INSTALLATION over the default" {
  mkdir -p "$HOME/.config/dalmatian/installations/example-project" \
           "$HOME/.config/dalmatian/installations/other"
  printf '{"default": "example-project"}\n' > "$HOME/.config/dalmatian/installations.json"
  export DALMATIAN_INSTALLATION=other

  export_installation_config aws

  [ "$CONFIG_SETUP_JSON_FILE" = "$HOME/.config/dalmatian/installations/other/setup.json" ]
  [ "$CONFIG_AWS_SSO_FILE" = "$HOME/.config/dalmatian/installations/other/dalmatian-sso.config" ]
}

@test "export_installation_config leaves the config paths empty with no installation" {
  export_installation_config aws

  [ -z "$DALMATIAN_INSTALLATION" ]
  [ -z "$CONFIG_INSTALLATION_DIR" ]
  [ -z "$CONFIG_SETUP_JSON_FILE" ]
  [ -z "$CONFIG_AWS_SSO_FILE" ]
}
