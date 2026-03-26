# ~/.bashrc

# Add this for Starship prompt
eval "$(starship init bash)"

# Add this for Atuin shell history
# Sourcing bash-prexec enables full history context (directory, duration, exit code)
if [ -f /usr/share/bash-prexec ]; then
  source /usr/share/bash-prexec
fi
eval "$(atuin init bash)"

# Add this for zoxide (a smarter cd command)
eval "$(zoxide init bash)"

# Add fzf keybindings (Ctrl-T, Ctrl-R, Alt-C) and fuzzy completion
[[ -f /usr/share/fzf/shell/key-bindings.bash ]] && source /usr/share/fzf/shell/key-bindings.bash