#!/bin/bash
set -e
set -o pipefail

# Prompt the user with a binary question
#
# @usage yes_no "Continue with setup? (Y/n)" "Y"
# @param $1 Message to prompt the user with
# @param $2 The default value if the user does not specify
function yes_no {
  local MESSAGE
  local DEFAULT

  MESSAGE="${1-"Continue? (Y/n)"}"
  DEFAULT="${2-"Y"}"

  while true; do
    read -rep "${MESSAGE} [$DEFAULT]: " CHOICE
    CHOICE=${CHOICE:-$DEFAULT}
    echo
    case "${CHOICE:0:1}" in
      [yY] )
        return 0 # true
        ;;
      [nN] )
        return 1 # false
        ;;
      * )
        echo "Please answer Y or N"
        ;;
    esac
  done
}

# Set up a handy repeatable error output function that uses `stderr`
#
# @usage err "A problem happened!"
# @param $* Any information to pass into stderr
function err {
  echo "[!] Error: $*" >&2
}

# Set up a handy log output function
#
# @usage log_info -l 'Something happened :)'"
# @param -l <log>  Any information to output
# @param -q <0/1>  Quiet mode
function log_info {
  OPTIND=1
  QUIET_MODE=0
  while getopts "l:q:" opt; do
    case $opt in
      l)
        LOG="$OPTARG"
        ;;
      q)
        QUIET_MODE="$OPTARG"
        ;;
      *)
        echo "Invalid \`log_info\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [ "$QUIET_MODE" == "0" ]
  then
    echo "==> $LOG"
  fi
}

# Check to see if a binary is installed on the system
#
# @usage  is_installed "oathtool"
# @param  $1 binary name
# @export $IS_INSTALLED boolean Whether the binary was found
function is_installed {
  if ! which -s "$1" || ! type -p "$1" > /dev/null; then
    err "$1 was not detected in your \$PATH"
    return 1 # false
  fi

  return 0 # true
}

# Dalmatian specific function
# Ask for a value from the user, and add it to setup.json
# If the value already exists in setup.json, provide it as a default
function read_prompt_with_setup_default {
  OPTIND=1
  DEFAULT=""
  SILENT=0
  while getopts "p:d:s" opt; do
    case $opt in
      p)
        PROMPT="$OPTARG"
        ;;
      d)
        DEFAULT="$OPTARG"
        ;;
      s)
        SILENT=1
        ;;
      *)
        echo "Invalid usage"
        ;;
    esac
  done
  if [ "$DEFAULT" != "" ]
  then
    PROMPT_DEFAULT=$(jq -r --arg index "$DEFAULT" 'getpath($index / ".")' < "$CONFIG_SETUP_JSON_FILE")
    if [[
      -n "$PROMPT_DEFAULT" &&
      "$PROMPT_DEFAULT" != "null"
    ]]
    then
      PROMPT="$PROMPT [$PROMPT_DEFAULT]"
    fi
  fi
  read -rp "$PROMPT: " VALUE
  if [ "$VALUE" == "" ]
  then
    PROMPT_RESULT="$PROMPT_DEFAULT"
  else
    PROMPT_RESULT="$VALUE"
  fi
  SETUP_JSON=$(
    jq -r \
      --arg index "$DEFAULT" \
      --arg value "$PROMPT_RESULT" \
      'getpath($index / ".") |= $value' \
      < "$CONFIG_SETUP_JSON_FILE"
  )
  echo "$SETUP_JSON" > "$CONFIG_SETUP_JSON_FILE"
  if [ "$SILENT" == "0" ]
  then
    echo "$PROMPT_RESULT"
  fi
}

# Dalmatian specific function
# Appends AWS sso config to the provided
# configuration file
function append_sso_config_file {
  config_file="$1"
  profile_name="$2"
  sso_start_url="$3"
  sso_region="$4"
  sso_account_id="$5"
  sso_role_name="$6"
  region="$7"

  cat <<EOT >> "$config_file"
[profile $profile_name]
sso_start_url = $sso_start_url
sso_region = $sso_region
sso_account_id = $sso_account_id
sso_role_name = $sso_role_name
region = $region

EOT
}
