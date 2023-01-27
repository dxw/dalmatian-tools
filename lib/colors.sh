#!/bin/bash
export C_RED="\033[1;31m"
export C_YELLOW="\033[1;33m"
export C_GREEN="\033[1;32m"
export C_RESET="\033[m"

fatal() {
  echo -e "${C_RED}Error: $1${C_RESET}"
}

warn() {
  echo -e "${C_YELLOW}Warning:${C_RESET}" "$1"
}

success() {
  echo -e "${C_GREEN}$1${C_RESET}"
}