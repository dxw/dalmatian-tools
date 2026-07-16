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
