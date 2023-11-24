#!/bin/bash
set -e
set -o pipefail

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
