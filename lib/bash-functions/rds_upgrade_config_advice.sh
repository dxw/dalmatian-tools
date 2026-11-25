#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to print what an operator must (or need not)
# change in Dalmatian config after queuing an RDS engine upgrade. Guidance goes
# through `log_msg`; the consequences of getting it wrong go through `warning`.
# Both go to stderr whatever the quiet mode, as the guidance is part of the
# warning set and makes no sense without it.
#
# @param -s <status>  Config version status: ok, update or unknown
# @param -t <target>  The engine version being upgraded to
# @param -w <where>   The file and key holding the configured version
# @param -o <lines>   Optional. Newline separated `<env> <running version>` or
#                     `<env> not found` (or `not checked`) lines for environments
#                     sharing the entry
# @param -m           Optional. Suggest the major.minor form of the target
# @param -a           Optional. The upgrade was applied immediately, so there is
#                     no window for an unrelated deploy to pre-empt
# @param -c           Optional. The configured version was not checked at all,
#                     rather than checked and found unreadable
function rds_upgrade_config_advice {
  local OPTIND opt OPTARG STATUS TARGET WHERE OTHERS SUGGEST_MINOR APPLIED_NOW NOT_CHECKED OPENING line
  # Local, so the caller's quiet mode survives: log_msg assigns QUIET_MODE
  # globally
  local QUIET_MODE=0
  OPTIND=1
  SUGGEST_MINOR=0
  APPLIED_NOW=0
  NOT_CHECKED=0
  while getopts "s:t:w:o:mac" opt; do
    case $opt in
      s)
        STATUS="$OPTARG"
        ;;
      t)
        TARGET="$OPTARG"
        ;;
      w)
        WHERE="$OPTARG"
        ;;
      o)
        OTHERS="$OPTARG"
        ;;
      m)
        SUGGEST_MINOR=1
        ;;
      a)
        APPLIED_NOW=1
        ;;
      c)
        NOT_CHECKED=1
        ;;
      *)
        echo "Invalid \`rds_upgrade_config_advice\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$STATUS" || -z "$TARGET" || -z "$WHERE" ]] ||
    [[ ! "$STATUS" =~ ^(ok|update|unknown)$ ]]
  then
    echo "Invalid \`rds_upgrade_config_advice\` function usage" >&2
    exit 1
  fi

  case "$STATUS" in
    ok)
      log_msg -l "No config change is needed: the configured version matches $TARGET." -q "$QUIET_MODE" >&2
      ;;
    update)
      log_msg -l "Change $WHERE to $TARGET after the upgrade has happened and before the next deploy." -q "$QUIET_MODE" >&2
      warning "Changing it before then makes the next deploy apply the upgrade immediately."
      warning "Leaving it unchanged after the upgrade makes the next deploy fail: AWS will not downgrade."
      if [[ -n "$OTHERS" ]]
      then
        log_msg -l "This entry is shared with other environments:" -q "$QUIET_MODE" >&2
        while IFS= read -r line
        do
          log_msg -l "  $line" -q "$QUIET_MODE" >&2
        done <<< "$OTHERS"
        log_msg -l "Config can only change once all of them run $TARGET." -q "$QUIET_MODE" >&2
      fi
      if [[ "$SUGGEST_MINOR" == "1" ]]
      then
        log_msg -l "Setting engine_version to $(cut -d. -f1-2 <<< "$TARGET") lets environments upgrade independently." -q "$QUIET_MODE" >&2
      fi
      ;;
    unknown)
      if [[ "$NOT_CHECKED" == "1" ]]
      then
        OPENING="The configured version was not checked."
      else
        OPENING="Could not read the configured version."
      fi
      log_msg -l "$OPENING If $WHERE is a full version, change it to $TARGET after the upgrade has happened and before the next deploy." -q "$QUIET_MODE" >&2
      warning "If it is a full version, changing it before then makes the next deploy apply the upgrade immediately."
      warning "If it is a full version, leaving it unchanged after the upgrade makes the next deploy fail: AWS will not downgrade."
      ;;
  esac

  if [[ "$APPLIED_NOW" == "0" ]]
  then
    warning "A deploy that changes this database for any other reason before the window applies the upgrade then."
  fi
}
