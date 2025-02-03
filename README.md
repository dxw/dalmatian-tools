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
