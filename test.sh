#!/usr/bin/env bash

# Check bash version is >= 4
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "Tests require Bash 4.0 or newer." >&2
  exit 1
fi

find ./bin -path ./bin/tmp -prune -o -type f -exec shellcheck -x {} +
find ./support -type f -exec shellcheck -x {} +
