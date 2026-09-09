#!/usr/bin/env bats

load ../test_helper

# Non-hidden regular files under bin/, excluding the scratch tmp/ tree.
# Symlinks are excluded: they are aliases for files already checked.
command_scripts() {
  find "$DALMATIAN_ROOT/bin" \
    -path "$DALMATIAN_ROOT/bin/tmp" -prune -o \
    -name '.*' -prune -o \
    -type f -print
}

@test "every command script is executable" {
  local script offenders=()

  while IFS='' read -r script
  do
    [ -x "$script" ] || offenders+=("${script#"$DALMATIAN_ROOT/"}")
  done < <(command_scripts)

  [ "${#offenders[@]}" -eq 0 ] || fail "not executable: ${offenders[*]}"
}

@test "every command script has a bash shebang" {
  local script offenders=()

  while IFS='' read -r script
  do
    case "$(head -n 1 "$script")" in
      '#!/usr/bin/env bash'|'#!/bin/bash') ;;
      *) offenders+=("${script#"$DALMATIAN_ROOT/"}") ;;
    esac
  done < <(command_scripts)

  [ "${#offenders[@]}" -eq 0 ] || fail "no bash shebang: ${offenders[*]}"
}

# Eleven v1 scripts (the aurora/rds sibling pair and the util/ and config/
# groups) predate the `set -e` convention and run with no errexit at all -
# confirmed by inspection, not just a missing `^set -e$` line. Three more
# (aws/v2/add-user, aws/v2/remove-user, aws/v2/list-users) do have errexit,
# just spelled `set -euo pipefail` on one line rather than `set -e` on its
# own. Both groups are named explicitly below, compared for exact equality
# against what the tree actually contains, so this test fails in either
# direction: a script silently losing its errexit, or a listed one gaining
# one and needing to drop off the list.
@test "every command script exits on failure" {
  local script relative
  local -a offenders=()
  local -a no_errexit=(
    bin/aurora/v1/count-sql-backups
    bin/aurora/v1/download-sql-backup
    bin/config/v1/list-environments
    bin/config/v1/list-infrastructures
    bin/config/v1/list-services
    bin/config/v1/list-services-by-buildspec
    bin/config/v1/services-to-tsv
    bin/util/v1/env
    bin/util/v1/exec
    bin/util/v1/generate-four-words
    bin/util/v1/list-security-group-rules
  )

  while IFS='' read -r script
  do
    relative="${script#"$DALMATIAN_ROOT/"}"
    grep -qE '^set -e$|^set -euo pipefail$' "$script" || offenders+=("$relative")
  done < <(command_scripts)

  [ "$(printf '%s\n' "${offenders[@]}" | sort)" = "$(printf '%s\n' "${no_errexit[@]}" | sort)" ] ||
    fail "$(printf 'scripts without set -e no longer match the declared list.\nfound:\n%s\ndeclared:\n%s' \
      "$(printf '%s\n' "${offenders[@]}" | sort)" "$(printf '%s\n' "${no_errexit[@]}" | sort)")"
}

@test "every bash function file defines a function named after the file" {
  local file name offenders=()

  for file in "$DALMATIAN_ROOT"/lib/bash-functions/*.sh
  do
    name="$(basename "$file" .sh)"
    grep -q "^function $name " "$file" || offenders+=("$name")
  done

  [ "${#offenders[@]}" -eq 0 ] || fail "name does not match its file: ${offenders[*]}"
}

@test "every subcommand directory holds at least one version directory" {
  local dir offenders=()

  while IFS='' read -r dir
  do
    # bin/tmp is a gitignored runtime scratch directory - bin/aurora/v1/import-dump,
    # bin/rds/v1/import-dump, bin/aws/v1/assume-infrastructure-role and the
    # bin/config/v1/* scripts all read or write under it (dalmatian.yml cache,
    # munged SQL). It doesn't exist in a fresh checkout, but if it's ever
    # created it is scratch space, not a subcommand, so it is skipped here.
    case "$(basename "$dir")" in
      tmp) continue ;;
    esac
    if [ ! -d "$dir/v1" ] && [ ! -d "$dir/v2" ]
    then
      offenders+=("${dir#"$DALMATIAN_ROOT/"}")
    fi
  done < <(find "$DALMATIAN_ROOT/bin" -mindepth 1 -maxdepth 1 -type d)

  [ "${#offenders[@]}" -eq 0 ] || fail "no v1 or v2 directory: ${offenders[*]}"
}

# Coverage ratchet for lib/bash-functions.
#
# declared_backlog is every lib/bash-functions/*.sh whose name is not
# mentioned (as a whole word) anywhere under test/lib/, hard-coded and sorted.
# It is checked for EXACT equality against what the tree actually contains, so
# this test fails in both directions: a new function landing with no
# test/lib coverage adds a name that isn't in the list yet, and finishing
# coverage for a backlogged function removes a name the list still has -
# either way the list must be edited, which is the point of a ratchet.
#
# Three of the fourteen are out of scope for this first cut by design, per
# the test-suite spec, rather than merely unwritten:
#   - aws_epoch                 makes a real network time query (sntp)
#   - install_session_manager   installs a binary onto the machine
#   - the GPG credential path: the AWS SSO / Identity Center config-writing
#     functions behind bin/dalmatian's gpg-encrypted credential cache
#     (append_sso_config_file, append_sso_config_file_assume_role,
#     load_aws_sso_setup, identity_center_instance,
#     resolve_identity_center_profile, export_aws_caller_identity_username,
#     read_prompt_with_setup_default)
# The remaining names (append_import_block, check_bash_version, esc_info,
# pick_ecs_instance, require_visible_plan) are simply not covered yet.
@test "lib/bash-functions coverage matches the declared backlog" {
  local file name
  local -a actual_backlog=()
  local -a declared_backlog=(
    append_import_block
    append_sso_config_file
    append_sso_config_file_assume_role
    aws_epoch
    check_bash_version
    esc_info
    export_aws_caller_identity_username
    identity_center_instance
    install_session_manager
    load_aws_sso_setup
    pick_ecs_instance
    read_prompt_with_setup_default
    require_visible_plan
    resolve_identity_center_profile
  )

  for file in "$DALMATIAN_ROOT"/lib/bash-functions/*.sh
  do
    name="$(basename "$file" .sh)"
    grep -rlqw "$name" "$DALMATIAN_ROOT/test/lib" 2>/dev/null || actual_backlog+=("$name")
  done

  [ "$(printf '%s\n' "${actual_backlog[@]}" | sort)" = "$(printf '%s\n' "${declared_backlog[@]}" | sort)" ] ||
    fail "$(printf 'lib/bash-functions coverage backlog drifted from the declared list.\nactual:\n%s\ndeclared:\n%s' \
      "$(printf '%s\n' "${actual_backlog[@]}" | sort)" "$(printf '%s\n' "${declared_backlog[@]}" | sort)")"
}
