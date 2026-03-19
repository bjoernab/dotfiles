# Enable colors
autoload -Uz colors && colors

# Better history
HISTSIZE=5000
SAVEHIST=5000
HISTFILE=~/.zsh_history
setopt appendhistory
setopt sharehistory
setopt hist_ignore_dups

# Better completion
autoload -Uz compinit
compinit

# Enable menu selection for tab completion
zstyle ':completion:*' menu select

# Case insensitive tab completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# Prompt (simple clean one)
PROMPT='%F{blue}%n@%m%f %F{red}%~ %F{green}% $ %f'