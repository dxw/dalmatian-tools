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
# A legacy layout is recognised by setup.json at the root, or by the
# .migrating-installation marker left by an interrupted run of this function,
# with no installations.json (unless the marker is present, in which case a
# prior run already wrote it and this run is a resume).
#
# The marker is written with the chosen installation name before anything is
# moved, and removed only after installations.json has been written, so a run
# interrupted at any point -- including between the last `mv` and
# set_installation_default -- is recognised as a resume next time and picks up
# the same name rather than re-deriving (and possibly changing) it.
#
# @usage migrate_legacy_installation
function migrate_legacy_installation {
  local legacy_setup marker marker_tmp name item source destination resuming
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
  local -a conflicts=()

  legacy_setup="$CONFIG_DIR/setup.json"
  marker="$CONFIG_DIR/.migrating-installation"

  if [[ ! -f "$legacy_setup" && ! -f "$marker" ]]
  then
    return 0
  fi

  resuming=0
  if [[ -f "$marker" ]]
  then
    resuming=1
    name="$(cat "$marker")"
    if ! installation_name_valid "$name"
    then
      die "'$name' is not a valid installation name in $marker: use lower-case letters, digits, '-' and '_', starting with a letter or digit"
    fi
  fi

  if [[ "$resuming" -eq 0 && -f "$CONFIG_INSTALLATIONS_JSON_FILE" ]]
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
    for item in "${tmp_items[@]}"
    do
      if [[ -e "$APP_ROOT/tmp/$item" ]]
      then
        err "  $APP_ROOT/tmp/$item (belongs under $APP_ROOT/tmp/<name>/)"
      fi
    done
    exit 1
  fi

  if [[ "$resuming" -eq 0 ]]
  then
    name="$(
      jq -r 'select((.project_name | type) == "string") | .project_name' \
        < "$legacy_setup" 2>/dev/null || true
    )"
    if ! installation_name_valid "$name"
    then
      name="default"
    fi
  fi

  # A name equal to a tmp_items entry would move tmp/<item> into
  # tmp/<name>/<item>, i.e. inside itself; whether that name came from
  # setup.json just now or from a resumed run's marker, fall back instead
  for item in "${tmp_items[@]}"
  do
    if [[ "$name" == "$item" ]]
    then
      warning "'$name' is also the name of a Terraform working copy under tmp/; using 'default' instead to avoid moving it into itself"
      name="default"
      break
    fi
  done

  for item in "${tmp_items[@]}"
  do
    source="$APP_ROOT/tmp/$item"
    destination="$APP_ROOT/tmp/$name/$item"
    if [[ -e "$source" && -e "$destination" ]]
    then
      conflicts+=("$destination")
    fi
  done

  for item in "${config_items[@]}"
  do
    source="$CONFIG_DIR/$item"
    destination="$CONFIG_INSTALLATIONS_DIR/$name/$item"
    if [[ -e "$source" && -e "$destination" ]]
    then
      conflicts+=("$destination")
    fi
  done

  if [[ "${#conflicts[@]}" -gt 0 ]]
  then
    err "Cannot move the legacy Dalmatian configuration:"
    for destination in "${conflicts[@]}"
    do
      err "  $destination already exists"
    done
    exit 1
  fi

  # Only now is the migration committed to: a preflight failure above leaves
  # no marker, so the next run re-derives the name and checks again. Written
  # via a same-directory temp file and rename so an interruption can never
  # leave an empty marker for the next run to trip over
  marker_tmp="$(mktemp "$CONFIG_DIR/.migrating-installation.XXXXXX")"
  printf '%s\n' "$name" > "$marker_tmp"
  mv "$marker_tmp" "$marker"

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
  rm -f "$marker"

  log_info -l "Moved the existing Dalmatian configuration into installation '$name'" -q "${QUIET_MODE:-0}"
}
