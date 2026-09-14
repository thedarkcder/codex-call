#!/bin/sh
set -eu

if [ "${FAKE_HELPER_FAIL:-0}" = "1" ]; then
  printf '%s\n' '{"ok":false,"error":"simulated helper failure"}'
  exit 0
fi

case "${1:-}" in
  call)
    if [ "${2:-}" = "end" ] && [ "${FAKE_HANGUP_FAIL:-0}" = "1" ]; then
      printf '%s\n' '{"ok":true,"state":"NORMAL","hungUp":false}'
    elif [ "${2:-}" = "end" ]; then
      printf '%s\n' '{"ok":true,"state":"NORMAL","hungUp":true}'
    else
      printf '%s\n' '{"ok":true,"state":"STARTING_CALL"}'
    fi
    ;;
  status)
    printf '%s\n' '{"ok":true,"state":"NORMAL","mode":"normal"}'
    ;;
  *)
    printf '%s\n' '{"ok":true}'
    ;;
esac
