#!/usr/bin/env bash
# Candidates come from support/dalmatian-complete in whichever checkout the
# dalmatian on PATH belongs to; see that script for what is completed.
_dalmatian_completion() {
  local dalmatian helper candidates candidate helper_status
  COMPREPLY=()

  dalmatian="$(command -v dalmatian)" || return 0
  helper="$(dirname "$dalmatian")/../support/dalmatian-complete"
  [ -x "$helper" ] || return 0

  candidates="$("$helper" "$COMP_CWORD" "${COMP_WORDS[@]}")"
  helper_status=$?

  if [ "$helper_status" -eq 2 ]
  then
    compopt -o filenames 2> /dev/null
    candidates="$(compgen -f -- "${COMP_WORDS[COMP_CWORD]}")"
  fi

  while IFS='' read -r candidate
  do
    if [ -n "$candidate" ]
    then
      COMPREPLY+=("$candidate")
    fi
  done <<< "$candidates"
  return 0
}
complete -F _dalmatian_completion dalmatian
