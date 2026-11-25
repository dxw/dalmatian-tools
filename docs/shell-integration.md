## Shell completion

**Bash (/bin/bash)**

Add the full path to the `support/bash-completion.sh` script to your `~/.bashrc` file

eg:

```
# ~/.bashrc

source /path/to/dalmatian-tools/support/bash-completion.sh
```

**Zsh (/bin/zsh)**

Add the full path to the `support/zsh-completion.sh` script to your `~/.zshrc` file

eg:

```
# ~/.zshrc

autoload -Uz +X compinit && compinit
autoload -Uz +X bashcompinit && bashcompinit
source /path/to/dalmatian-tools/support/zsh-completion.sh
```

### What is completed

Subcommands, commands and each command's flags, for whichever version
`dalmatian version` has selected. After a flag that takes a value, completion
offers values it can find locally, without calling AWS:

- infrastructures, environments, services and RDS names: under v2 from the
  selected installation's tfvars cache (`dalmatian terraform-dependencies
  get-tfvars` refreshes it); under v1 from the `dalmatian.yml` given by
  `DALMATIAN_CONFIG_PATH`, which also supplies Aurora and ElastiCache names
- installation names, for `dalmatian installation use` and `remove`
- filenames, for flags that take a file or path

v1 values need a compiled `dalmatian.yml`. Pointing `DALMATIAN_CONFIG_PATH` at
the one in a local `dalmatian-config` checkout keeps them current with
`git pull`; without it, completion falls back to the copy
`dalmatian config` commands cache under `bin/tmp/`.
