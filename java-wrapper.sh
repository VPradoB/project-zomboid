#!/usr/bin/env bash
set -eu

case ${PZ_JAVA_MODE:-box64} in
  box64)
    exec "${BOX64_BIN:-/usr/bin/box64}" /opt/zomboid-server/jre64/bin/java "$@"
    ;;
  arm64)
    args=()
    for arg; do
      [[ $arg == -Xint ]] || args+=("$arg")
    done
    exec "${NATIVE_JAVA_BIN:-/opt/zulu25/bin/java}" "${args[@]}"
    ;;
  *)
    printf 'PZ_JAVA_MODE must be box64 or arm64, got: %s\n' "$PZ_JAVA_MODE" >&2
    exit 64
    ;;
esac
