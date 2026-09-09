# TODO

Everything here is tracked as a GitHub issue. Add new work as an issue and link
it below rather than describing it here.

## Bugs

- [#514](https://github.com/dxw/dalmatian-tools/issues/514) —
  `ecs/v2/ec2-access` builds a tag filter that can never match: `jq -c` leaves
  the project name quoted
- [#515](https://github.com/dxw/dalmatian-tools/issues/515) —
  `service/v1/copy-environment-variables` copies only the first variable on
  bash 4+
- [#516](https://github.com/dxw/dalmatian-tools/issues/516) —
  `certificate/v1/delete` issues `delete-certificate` with an empty ARN
- [#517](https://github.com/dxw/dalmatian-tools/issues/517) —
  `s3/v2/empty-and-delete-bucket` does not require `-b` and builds destructive
  calls from an empty bucket name
- [#518](https://github.com/dxw/dalmatian-tools/issues/518) —
  `waf/v1/set-ip-rule` creates an IP set with no addresses and reports success
- [#519](https://github.com/dxw/dalmatian-tools/issues/519) —
  `waf/v1/cf-ip-block` rejects valid IPv6 prefixes `/100` to `/128`
- [#520](https://github.com/dxw/dalmatian-tools/issues/520) — `is_installed`
  reports every binary as missing on Linux, because `which -s` is a BSD flag
- [#521](https://github.com/dxw/dalmatian-tools/issues/521) — `aurora/v1` has
  drifted from `rds/v1`: `export-dump` broken for a new `-o` path, doubled KMS
  suffix, lost VPC scoping, stray `set -x`
- [#522](https://github.com/dxw/dalmatian-tools/issues/522) —
  `aws/v2/list-profiles` cannot fail: process substitution hides the CLI exit
  status
- [#523](https://github.com/dxw/dalmatian-tools/issues/523) —
  `utilities/v2/run-command` has a dead `-s` check, does not recognise plain
  `postgres`, and aborts on its own happy path
- [#524](https://github.com/dxw/dalmatian-tools/issues/524) —
  `config/v1/list-environments` returns array indices rather than environment
  names
- [#525](https://github.com/dxw/dalmatian-tools/issues/525) — `getopts`
  optstrings missing a colon silently disable `-i`, including in
  `pick_ecs_instance`
- [#526](https://github.com/dxw/dalmatian-tools/issues/526) — flags registered
  in `getopts` with no `case` branch look supported but print usage
- [#527](https://github.com/dxw/dalmatian-tools/issues/527) — several commands
  carry an empty lookup result into the next AWS call instead of failing
- [#531](https://github.com/dxw/dalmatian-tools/issues/531) — `dalmatian
  version` exits 128 in a clone without tags, taking every invocation with it
- [#532](https://github.com/dxw/dalmatian-tools/issues/532) —
  `generate-four-words` prints `sort: write failed: Broken pipe` on Linux
- [#504](https://github.com/dxw/dalmatian-tools/issues/504) — `bin/dalmatian`
  inherits `INFRASTRUCTURE_NAME` from the environment and assumes the wrong role
- [#505](https://github.com/dxw/dalmatian-tools/issues/505) — `test.sh` masks
  the exit status of the `./bin` shellcheck pass
- [#507](https://github.com/dxw/dalmatian-tools/issues/507) —
  `get-caller-identity` is parsed with `jq` and breaks when AWS CLI output is not
  JSON

## Enhancements

- [#528](https://github.com/dxw/dalmatian-tools/issues/528) — `usage()` sends
  only its first line to stderr, and `-h` exit codes disagree across commands
- [#529](https://github.com/dxw/dalmatian-tools/issues/529) — eleven v1 scripts
  set no `errexit`, and `cloudfront` v1/v2 have drifted
- [#503](https://github.com/dxw/dalmatian-tools/issues/503) — support more than
  one Dalmatian v2 installation on a machine
- [#506](https://github.com/dxw/dalmatian-tools/issues/506) — pickers cannot be
  cancelled; extract a shared picker function
- [#425](https://github.com/dxw/dalmatian-tools/issues/425) — `config
  services-to-tsv` should account for subdirectory installs
- [#370](https://github.com/dxw/dalmatian-tools/issues/370) — [v2] prompt before
  auto-updating
- [#102](https://github.com/dxw/dalmatian-tools/issues/102) — extend
  `container-access` to specify containers
- [#99](https://github.com/dxw/dalmatian-tools/issues/99) — add a command to dump
  from an RDS instance which does not follow the normal naming pattern
- [#48](https://github.com/dxw/dalmatian-tools/issues/48) — add `config`
  subcommands to create things
- [#20](https://github.com/dxw/dalmatian-tools/issues/20) — add a verbose mode
- [#19](https://github.com/dxw/dalmatian-tools/issues/19) — add a dry run mode
