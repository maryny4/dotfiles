[[ $- != *i* ]] && return

PS1='[\u@\h \W]\$ '
HISTSIZE=15000
HISTFILESIZE=15000
HISTCONTROL=ignoreboth
shopt -s histappend
stty -ixon  # free Ctrl+S/Ctrl+Q from terminal flow control

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
export EDITOR=nvim
export VISUAL=nvim

# xdg base dirs
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"

# keep $HOME clean
# bash/python/node/sqlite silently drop history if the dir is missing
mkdir -p "$XDG_STATE_HOME"/{bash,python,node,sqlite}
# shell and REPL histories
export HISTFILE="$XDG_STATE_HOME/bash/history"
export PYTHON_HISTORY="$XDG_STATE_HOME/python/history"
export NODE_REPL_HISTORY="$XDG_STATE_HOME/node/repl_history"
export SQLITE_HISTORY="$XDG_STATE_HOME/sqlite/history"
# tool configs
export RIPGREP_CONFIG_PATH="$XDG_CONFIG_HOME/ripgrep/config"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"
export CLAUDE_CONFIG_DIR="$XDG_CONFIG_HOME/claude"
# data and caches
export CARGO_HOME="$XDG_DATA_HOME/cargo"
export GNUPGHOME="$XDG_DATA_HOME/gnupg"
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME/npm"
export CUDA_CACHE_PATH="$XDG_CACHE_HOME/nv"

# aliases
if command -v eza >/dev/null; then
  alias ls='eza --icons=auto --group-directories-first'
  alias ll='eza -l --icons=auto --group-directories-first --git'
  alias la='eza -la --icons=auto --group-directories-first --git'
  alias lt='eza --tree --icons=auto --level=2'
else
  alias ls='ls --color=auto'
fi
alias vim='nvim'
# grep -> rg. Short flags are split and translated one by one: several mean
# something else in rg (-L follow, -h help, -s case-sensitive, -z search-zip).
if command -v rg >/dev/null; then
  grep() {
    local args=() a c rest opt=1 wantval=0
    for a in "$@"; do
      # After `--`, and after a value-taking flag, the argument is data.
      if [ $opt -eq 0 ] || [ $wantval -eq 1 ]; then
        wantval=0; args+=("$a"); continue
      fi
      case "$a" in
        --) opt=0; args+=("$a") ;;
        --extended-regexp|--recursive) ;;
        --regexp|--file) wantval=1; args+=("$a") ;;
        --*) args+=("$a") ;;
        -[!-]*)
          rest="${a#-}"
          while [ -n "$rest" ]; do
            c="${rest:0:1}"; rest="${rest:1}"
            case "$c" in
              E|r|R|I|U) ;;    # rg defaults, or no equivalent
              L) args+=(--files-without-match) ;;
              h) args+=(--no-filename) ;;
              s) args+=(--no-messages) ;;
              z) args+=(--null-data) ;;
              e|f|A|B|C|m|g|t|T)
                args+=("-$c")
                if [ -n "$rest" ]; then args+=("$rest"); rest=""; else wantval=1; fi ;;
              *) args+=("-$c") ;;
            esac
          done ;;
        *) args+=("$a") ;;
      esac
    done
    rg "${args[@]}"
  }
else
  alias grep='grep --color=auto'
fi
alias lsblk='lsblk -e7 -o NAME,PATH,SIZE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS'
if [ "$TERM" = xterm-kitty ]; then
  alias ssh='TERM=xterm-256color ssh'
  command -v sshs >/dev/null && alias sshs='sshs --template "env TERM=xterm-256color ssh \"{{{name}}}\""'
fi

# tool hooks
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
command -v fzf >/dev/null && eval "$(fzf --bash)"
command -v zoxide >/dev/null && eval "$(zoxide init bash)"

# host overrides: last, wins over everything
_hostfile="$XDG_CONFIG_HOME/bash/hosts/$HOSTNAME.sh"
[ -r "$_hostfile" ] && . "$_hostfile"
unset _hostfile
