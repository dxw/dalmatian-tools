#!/usr/bin/env bash
set -e
set -o pipefail

# Move Terraform working copies left in the flat pre-installations tmp/ layout
# into the default installation's tmp/<name>/.
#
# migrate_legacy_installation moves these itself, but only under the APP_ROOT
# it runs from. The config dir is shared between checkouts, so a migration run
# from a second checkout or a worktree moves the configuration -- and removes
# the legacy setup.json that triggers it -- while every other checkout keeps
# its working copies at tmp/<item>, where nothing reads them any more.
#
# The legacy layout predates installations, so its working copies belong to
# the installation the migration created, which it recorded as the default.
# They are adopted there rather than into whatever DALMATIAN_INSTALLATION
# selects. An occupied destination is left alone with a warning: the copy
# already in place is the one in use.
#
# @usage adopt_legacy_working_copies
function adopt_legacy_working_copies {
  local name item source destination
  local -a items=(
    terraform-dxw-dalmatian-account-bootstrap
    terraform-dxw-dalmatian-infrastructure
    service-environment-files
  )

  # resolve_installation validates the default only when it is the selected
  # installation; with DALMATIAN_INSTALLATION set it has not been checked, and
  # it becomes part of a path below
  name="$(installation_default)"
  if [[ -z "$name" ]] || ! installation_name_valid "$name" || [[ ! -d "$CONFIG_INSTALLATIONS_DIR/$name" ]]
  then
    return 0
  fi

  for item in "${items[@]}"
  do
    source="$APP_ROOT/tmp/$item"
    destination="$APP_ROOT/tmp/$name/$item"
    if [[ ! -e "$source" ]]
    then
      continue
    fi
    # tmp/<item> moved into tmp/<item>/<item> would be moved inside itself
    if [[ "$name" == "$item" ]]
    then
      warning "$source cannot be moved into installation '$name' without moving it inside itself. Move or delete it by hand"
      continue
    fi
    if [[ -e "$destination" ]]
    then
      warning "$source is no longer used now that working copies live under $APP_ROOT/tmp/$name/, and $destination already exists. Delete it by hand"
      continue
    fi
    mkdir -p "$APP_ROOT/tmp/$name"
    mv "$source" "$destination"
    log_info -l "Moved $source into installation '$name'" -q "${QUIET_MODE:-0}"
  done

  return 0
}
