#!/bin/bash
set -e
set -o pipefail

# Check to see if the currently logged in user is a sudoer
function is_sudoer {
  # Check admin group membership (fastest, but not definitive)
  if groups "$USER" | grep -q "admin";
  then
    GROUP_CHECK_RESULT=$?
  else
    GROUP_CHECK_RESULT=1
  fi

  # Check sudo privileges using sudo -l (requires sudo, but avoids direct /etc/sudoers access)
  if sudo -l 2>/dev/null | grep -q "ALL";
  then
    SUDO_CHECK_RESULT=0
  else
    SUDO_CHECK_RESULT=1
  fi

  # Return 0 only if BOTH group check (if applicable) AND sudo check pass
  if [[ $GROUP_CHECK_RESULT -eq 0 && $SUDO_CHECK_RESULT -eq 0 ]];
  then
    echo "[i] $USER is a sudoer"
    return 0
  elif [[ $GROUP_CHECK_RESULT -eq 1 && $SUDO_CHECK_RESULT -eq 0 ]];
  then
    echo "[i] $USER is a sudoer, but is not in 'admin' group"
    return 0
  else
    echo "[!] $USER is not a sudoer" >&2
    return 1
  fi
}
