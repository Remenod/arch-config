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

export NO_AT_BRIDGE=1
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export ZSH_COMPDUMP="$XDG_CACHE_HOME/zsh/zcompdump"

# Set PATH before anything below looks up commands in it.
# -U drops duplicates; (N-/) skips entries that are not directories here.
typeset -U path
path+=(
    $HOME/opt/cross/bin(N-/)
    /opt/android-sdk/platform-tools(N-/)
    $HOME/.local/bin(N-/)
    $HOME/.cargo/bin(N-/)
)

# Install zinit on first start; without it (no git, no network) the shell
# still starts, just without the plugins.
ZINIT_HOME="$XDG_DATA_HOME/zinit/zinit.git"
if [[ ! -r $ZINIT_HOME/zinit.zsh ]] && (( $+commands[git] )); then
    print -P "%F{blue}Installing zinit into $ZINIT_HOME%f"
    mkdir -p "${ZINIT_HOME:h}" &&
        git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

if [[ -r $ZINIT_HOME/zinit.zsh ]]; then
    source "$ZINIT_HOME/zinit.zsh"

    zinit ice lucid
    zinit light zsh-users/zsh-autosuggestions

    zinit ice wait lucid
    zinit light zsh-users/zsh-syntax-highlighting

    zinit ice wait lucid
    zinit light zsh-users/zsh-completions

    zinit ice wait lucid
    zinit light zsh-users/zsh-history-substring-search
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

fpath=(~/.zsh/completion/ $fpath)

# compinit ignores ZSH_COMPDUMP on its own; -d is what moves the dump.
autoload -Uz compinit
mkdir -p "${ZSH_COMPDUMP:h}"
compinit -d "$ZSH_COMPDUMP"

export EDITOR=nano

alias clr='clear'
alias copy='wl-copy'
alias ...=../..
alias ....=../../..
alias .....=../../../..
alias ......=../../../../..

# Fall back to the plain tools where eza or advcpmv is not installed.
if (( $+commands[eza] )); then
    alias ls='eza --icons=always'
    alias l='ls -lah'
    alias lt='l --tree --ignore-glob=.git'
    alias ltd='lt --only-dirs'
    alias ll='ls -lh'
    alias llt='ll --tree --ignore-glob=.git'
    alias lltd='llt --only-dirs'
else
    alias ls='ls --color=auto'
    alias l='ls -lah'
    alias ll='ls -lh'
fi

if (( $+commands[advcp] )); then
    alias cp='advcp -gi'
else
    alias cp='cp -i'
fi

if (( $+commands[advmv] )); then
    alias mv='advmv -gi'
else
    alias mv='mv -i'
fi

alias history='history 1'
alias h=history
alias hl='history | less'
alias hs='history | grep'

alias md='mkdir -p'
alias rd=rmdir

alias sudo='sudo '

# Start a program detached from this terminal: run firefox
run() {
    setsid "$@" >/dev/null 2>&1 </dev/null &!
}

# Run a command in a new terminal window: ae 'htop'
ae() {
    alacritty -e bash -c "$1" &!
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
eval "$(direnv hook zsh)"

# fzf: Ctrl-R fuzzy history, Ctrl-T file picker, Alt-C cd into a dir.
# Sourced last so fzf's Ctrl-R wins over the history-search bindings above.
if [[ -d /usr/share/fzf ]]; then
    source /usr/share/fzf/key-bindings.zsh
    source /usr/share/fzf/completion.zsh
fi

# zoxide: `z <part>` jumps to a frequently used dir, `zi` picks interactively.
# Does not shadow cd.
if (( $+commands[zoxide] )); then
    eval "$(zoxide init zsh)"
fi
