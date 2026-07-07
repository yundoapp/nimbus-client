#!/usr/bin/env bash
set -euo pipefail

label="${1:-snapshot}"
safe_label="$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '_')"
timestamp="$(date '+%Y%m%d-%H%M%S')"
out_dir="build/tun-evidence/${timestamp}-${safe_label}"

mkdir -p "$out_dir"

run_capture() {
  local name="$1"
  shift
  {
    echo "$ $*"
    "$@" 2>&1 || true
  } >"${out_dir}/${name}.txt"
}

{
  echo "timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "label=${label}"
  echo "hostname=$(hostname)"
  echo "user=$(id -un)"
  echo "pwd=$(pwd)"
} >"${out_dir}/meta.txt"

run_capture sw_vers sw_vers
run_capture ifconfig ifconfig
run_capture routes netstat -rn
run_capture dns scutil --dns
run_capture network_info scutil --nwi
run_capture default_route route -n get default
run_capture route_1_1_1_1 route -n get 1.1.1.1
run_capture route_8_8_8_8 route -n get 8.8.8.8
run_capture network_services networksetup -listallnetworkservices
run_capture proxies scutil --proxy
run_capture yundo_processes pgrep -afil 'Yundo|Hiddify|sing-box|hiddify'

cat <<EOF
Captured macOS network state:
${out_dir}

Suggested labels:
  before-tun
  connected-tun
  disconnected-tun
EOF
