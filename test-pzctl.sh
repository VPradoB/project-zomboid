#!/usr/bin/env bash
set -Eeuo pipefail

root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin" "$root/data/mods" "$root/data/Server"

cat > "$root/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -eu
out=
url=
while (($#)); do
  case $1 in
    -o) out=$2; shift 2 ;;
    http*) url=$1; shift ;;
    *) shift ;;
  esac
done
case $url in
  # Mirrors the class/id shape consumed from upstream Workshop collection HTML.
  *id=999999) printf '<div class="collectionItem" id="sharedfile_111111"></div>\n<div class="collectionItem" id="sharedfile_222222"></div>\n' > "$out" ;;
  *) printf '<html>single item</html>\n' > "$out" ;;
esac
EOF

cat > "$root/bin/depot" <<'EOF'
#!/usr/bin/env bash
set -eu
app=
id=
dir=
while (($#)); do
  case $1 in
    -app) app=$2; shift 2 ;;
    -pubfile) id=$2; shift 2 ;;
    -dir) dir=$2; shift 2 ;;
    *) exit 90 ;;
  esac
done
[[ $app == 108600 && $id =~ ^[0-9]+$ && -n $dir ]]
case $id in
  111111)
    mkdir -p "$dir/steamapps/workshop/content/108600/$id/mods/Alpha"
    printf 'name=Alpha\nid=alpha\n' > "$dir/steamapps/workshop/content/108600/$id/mods/Alpha/mod.info"
    ;;
  222222)
    mkdir -p "$dir/content/mods/Nested/42" "$dir/content/mods/Beta"
    printf 'name=Nested\nid=nested\n' > "$dir/content/mods/Nested/mod.info"
    printf 'name=Nested B42\nid=nested\n' > "$dir/content/mods/Nested/42/mod.info"
    printf 'name=Beta\nid=beta\n' > "$dir/content/mods/Beta/mod.info"
    ;;
  333333)
    mkdir -p "$dir/content/mods/Bad"
    printf 'id=bad;id\n' > "$dir/content/mods/Bad/mod.info"
    ;;
  444444)
    mkdir -p "$dir/content/mods/Bad\$name"
    printf 'id=valid\n' > "$dir/content/mods/Bad\$name/mod.info"
    ;;
esac
EOF
chmod +x "$root/bin/curl" "$root/bin/depot"

export PATH="$root/bin:$PATH"
export PZ_HOME="$root/data" PZ_MODS="$root/data/mods"
export PZ_INI="$root/data/Server/test.ini" PZ_DD="$root/bin/depot"
pzctl=./pzctl

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ $1 == "$2" ]] || fail "expected [$2], got [$1]"; }
assert_file() { [[ -e $1 ]] || fail "missing $1"; }
assert_not_file() { [[ ! -e $1 ]] || fail "unexpected $1"; }
assert_no_config_tmp() {
  if compgen -G "$(dirname "$PZ_INI")/.pzctl.ini.*" >/dev/null; then fail 'config temp survived'; fi
}

rm -f "$PZ_INI"
assert_eq "$($pzctl list)" '(none)'
printf 'PublicName=Keep Me\n' > "$PZ_INI"
output=$($pzctl add 'https://steamcommunity.com/sharedfiles/filedetails/?id=111111')
[[ $output == *'Players must subscribe: https://steamcommunity.com/sharedfiles/filedetails/?id=111111'* ]] || fail 'missing player subscription link'
assert_file "$PZ_MODS/Alpha/mod.info"
assert_eq "$(awk -F= '/^Mods=/{print $2}' "$PZ_INI")" alpha
assert_eq "$(awk -F= '/^PublicName=/{print $2}' "$PZ_INI")" 'Keep Me'
assert_eq "$(stat -c %a "$PZ_INI")" 600
assert_not_file "$PZ_MODS/42"

$pzctl add 222222 >/dev/null
mods=$(awk -F= '/^Mods=/{print $2}' "$PZ_INI")
[[ ";$mods;" == *';alpha;'* && ";$mods;" == *';nested;'* && ";$mods;" == *';beta;'* ]] || fail "multiple roots not activated: $mods"
assert_eq "$(tr ';' '\n' <<< "$mods" | grep -c '^nested$')" 1
assert_file "$PZ_MODS/Nested/42/mod.info"

$pzctl add 222222 >/dev/null
assert_eq "$(tr ';' '\n' < <(awk -F= '/^Mods=/{print $2}' "$PZ_INI") | sort | uniq -d)" ''
assert_eq "$($pzctl list | sort | tr '\n' ' ')" 'alpha beta nested '

cat > "$PZ_INI" <<'EOF'
Before=one
Mods=alpha;;beta;alpha
Middle=keep
Mods=;gamma;beta;
Mods=
After=two
EOF
assert_eq "$($pzctl list | tr '\n' ' ')" 'alpha beta gamma '
assert_eq "$(cat "$PZ_INI")" $'Before=one\nMods=alpha;beta;gamma\nMiddle=keep\nAfter=two'
assert_eq "$(grep -c '^Mods=' "$PZ_INI")" 1

cat > "$PZ_INI" <<'EOF'
Mods=alpha;beta
Keep=this
Mods=gamma;alpha;gamma
EOF
$pzctl remove alpha >/dev/null
assert_file "$PZ_MODS/Alpha/mod.info"
assert_eq "$(cat "$PZ_INI")" $'Mods=beta;gamma\nKeep=this'

printf 'Mods=\nKeep=empty\nMods=;;\n' > "$PZ_INI"
assert_eq "$($pzctl list)" '(none)'
assert_eq "$(cat "$PZ_INI")" $'Mods=\nKeep=empty'

rm -rf "$PZ_MODS"/*
printf 'OtherSetting=true\n' > "$PZ_INI"
output=$($pzctl add 999999)
[[ $output == *'id=999999'* ]] || fail 'collection link missing'
assert_file "$PZ_MODS/Alpha/mod.info"
assert_file "$PZ_MODS/Beta/mod.info"
assert_file "$PZ_MODS/Nested/mod.info"
assert_eq "$(grep -c '^Mods=' "$PZ_INI")" 1

if $pzctl add not-an-id >/dev/null 2>&1; then fail 'accepted invalid Workshop ID'; fi
if $pzctl add 333333 >/dev/null 2>&1; then fail 'accepted invalid mod ID'; fi
if $pzctl add 444444 >/dev/null 2>&1; then fail 'accepted invalid mod directory'; fi
if $pzctl remove 'bad;id' >/dev/null 2>&1; then fail 'accepted invalid remove ID'; fi

help=$($pzctl --help)
[[ $help == *'Players manually subscribe to the printed Workshop link.'* ]] || fail 'help omits manual subscription'
[[ $help == *'Changes require restarting the container via Coolify.'* ]] || fail 'help omits Coolify restart'

mkdir "$root/fault-bin"
cat > "$root/fault-bin/awk" <<'EOF'
#!/usr/bin/env bash
set -eu
if [[ ${PZCTL_AWK_MODE:-} && ${1:-} == -v && ${2:-} == value=* ]]; then
  case $PZCTL_AWK_MODE in
    error) exit 42 ;;
    signal) touch "$PZCTL_AWK_READY"; sleep 30 ;;
  esac
fi
exec /usr/bin/awk "$@"
EOF
chmod +x "$root/fault-bin/awk"
printf 'Mods=alpha\n' > "$PZ_INI"
touch "$root/data/Server/unrelated"
if PATH="$root/fault-bin:$PATH" PZCTL_AWK_MODE=error $pzctl list >/dev/null 2>&1; then
  fail 'config write error unexpectedly succeeded'
fi
assert_no_config_tmp
assert_eq "$(< "$PZ_INI")" 'Mods=alpha'
assert_file "$root/data/Server/unrelated"

ready=$root/awk-ready
setsid env PATH="$root/fault-bin:$PATH" PZCTL_AWK_MODE=signal PZCTL_AWK_READY="$ready" $pzctl list >/dev/null 2>&1 &
pid=$!
for _ in {1..100}; do [[ -e $ready ]] && break; sleep 0.01; done
[[ -e $ready ]] || fail 'signal cleanup test did not reach config write'
kill -TERM -- "-$pid"
if wait "$pid"; then fail 'signaled config write unexpectedly succeeded'; fi
assert_no_config_tmp
assert_eq "$(< "$PZ_INI")" 'Mods=alpha'
assert_file "$root/data/Server/unrelated"

mkdir "$root/root-bin"
cat > "$root/root-bin/install" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$root/root-bin/setpriv" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$PATH" > "$PZCTL_ROOT_PATH"
printf '%s\n' "$@" > "$PZCTL_ROOT_ARGS"
EOF
chmod +x "$root/root-bin/install" "$root/root-bin/setpriv"
root_path=$root/root-path root_args=$root/root-args
unshare --user --map-root-user env PATH="$root/root-bin:$PATH" PZCTL_ROOT_PATH="$root_path" \
  PZCTL_ROOT_ARGS="$root_args" PZ_USER=nobody PZ_HOME="$PZ_HOME" PZ_MODS="$PZ_MODS" \
  PZ_INI="$PZ_INI" PZ_DD="$PZ_DD" $pzctl list
[[ $(< "$root_path") == "$root/root-bin:"* ]] || fail 'root re-exec lost PATH'
grep -Fxq "env" "$root_args" || fail 'root re-exec omitted env'
grep -Fxq "$pzctl" "$root_args" || fail 'root re-exec omitted script path'
grep -Fxq "list" "$root_args" || fail 'root re-exec omitted command arguments'

printf 'pzctl harness: PASS\n'
