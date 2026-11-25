# Dalmatian Tools

![GitHub Release](https://img.shields.io/github/v/release/dxw/dalmatian-tools)

A collection of administration tools you can use to interact with dxw's Dalmatian hosting platform.

## Table of Contents
1. [Installation](./docs/installation.md)
1. [Usage](./docs/usage.md)
1. [Shell integration](./docs/shell-integration.md)
1. [FAQ](./docs/faq.md)

### Environment Variables

- `DALMATIAN_CONFIG_PATH`

  Set a path to `dalmatian.yml` to override the use of the checkout used by the
  tools by default. Useful if bringing up a service or infrastructure whose
  config hasn't been merged in yet. Shell completion reads v1 infrastructure,
  environment, service, RDS, Aurora and ElastiCache names from it too.

- `DALMATIAN_INSTALLATION`
  Select which Dalmatian installation to run against, overriding the default
  recorded by `dalmatian installation use`. See "Installations" in
  [README-in-development.md](README-in-development.md).

- `DALMATIAN_FZF_ENABLED`
  Set to `0` to disable `fzf` support for interactive selections. Defaults to `1`.

- `DALMATIAN_SKIP_UPDATE_PROMPT`
  Set to `1` to skip the update prompt when there are local changes or the current
  version tag is newer than the remote. Useful when running a development
  version.

- `DALMATIAN_SKIP_UPDATE_CHECK`
  Set to `1` to skip the automatic update check that runs before every command.
  `dalmatian update` can still be run explicitly. Note that if the check can't
  reach GitHub (network failure, API rate limit, etc.), it is skipped with a
  warning anyway.
