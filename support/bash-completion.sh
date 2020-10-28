#!/bin/bash
dalmatian_completion() {
  if ! command -v dalmatian > /dev/null
  then
    return 0
  fi
  DALMATIAN_BIN_PATH=$(dirname "$(command -v dalmatian)")

  if [ "${#COMP_WORDS[@]}" == 2 ]
  then
    SUBCOMMANDS=()

    DIRS=()
    while IFS=  read -r -d $'\0'; do
      DIRS+=("$REPLY")
    done < <(find "$DALMATIAN_BIN_PATH" -maxdepth 1 -type d -print0)
    
    FILES=()
    while IFS=  read -r -d $'\0'; do
      FILES+=("$REPLY")
    done < <(find "$DALMATIAN_BIN_PATH/configure-commands" -maxdepth 1 -type f -print0)

    for d in "${DIRS[@]}"
    do
      SUBCOMMAND="$(basename "$d")"
      if [[
        "$SUBCOMMAND" != "bin" &&
        "$SUBCOMMAND" != "configure-commands" &&
        "$SUBCOMMAND" != "tmp"
      ]]
      then
        SUBCOMMANDS+=("$SUBCOMMAND")
      fi
    done
    for f in "${FILES[@]}"
    do
      SUBCOMMANDS+=("$(basename "$f")")
    done
    IFS=" " read -r -a SUBCOMMANDS <<< "$(sort <<<"${SUBCOMMANDS[*]}")"

    COMPREPLY=()
    while IFS='' read -r comp
    do
      COMPREPLY+=("$comp")
    done < <(compgen -W "$(printf "'%s' " "${SUBCOMMANDS[@]}")" -- "${COMP_WORDS[COMP_CWORD]}")
    return 0
  elif [ "${#COMP_WORDS[@]}" == 3 ]
  then
    if [[
      "$1" != "bin" &&
      "$1" != "configure-commands" &&
      "$1" != "tmp" &&
      -d "$DALMATIAN_BIN_PATH/${COMP_WORDS[1]}"
    ]]
    then
      FILES=()
      while IFS=  read -r -d $'\0'; do
        FILES+=("$REPLY")
      done < <(find "$DALMATIAN_BIN_PATH/${COMP_WORDS[1]}" -maxdepth 1 -type f -print0)
      COMMANDS=()

      for f in "${FILES[@]}"
      do
        COMMANDS+=("$(basename "$f")")
      done
      IFS=" " read -r -a COMMANDS <<< "$(sort <<<"${COMMANDS[*]}")"

      COMPREPLY=()
      while IFS='' read -r comp
      do
        COMPREPLY+=("$comp")
      done < <(compgen -W "$(printf "'%s' " "${COMMANDS[@]}")" -- "${COMP_WORDS[COMP_CWORD]}")
      return 0
    fi
  fi
}
complete -F dalmatian_completion dalmatian
