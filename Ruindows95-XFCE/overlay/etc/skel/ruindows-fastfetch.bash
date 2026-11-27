
# Ruindows95 V8: Fastfetch on interactive local terminals.
if [[ $- == *i* && -t 1 && -z ${SSH_CONNECTION:-} && ${TERM:-dumb} != dumb ]] && command -v fastfetch >/dev/null 2>&1; then
    command fastfetch
fi
