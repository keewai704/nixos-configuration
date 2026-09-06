# Run after activation: zsh -i hosts/citrus/check-shell.zsh
setopt errexit

[[ -o interactive ]]
[[ ${_comps[yt-dlp]} == _yt-dlp ]]
[[ ${_comps[pymobiledevice3]} == _pymobiledevice3 ]]
(( $+functions[_zsh_autosuggest_start] ))
(( $+functions[_zsh_highlight] ))
(( $+widgets[fzf-history-widget] ))
(( $+functions[z] && $+functions[zi] ))

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

print 'zsh plugins and yt-dlp/pymobiledevice3 completion passed'
