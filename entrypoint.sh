#!/usr/bin/env bash
set -Eeuo pipefail

install_dir=/opt/zomboid-server
data_dir=/home/zomboid/Zomboid
workshop="$install_dir/steamapps/workshop/content/108600"
workshop_store="${workshop}.ci"
console="$data_dir/server-console.txt"
server_pid=

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill -TERM "$server_pid"
    wait "$server_pid" || true
  fi
  mountpoint -q "$workshop" && fusermount3 -u "$workshop" || true
}
trap 'cleanup; exit 0' TERM INT

case "$(uname -m)" in
  aarch64|arm64) ;;
  *) printf 'This image requires an ARM64 host. Detected: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

: "${ADMIN_PASSWORD:?ADMIN_PASSWORD must be set}"
RAM_GB=${RAM_GB:-8}
SERVER_ID=${SERVER_ID:-servertest}
[[ "$RAM_GB" =~ ^[0-9]+$ ]] && (( RAM_GB >= 2 )) || { echo 'RAM_GB must be an integer of at least 2' >&2; exit 1; }
[[ "$SERVER_ID" =~ ^[A-Za-z0-9_-]+$ ]] || { echo 'SERVER_ID may only contain letters, numbers, underscores, and hyphens' >&2; exit 1; }

mkdir -p "$install_dir" "$data_dir"
chown zomboid:zomboid "$install_dir" "$data_dir"
setpriv --reuid=zomboid --regid=zomboid --init-groups env HOME=/home/zomboid \
  /opt/depotdownloader/DepotDownloader -app 380870 -branch unstable -os linux -dir "$install_dir"

chmod +x "$install_dir/ProjectZomboid64" "$install_dir"/*.sh "$install_dir"/jre64/bin/* 2>/dev/null || true
[[ -e "$install_dir/jre64/lib/jspawnhelper" ]] && chmod +x "$install_dir/jre64/lib/jspawnhelper"
sed "s/__XMX__/${RAM_GB}g/" /usr/local/share/zomboid/ProjectZomboid64.json > "$install_dir/ProjectZomboid64.json"

if [[ -d "$workshop" && ! -d "$workshop_store" ]]; then
  mv "$workshop" "$workshop_store"
fi
install -d -o zomboid -g zomboid "$workshop_store" "$workshop" "$data_dir/mods"
grep -qxF user_allow_other /etc/fuse.conf || echo user_allow_other >> /etc/fuse.conf
ciopfs -o allow_other "$workshop_store" "$workshop"
mountpoint -q "$workshop" || { echo 'ciopfs mount failed; /dev/fuse and SYS_ADMIN are required' >&2; exit 1; }

cd "$install_dir"
export PATH="$install_dir/jre64/bin:$PATH"
export BOX64_LD_LIBRARY_PATH="$install_dir/linux64:$install_dir/natives:$install_dir:$install_dir/jre64/lib/amd64"
export BOX64_LD_PRELOAD=libjsig.so
attempt=0
while true; do
  attempt=$((attempt + 1))
  printf 'Starting Project Zomboid through box64 (attempt %d)\n' "$attempt"
  setpriv --reuid=zomboid --regid=zomboid --init-groups env HOME=/home/zomboid \
    box64 ./ProjectZomboid64 -servername "$SERVER_ID" -adminpassword "$ADMIN_PASSWORD" &
  server_pid=$!

  while kill -0 "$server_pid" 2>/dev/null; do
    sleep 15 & wait $! || true
    kill -0 "$server_pid" 2>/dev/null || break
    ss -uln | grep -q ':16261 ' && continue
    idle=$(( $(date +%s) - $(stat -c %Y "$console" 2>/dev/null || echo 0) ))
    (( idle >= 360 )) || continue
    [[ -r /sys/fs/cgroup/cpu.stat ]] || continue
    cpu_before=$(awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
    sleep 8 & wait $! || true
    cpu_after=$(awk '/usage_usec/{print $2}' /sys/fs/cgroup/cpu.stat)
    if (( cpu_after - cpu_before < 2000000 )); then
      echo "Boot stalled for ${idle}s with low CPU; retrying"
      kill -TERM "$server_pid"
      break
    fi
  done

  set +e
  wait "$server_pid"
  status=$?
  set -e
  server_pid=
  printf 'Server exited with status %d; retrying in 20 seconds\n' "$status"
  sleep 20
done
