#!/usr/bin/env bash
set -e
set -o pipefail

# Move a pre-installations Dalmatian configuration into installations/<name>/.
#
# Before installations existed, `dalmatian setup` wrote setup.json, the AWS SSO
# config, the two Terraform backend vars files and .cache/ straight into the
# config dir root, and the Terraform working copies into tmp/ under the tools
# checkout. This moves all of that under one installation named after
# setup.json's project_name (or 'default' when that is unusable) and records it
# as the default installation.
#
# A legacy layout is recognised by setup.json at the root with no
# installations.json. The tmp/ working copies move first, then the config
# items with setup.json last, then installations.json is written last, so an
# interrupted run is recognised as legacy again next time and resumes:
# anything already moved is skipped.
# Both a root setup.json and an installations.json means somebody has edited
# by hand, so the function refuses rather than guess.
#
# @usage migrate_legacy_installation
function migrate_legacy_installation {
  local legacy_setup name item source destination
  local -a config_items=(
    dalmatian-sso.config
    account-bootstrap-backend.vars
    infrastructure-backend.vars
    .cache
    setup.json
  )
  local -a tmp_items=(
    terraform-dxw-dalmatian-account-bootstrap
    terraform-dxw-dalmatian-infrastructure
    service-environment-files
  )

  legacy_setup="$CONFIG_DIR/setup.json"

  if [[ ! -f "$legacy_setup" ]]
  then
    return 0
  fi

  if [[ -f "$CONFIG_INSTALLATIONS_JSON_FILE" ]]
  then
    err "Found both a legacy Dalmatian configuration and $CONFIG_INSTALLATIONS_JSON_FILE"
    err "Move these into an installation directory under $CONFIG_INSTALLATIONS_DIR, or delete them, by hand:"
    for item in "${config_items[@]}"
    do
      if [[ -e "$CONFIG_DIR/$item" ]]
      then
        err "  $CONFIG_DIR/$item"
      fi
    done
    exit 1
  fi

  name="$(
    jq -r 'select((.project_name | type) == "string") | .project_name' \
      < "$legacy_setup" 2>/dev/null || true
  )"
  if ! installation_name_valid "$name"
  then
    name="default"
  fi

  mkdir -p "$CONFIG_INSTALLATIONS_DIR/$name"

  for item in "${tmp_items[@]}"
  do
    source="$APP_ROOT/tmp/$item"
    destination="$APP_ROOT/tmp/$name/$item"
    if [[ ! -e "$source" ]]
    then
      continue
    fi
    if [[ -e "$destination" ]]
    then
      die "Cannot move $source: $destination already exists"
    fi
    mkdir -p "$APP_ROOT/tmp/$name"
    mv "$source" "$destination"
  done

  for item in "${config_items[@]}"
  do
    source="$CONFIG_DIR/$item"
    destination="$CONFIG_INSTALLATIONS_DIR/$name/$item"
    if [[ ! -e "$source" ]]
    then
      continue
    fi
    if [[ -e "$destination" ]]
    then
      die "Cannot move $source: $destination already exists"
    fi
    mv "$source" "$destination"
  done

  set_installation_default "$name"

  log_info -l "Moved the existing Dalmatian configuration into installation '$name'" -q "${QUIET_MODE:-0}"
}
