HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000

setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY

setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_FIND_NO_DUPS

source ~/.local/share/zinit/zinit.git/zinit.zsh

zinit ice lucid
zinit light zsh-users/zsh-autosuggestions

zinit ice wait lucid
zinit light zsh-users/zsh-syntax-highlighting

zinit ice wait lucid
zinit light zsh-users/zsh-completions
zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

zinit ice wait lucid
zinit light zsh-users/zsh-history-substring-search
fpath=(~/.zsh/completion/ $fpath)

autoload -Uz compinit
compinit

export EDITOR=nano

alias ls='eza --icons always'
alias clr='clear'
alias copy='wl-copy'
alias cp='advcp -gi'
alias mv='advmv -gi'
alias ...=../..
alias ....=../../..
alias .....=../../../..
alias ......=../../../../..
alias history='history 1'
alias h=history
alias hl='history | less'
alias hs='history | grep'
alias l='ls -lah'
alias lt='ls -lah --tree --ignore-glob=.git'
alias la='ls -lAh'
alias lat='ls -lAh --tree --ignore-glob=.git'
alias ll='ls -lh'
alias llt='ls -lh --tree --ignore-glob=.git'
alias md='mkdir -p'
alias rd=rmdir
alias run='setsid "$@" >/dev/null 2>&1 < /dev/null &'
alias sudo='sudo '

ae () {
    alacritty -e bash -c "$1"
    disown
}
 
autoload -Uz history-search-end

zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end

bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word
bindkey '^[[5D' backward-word
bindkey '^[[5C' forward-word
bindkey '^[[3;5~' delete-word
bindkey '^H' backward-delete-word

bindkey '^[[A' history-beginning-search-backward-end
bindkey '^[[B' history-beginning-search-forward-end

#bindkey '^[[A' history-substring-search-up
#bindkey '^[[B' history-substring-search-down

bindkey '^[[1;2A' history-substring-search-up
bindkey '^[[1;2B' history-substring-search-down

bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char

PROMPT='%F{green}%n@%m%f:%F{blue}%~%f$ '

export NO_AT_BRIDGE=1
export XDG_CACHE_HOME="$HOME/.cache"
export ZSH_COMPDUMP="$XDG_CACHE_HOME/zsh/zcompdump"

export PATH="$PATH:/home/remenod/opt/cross/bin"
export PATH=$PATH:/opt/android-sdk/platform-tools
export PATH="$PATH:/home/remenod/.local/bin"
