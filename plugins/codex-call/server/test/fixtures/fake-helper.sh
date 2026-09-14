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
    case "${FAKE_STATUS_STATE:-NORMAL}" in
      IN_CALL)
        printf '%s\n' '{"ok":true,"state":"IN_CALL","mode":"call"}'
        ;;
      STARTING_CALL)
        printf '%s\n' '{"ok":true,"state":"STARTING_CALL","mode":"call"}'
        ;;
      ERROR)
        printf '%s\n' '{"ok":true,"state":"ERROR","mode":"call"}'
        ;;
      *)
        printf '%s\n' '{"ok":true,"state":"NORMAL","mode":"normal"}'
        ;;
    esac
    ;;
  *)
    printf '%s\n' '{"ok":true}'
    ;;
esac
