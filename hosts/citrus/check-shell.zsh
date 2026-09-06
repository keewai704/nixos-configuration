# Run after activation: zsh -i hosts/citrus/check-shell.zsh
setopt errexit

[[ -o interactive ]]
[[ ${_comps[yt-dlp]} == _yt-dlp ]]
[[ ${_comps[pymobiledevice3]} == _pymobiledevice3 ]]
(( $+functions[_zsh_autosuggest_start] ))
(( $+functions[_zsh_highlight] ))
(( $+functions[history-substring-search-up] ))
(( $+functions[nix-shell] ))
(( $+functions[prompt_starship_precmd] ))
[[ $(bindkey '^[[A') == *history-substring-search-up* ]]
[[ $(bindkey '^[[B') == *history-substring-search-down* ]]
[[ -s ${STARSHIP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml} ]]
starship prompt --path /tmp >/dev/null
(( $+widgets[fzf-history-widget] ))
(( $+functions[z] && $+functions[zi] ))

[[ $aliases[ls] == eza && $aliases[cat] == 'bat --paging=never' ]]
[[ $aliases[tree] == 'eza --tree' && $aliases[ff] == fd ]]
[[ $aliases[du] == dust && $aliases[df] == duf && $aliases[top] == btop ]]
# Replacing cat must preserve plain text when output is piped.
[[ $(printf 'modern CLI\n' | cat) == 'modern CLI' ]]
eza --version >/dev/null
fd --version >/dev/null
dust --version >/dev/null
duf --version >/dev/null
btop --version >/dev/null

# Capture candidates without requiring an interactive ZLE completion widget.
_arguments() { candidates="$*"; }
typeset candidates
words=(yt-dlp --)
CURRENT=2
_yt-dlp
[[ $candidates == *--format* && $candidates == *--extract-audio* ]]

words=(pymobiledevice3 dev)
CURRENT=2
_pymobiledevice3
[[ $candidates == *developer* ]]
words=(pymobiledevice3 developer core)
CURRENT=3
_pymobiledevice3
[[ $candidates == *core-device* ]]

print 'zsh plugins, CLI aliases and yt-dlp/pymobiledevice3 completion passed'
