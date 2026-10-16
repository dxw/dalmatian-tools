#!/usr/bin/env bats

load ../test_helper

# marklogic_curl_config renders the `user = "name:password"` line that curl
# reads from a --config file. curl's parser treats both `"` and `\` as
# special inside the quotes, so both have to be escaped or a password with
# a backslash arrives at the server changed.

setup() {
  setup_sandbox
  load_all_functions
}

@test "marklogic_curl_config renders the user line" {
  run marklogic_curl_config -u example-admin -p 'plainpassword'
  assert_success
  assert_output 'user = "example-admin:plainpassword"'
}

@test "marklogic_curl_config escapes backslashes and double quotes" {
  run marklogic_curl_config -u example-admin -p 'pa\ss"w\nrd'
  assert_success
  assert_output 'user = "example-admin:pa\\ss\"w\\nrd"'
}

@test "marklogic_curl_config rejects a password containing a line break" {
  run --separate-stderr marklogic_curl_config -u example-admin -p "$(printf 'bad\npassword')"
  assert_failure
  assert_stderr_contains "must not contain line breaks"
}

@test "marklogic_curl_config rejects missing arguments" {
  run --separate-stderr marklogic_curl_config -u example-admin
  assert_failure
  assert_stderr_contains "Invalid \`marklogic_curl_config\` function usage"
}
