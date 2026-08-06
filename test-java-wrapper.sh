#!/usr/bin/env bash
set -Eeuo pipefail

root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT

cat > "$root/record" <<'EOF'
#!/usr/bin/env bash
printf '<%s>\n' "$@"
EOF
chmod +x "$root/record"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ $1 == "$2" ]] || fail "expected [$2], got [$1]"; }

output=$(BOX64_BIN="$root/record" PZ_JAVA_MODE=box64 bash ./java-wrapper.sh -Xint '-Dname=two words')
assert_eq "$output" $'</opt/zomboid-server/jre64/bin/java>\n<-Xint>\n<-Dname=two words>'

output=$(NATIVE_JAVA_BIN="$root/record" PZ_JAVA_MODE=arm64 bash ./java-wrapper.sh -Xms2g -Xint '-Dname=two words')
assert_eq "$output" $'<-Xms2g>\n<-Dname=two words>'

if PZ_JAVA_MODE=invalid bash ./java-wrapper.sh >/dev/null 2>&1; then
  fail 'accepted invalid PZ_JAVA_MODE'
fi

printf 'java-wrapper harness: PASS\n'
