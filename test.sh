#!/usr/bin/env bash

set -e
set -o pipefail

# Check bash version is >= 4
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "Tests require Bash 4.0 or newer." >&2
  exit 1
fi

usage() {
  echo "Usage: $(basename "$0") [lint|bats|<bats arguments>]" 1>&2
  echo "  (no arguments)  - run shellcheck, then the bats suite"
  echo "  lint            - run shellcheck only"
  echo "  bats            - run the bats suite only"
  echo "  <path>          - passed straight to bats, eg. test/lib/logging.bats"
  exit 1
}

run_lint() {
  # Hidden files (eg. bin/custom/v2/.gitkeep) are not scripts, so are not linted
  find ./bin -path ./bin/tmp -prune -o -name '.*' -prune -o -type f -exec shellcheck -x {} +
  find ./support -type f -exec shellcheck -x {} +
  find ./lib/bash-functions -type f -exec shellcheck -x {} +
  # -type f skips the stub symlinks, which all point at _dispatch
  shellcheck -x ./test/test_helper.bash
  find ./test/stubs -name '.*' -prune -o -type f -exec shellcheck -x {} +
  # .bats files parse fine, with each @test read as a function definition, so
  # the tests get the same checking as everything else. What shellcheck cannot
  # see is that bats' `run` assigns $status/$output/$lines/$stderr, which is why
  # the helper carries a file-level SC2154 directive and the test files touch
  # those variables only through the helper's assertion functions.
  #
  # Note the wording above: a comment beginning "# shellcheck" followed by prose
  # is read as a malformed *directive* and hard-errors (SC1072/SC1073), so don't
  # start a comment with that word.
  find ./test -name '*.bats' -exec shellcheck -x {} +
  # This script too. CI's shellcheck action scans the whole repository, so
  # anything omitted here fails there instead.
  shellcheck -x ./test.sh
}

run_bats() {
  bats --recursive test
}

case "${1-}" in
  "")
    run_lint
    run_bats
    ;;
  lint)
    run_lint
    ;;
  bats)
    run_bats
    ;;
  -h)
    usage
    ;;
  *)
    bats "$@"
    ;;
esac
