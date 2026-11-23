#!/usr/bin/env bash
set -e
set -o pipefail

# Dalmatian v2 specific function to turn an RDS weekly maintenance window
# (`ddd:hh:mm-ddd:hh:mm`, UTC) into the concrete window relevant at a given
# time. Prints `<start> <end> <state>` on one line, with start and end as
# `%Y-%m-%dT%H:%M:%SZ` and state either `in-progress` (now falls inside the
# window) or `upcoming` (the next occurrence).
#
# @param -w <window>  RDS maintenance window, e.g. sun:23:30-mon:00:30
# @param -n <epoch>   The current time as a Unix epoch
function rds_next_maintenance_window {
  local OPTIND opt OPTARG WINDOW NOW
  OPTIND=1
  while getopts "w:n:" opt; do
    case $opt in
      w)
        WINDOW="$OPTARG"
        ;;
      n)
        NOW="$OPTARG"
        ;;
      *)
        echo "Invalid \`rds_next_maintenance_window\` function usage" >&2
        exit 1
        ;;
    esac
  done
  if [[ -z "$WINDOW" || -z "$NOW" ]]
  then
    echo "Invalid \`rds_next_maintenance_window\` function usage" >&2
    exit 1
  fi

  local WEEK=604800
  local LOWER_WINDOW="${WINDOW,,}"
  local DAY_RE="mon|tue|wed|thu|fri|sat|sun"
  if [[ ! "$LOWER_WINDOW" =~ ^($DAY_RE):[0-2][0-9]:[0-5][0-9]-($DAY_RE):[0-2][0-9]:[0-5][0-9]$ ]]
  then
    err "Unrecognised maintenance window: $WINDOW"
    exit 1
  fi

  local DAYS="mon tue wed thu fri sat sun"
  local START_PART="${LOWER_WINDOW%-*}"
  local END_PART="${LOWER_WINDOW#*-}"
  local DAY_OFFSETS=()
  local PART DAY HOUR MIN INDEX D
  for PART in "$START_PART" "$END_PART"
  do
    IFS=: read -r DAY HOUR MIN <<< "$PART"
    INDEX=0
    for D in $DAYS
    do
      if [[ "$D" == "$DAY" ]]
      then
        break
      fi
      INDEX=$((INDEX + 1))
    done
    DAY_OFFSETS+=("$((INDEX * 86400 + 10#$HOUR * 3600 + 10#$MIN * 60))")
  done

  local NOW_DOW WEEK_START START END STATE
  NOW_DOW="$(gdate -u -d "@$NOW" +%u)"
  WEEK_START=$((NOW - NOW % 86400 - (NOW_DOW - 1) * 86400))
  START=$((WEEK_START + DAY_OFFSETS[0]))
  END=$((WEEK_START + DAY_OFFSETS[1]))
  if (( END <= START ))
  then
    END=$((END + WEEK))
  fi

  if (( START - WEEK <= NOW && NOW < END - WEEK ))
  then
    START=$((START - WEEK))
    END=$((END - WEEK))
    STATE="in-progress"
  elif (( START <= NOW && NOW < END ))
  then
    STATE="in-progress"
  elif (( NOW >= END ))
  then
    START=$((START + WEEK))
    END=$((END + WEEK))
    STATE="upcoming"
  else
    STATE="upcoming"
  fi

  echo "$(gdate -u -d "@$START" +%Y-%m-%dT%H:%M:%SZ) $(gdate -u -d "@$END" +%Y-%m-%dT%H:%M:%SZ) $STATE"
}
