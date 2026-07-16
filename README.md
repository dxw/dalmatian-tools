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
  config hasn't been merged in yet.

- DALMATIAN_FZF_ENABLED
  Set to 0 to disable fzf support for interactive selections. Defaults to 1.

- DALMATIAN_SKIP_UPDATE_PROMPT
  Set to 1 to skip the update prompt when there are local changes or the current
  version tag is newer than the remote. Useful when running a development
  version.
