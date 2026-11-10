# Shared by the v2 RDS commands that run a script in the utilities task. Load
# it after test_helper. The scripts are matched literally, $DB_PASSWORD and
# all, because the container expands them, not this shell
# shellcheck disable=SC2016

# Test passwords are made at run time rather than written out, so that no
# literal password assignment in this file trips secret scanners
fake_password() {
  printf 'fake%s%s' "$1" "$BATS_TEST_NUMBER"
}

# The command handed to `utilities run-command -c`, without the -R that
# follows it when the caller asks for the task's outcome
task_command() {
  sed -n 's/^dalmatian utilities run-command -i [^ ]* -e [^ ]* -r [^ ]* -c //p' "$DALMATIAN_STUB_LOG" | sed 's/ -R [^ ]*$//'
}

# The script it runs with bash -c in the container, decoded
task_script() {
  task_command | sed -n 's/^bash -c "$(echo \([A-Za-z0-9+\/=]*\) | base64 -d)".*/\1/p' | base64 -d
}

# Run the decoded script as the container would, with aws answering the
# parameter lookup with $1 and mysql/psql recording their arguments and stdin.
# When $2 is given (it may be empty), a mysql/psql call made as a lookup (psql
# -tA, mysql -N) prints it instead, and leaves the recorded arguments and stdin
# to the later calls that do the work. TASK_LOOKUP_EXIT and TASK_CLIENT_EXIT,
# when exported, make the lookup and the main call exit with that status after
# doing their usual work, as a failing psql (3) or mysql (1) would
run_task_script() {
  local password=$1

  mkdir -p "$SANDBOX/container"
  printf '#!/usr/bin/env bash\nprintf "%%s" %q\n' "$password" > "$SANDBOX/container/aws"
  rm -f "$SANDBOX/answer"
  if [ $# -ge 2 ]
  then
    printf '%s' "$2" > "$SANDBOX/answer"
  fi
  for client in mysql psql
  do
    cat > "$SANDBOX/container/$client" <<FAKE
#!/usr/bin/env bash
for arg in "\$@"
do
  if [ -e "$SANDBOX/answer" ] && { [ "\$arg" == "-tA" ] || [ "\$arg" == "-N" ]; }
  then
    cat > /dev/null
    cat "$SANDBOX/answer"
    exit "\${TASK_LOOKUP_EXIT:-0}"
  fi
done
printf "%s\\n" "\$@" > "$SANDBOX/$client.args"
cat > "$SANDBOX/$client.stdin"
exit "\${TASK_CLIENT_EXIT:-0}"
FAKE
  done
  chmod +x "$SANDBOX/container/"*
  task_script > "$SANDBOX/task-script"
  DB_USER=root DB_PASSWORD="$(fake_password root)" PATH="$SANDBOX/container:$PATH" bash "$SANDBOX/task-script" < /dev/null
}
