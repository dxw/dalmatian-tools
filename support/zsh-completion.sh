#!/bin/bash
_dalmatian_completions_filter() {
  local words="$1"
  local cur=${COMP_WORDS[COMP_CWORD]}
  local result=()

  if [[ "${cur:0:1}" == "-" ]]; then
    echo "$words"

  else
    for word in $words; do
      [[ "${word:0:1}" != "-" ]] && result+=("$word")
    done

    echo "${result[*]}"

  fi
}

_dalmatian_completions() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  local compwords=("${COMP_WORDS[@]:1:$COMP_CWORD-1}")
  local compline="${compwords[*]}"
  local dir
  local bindir
  dir=$(command -v "dalmatian")
  bindir=$(dirname "$dir")

  local version="v1"
  local config_dir="$HOME/.config/dalmatian"
  local config_version_json_file="$config_dir/version.json"
  if [ -f "$config_version_json_file" ]
  then
    version=$(jq -r '.version' < "$config_version_json_file")
  fi

  case "$compline" in
    'aurora'*)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/aurora/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    'certificate'*)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/certificate/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    'cloudfront'*)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/cloudfront/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    'service'*)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/service/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    'config')
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/config/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    'util'*)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/util/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    'rds'*)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/rds/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    'ecs'*)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/ecs/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    'waf'*)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/waf/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    'aws'*)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/aws/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    'ci'*)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/ci/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    'elasticache'*)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "$(find "$bindir/elasticache/$version" -type f -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

    *)
      while read -r; do COMPREPLY+=( "$REPLY" ); done < <( compgen -W "$(_dalmatian_completions_filter "-h -l $(find "$bindir" -type d -not -path "$bindir"/configure-commands -mindepth 1 -maxdepth 1 -exec basename {} \;)")" -- "$cur" )
      ;;

  esac
} &&
complete -F _dalmatian_completions dalmatian

# ex: filetype=sh
