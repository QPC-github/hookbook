# Hookbook (https://github.com/Shopify/hookbook)
#
# Copyright 2019 Shopify Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

__hookbook_shell="$(\ps -p $$ | \awk 'NR > 1 { sub(/^-/, "", $4); print $4 }')"
__hookbook_shellname="$(basename "${__hookbook_shell}")"

__hookbook_array_contains() {
  local seeking=$1; shift
  local in=1
  for element; do
    if [[ $element == $seeking ]]; then
      in=0
      break
    fi
  done
  return $in
}

case "${__hookbook_shellname}" in
  zsh)
    hookbook_add_hook() {
      local fn=$1

      eval "
        __hookbook_${fn}_preexec() { ${fn} zsh-preexec }
        __hookbook_${fn}_chpwd()   { ${fn} zsh-chpwd }
        __hookbook_${fn}_precmd()  { ${fn} zsh-precmd }
      "

      __hookbook_array_contains "__hookbook_${fn}_preexec" "${preexec_functions[@]}" \
        || preexec_functions+=("__hookbook_${fn}_preexec")

      __hookbook_array_contains "__hookbook_${fn}_chpwd" "${chpwd_functions[@]}" \
        || chpwd_functions+=("__hookbook_${fn}_chpwd")

      __hookbook_array_contains "__hookbook_${fn}_precmd" "${precmd_functions[@]}" \
        || precmd_functions+=("__hookbook_${fn}_precmd")
    }

    ;;
  bash)
    if declare -p __hookbook_functions >/dev/null 2>&1; then
      __hookbook_functions=()
    fi

    # Bash sometimes calls DEBUG with stderr redirected to /dev/null.
    # Yes. This is puzzling to me too.
    # Since we want our hooks to be able to generate stderr lines, let's not
    # call them in those cases.
    # `stat -f %Hr` retrieves a device major number on macOS, and `stat -c %t`
    # does the same on linux. /dev/null has a major number of 3 on macOS and 1
    # on linux, and /dev/stderr==/dev/fd/2 has a different number when
    # connected to a TTY (but /dev/fd/2 is a symlink on linux).
    if [[ "$(uname -s)" == "Darwin" ]]; then
      __dev_null_major="$(stat -f "%Hr" "/dev/null")"
      __stat_stderr='stat -f "%Hr" /dev/fd/2'
    else
      __dev_null_major="$(stat -c "%t" /dev/null)"
      __stat_stderr='stat -c "%t" "$(readlink -f "/dev/fd/2")"'
    fi
    eval "__hookbook_debug_handler() {
      if [[ \"\$(${__stat_stderr})\" == \"${__dev_null_major}\" ]]; then
        return
      fi
      for fn in \"\${__hookbook_functions[@]}\"; do
        \${fn} bash-debug
      done
    }"
    unset __stat_stderr
    unset __dev_null_major

    # If `set +x`, toggle off +x for the duration of the hook.
    # __hookbook_underscore preserves the value of $_, which is otherwise clobbered.
    # `env -u X true "$X"` unassigns X while setting $_ to its value.
    # The output redirection craziness is hard to follow here, but what it's
    # accomplishing is to route as much tracing output as possible to
    # /dev/null, whilst keeping any stderr output generated by the handler on
    # stderr.
    trap '
      {
        __hookbook_underscore=$_
        if [[ $- =~ x ]]; then
          set +x
          __hookbook_debug_handler 2>&3
          set -x
        else
          __hookbook_debug_handler 2>&3
        fi
        env -u __hookbook_underscore true "$__hookbook_underscore"
    } 4>&2 2>/dev/null 3>&4
    ' DEBUG

    hookbook_add_hook() {
      local fn=$1

      if [[ ! "${PROMPT_COMMAND}" == *" $fn "* ]]; then
        # This is essentially:
        #   PROMPT_COMMAND="${fn}; ${PROMPT_COMMAND}"
        # ...except with weird magic to toggle off `-x` if it's set, much like
        # in the DEBUG trap above.
        PROMPT_COMMAND="{
          if [[ \$- =~ x ]];
          then set +x; ${fn} bash-prompt 2>&3; set -x;
          else ${fn} bash-prompt 2>&3;
          fi;
        } 4>&2 2>/dev/null 3>&4;
        ${PROMPT_COMMAND}"
      fi

      __hookbook_array_contains "${fn}" "${__hookbook_functions[@]}" \
        || __hookbook_functions+=("${fn}")
    }
    ;;
  *)
    >&2 \echo "hookbook is not compatible with your shell (${__hookbook_shell})"
    \return 1
    ;;
esac

unset __hookbook_shell
unset __hookbook_shellname
