#!/usr/bin/env bats

load ../test_helper

HELPER="$DALMATIAN_ROOT/support/dalmatian-complete"

setup() {
  setup_sandbox
  unset DALMATIAN_CONFIG_PATH
  use_version v2
}

use_version() {
  printf '{"version": "%s"}\n' "$1" > "$CONFIG_DIR/version.json"
}

# Complete the last word of the given command line, as the shell would
complete_line() {
  run "$HELPER" "$(( $# - 1 ))" "$@"
}

# The candidates, space-separated, for comparing a whole list at once
assert_candidates() {
  local actual
  actual="$(printf '%s\n' "$output" | tr '\n' ' ')"
  actual="${actual% }"
  if [ "$actual" != "$1" ]
  then
    fail "$(printf 'expected candidates:\n%s\nactual:\n%s' "$1" "$actual")"
  fi
}

# Two accounts whose names share a prefix and contain dashes, and
# infrastructure names with dashes too, so a split on the wrong dash shows up
use_tfvars_cache() {
  local dir="$CONFIG_INSTALLATION_DIR/.cache/tfvars"
  mkdir -p "$dir"
  : > "$dir/000-terraform.tfvars"
  : > "$dir/100-123456789012-eu-west-2-stats-user.tfvars"
  : > "$dir/100-210987654321-eu-west-2-stats.tfvars"

  cat > "$dir/200-123456789012-eu-west-2-stats-user-net-staging.tfvars" <<'EOF'
infrastructure_ecs_cluster_services = {
  web = {
    container_port = 80
    nested = {
      value = 1
    }
  }
  "worker" = {
    container_port = 0
  }
}

infrastructure_rds = {
  maindb = {
    engine = "postgres"
  }
}
EOF
  cat > "$dir/200-123456789012-eu-west-2-stats-user-net-prod.tfvars" <<'EOF'
infrastructure_ecs_cluster_services = {
  web = {
    container_port = 80
  }
}

infrastructure_rds = {}

other_map = {
  not_an_rds = {
    value = 1
  }
}
EOF
  cat > "$dir/200-210987654321-eu-west-2-stats-net-sun-prod.tfvars" <<'EOF'
infrastructure_ecs_cluster_services = {}

infrastructure_rds = {
  sundb = {
    engine = "mysql"
  }
}
EOF
}

use_v1_config() {
  use_version v1
  export DALMATIAN_CONFIG_PATH="$SANDBOX/dalmatian.yml"
  install_fixture completion-dalmatian.yml "$DALMATIAN_CONFIG_PATH"
}

@test "subcommands come from the active version's command tree" {
  complete_line dalmatian ""
  assert_success
  assert_output_contains "installation"
  assert_output_contains "rds"
  case "$output" in
    *login*) fail "v1-only login offered under v2" ;;
  esac

  use_version v1
  complete_line dalmatian ""
  assert_output_contains "login"
  case "$output" in
    *installation*) fail "v2-only installation offered under v1" ;;
  esac
}

@test "the top level offers its own flags" {
  complete_line dalmatian -
  assert_success
  assert_candidates "-h -l"
}

@test "commands are those of the subcommand under the active version" {
  complete_line dalmatian rds ""
  assert_success
  assert_candidates "run-command shell"
}

@test "commands are filtered by the word being completed" {
  complete_line dalmatian rds sh
  assert_candidates "shell"
}

@test "flags come from the command's getopts spec" {
  complete_line dalmatian rds shell ""
  assert_success
  assert_candidates "-D -M -e -h -i -r"
}

@test "flags already on the line are not offered again" {
  complete_line dalmatian rds shell -i x -r y -
  assert_candidates "-D -M -e -h"
}

@test "flags are not offered for a word that isn't one" {
  complete_line dalmatian rds shell -i x foo
  assert_success
  assert_output ""
}

@test "flags of a top-level command start after its name" {
  complete_line dalmatian version -
  assert_candidates "-h -s -v"
}

@test "commands outside the command tree are not read" {
  complete_line dalmatian rds ../v1/shell -
  assert_success
  assert_output ""
}

@test "installation completes its actions, then installation names" {
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/other"

  complete_line dalmatian installation ""
  assert_candidates "list remove use"

  complete_line dalmatian installation use ""
  assert_candidates "example-project other"

  complete_line dalmatian installation remove -
  assert_candidates "-y"
}

@test "v2 infrastructures are split from their account by the account tfvars" {
  use_tfvars_cache
  complete_line dalmatian rds shell -i ""
  assert_success
  assert_candidates "net net-sun"
}

@test "v2 infrastructures follow DALMATIAN_INSTALLATION" {
  use_tfvars_cache
  mkdir -p "$CONFIG_INSTALLATIONS_DIR/empty"
  DALMATIAN_INSTALLATION=empty complete_line dalmatian rds shell -i ""
  assert_success
  assert_output ""
}

@test "an invalid installation name reads nothing" {
  use_tfvars_cache
  DALMATIAN_INSTALLATION="../installations/example-project" complete_line dalmatian rds shell -i ""
  assert_success
  assert_output ""
}

@test "v2 environments are narrowed to the infrastructure on the line" {
  use_tfvars_cache
  complete_line dalmatian rds shell -i net -e ""
  assert_candidates "prod staging"

  complete_line dalmatian rds shell -i net-sun -e ""
  assert_candidates "prod"

  complete_line dalmatian rds shell -e ""
  assert_candidates "prod staging"
}

@test "v2 services are the keys of the ECS services map" {
  use_tfvars_cache
  complete_line dalmatian service logs -i net -e staging -s ""
  assert_candidates "web worker"

  complete_line dalmatian service logs -i net -e prod -s ""
  assert_candidates "web"

  complete_line dalmatian service logs -i net-sun -s ""
  assert_output ""
}

@test "v2 RDS names are the keys of the RDS map, and an empty map yields none" {
  use_tfvars_cache
  complete_line dalmatian rds shell -i net -e staging -r ""
  assert_candidates "maindb"

  complete_line dalmatian rds shell -i net -e prod -r ""
  assert_output ""

  complete_line dalmatian rds shell -i net-sun -r ""
  assert_candidates "sundb"
}

@test "v2 values are empty without a tfvars cache" {
  complete_line dalmatian rds shell -i ""
  assert_success
  assert_output ""
}

@test "v1 infrastructures and environments come from DALMATIAN_CONFIG_PATH" {
  use_v1_config
  complete_line dalmatian rds shell -i ""
  assert_candidates "example-infra other-infra"

  complete_line dalmatian rds shell -i other-infra -e ""
  assert_candidates "dev"

  complete_line dalmatian rds shell -e ""
  assert_candidates "dev prod staging"
}

@test "v1 services, RDS and Aurora names are narrowed to the infrastructure" {
  use_v1_config
  complete_line dalmatian service container-access -i example-infra -s ""
  assert_candidates "web worker"

  complete_line dalmatian rds shell -i example-infra -r ""
  assert_candidates "maindb"

  complete_line dalmatian rds shell -r ""
  assert_candidates "maindb otherdb"

  complete_line dalmatian aurora shell -i example-infra -r ""
  assert_candidates "clusterdb"
}

@test "the aurora commands that name their cluster <rds_name> get Aurora names" {
  use_v1_config
  complete_line dalmatian aurora start-sql-backup-to-s3 -i example-infra -r ""
  assert_candidates "clusterdb"
}

@test "<cluster_name> is an ElastiCache cluster only under elasticache" {
  use_v1_config
  complete_line dalmatian elasticache reboot -i example-infra -c ""
  assert_candidates "cache"

  complete_line dalmatian service container-access -i example-infra -c ""
  assert_success
  assert_output ""
}

@test "a v1 infrastructure name can't alter the config query" {
  use_v1_config
  complete_line dalmatian rds shell -i '"] | .infrastructures | keys | .[0' -r ""
  assert_success
  assert_output ""
}

@test "v1 values are empty without a config file" {
  use_version v1
  export DALMATIAN_CONFIG_PATH="$SANDBOX/missing.yml"
  complete_line dalmatian rds shell -i ""
  assert_success
  assert_output ""
}

@test "a file or path placeholder asks the shell for filenames" {
  complete_line dalmatian service logs -o ""
  assert_failure 2
  assert_output ""
}

@test "a placeholder with no known values completes nothing" {
  complete_line dalmatian service logs -p ""
  assert_success
  assert_output ""
}

@test "every command with a getopts spec has its flags found" {
  local script subcommand version missing=()

  for script in "$DALMATIAN_ROOT"/bin/*/v[12]/*
  do
    [[ -f "$script" ]] && grep -q 'getopts' "$script" || continue
    version="$(basename "$(dirname "$script")")"
    subcommand="$(basename "$(dirname "$(dirname "$script")")")"
    [ "$subcommand" != "configure-commands" ] || continue
    use_version "$version"
    complete_line dalmatian "$subcommand" "$(basename "$script")" -
    if [[ "$output" != *-h* ]]
    then
      missing+=( "${script#"$DALMATIAN_ROOT"/}" )
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]
  then
    fail "$(printf 'no flags found for:\n%s' "$(printf '  %s\n' "${missing[@]}")")"
  fi
}

@test "the bash function fills COMPREPLY from the helper" {
  mkdir -p "$SANDBOX/files"
  : > "$SANDBOX/files/output.log"

  run bash -c '
    PATH="$1/bin:$PATH"
    source "$1/support/bash-completion.sh"
    try() {
      COMP_WORDS=( "$@" )
      COMP_CWORD=$(( $# - 1 ))
      _dalmatian_completion
      echo "${COMPREPLY[*]}"
    }
    try dalmatian rds sh
    try dalmatian service logs -o "$2/files/out"
  ' _ "$DALMATIAN_ROOT" "$SANDBOX"
  assert_success
  assert_line 0 "shell"
  assert_line 1 "$SANDBOX/files/output.log"
}
