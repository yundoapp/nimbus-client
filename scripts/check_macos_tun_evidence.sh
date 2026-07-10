#!/usr/bin/env bash
set -euo pipefail

before_dir="${1:-}"
connected_dir="${2:-}"
disconnected_dir="${3:-}"
strict="${4:-}"
blockers=()

for phase in "$before_dir" "$connected_dir" "$disconnected_dir"; do
  [[ -d "$phase" ]] || blockers+=("缺少三阶段采证目录")
done

required_files=(ifconfig.txt routes.txt default_route.txt route_1_1_1_1.txt dns.txt)
if (( ${#blockers[@]} == 0 )); then
  for phase in "$before_dir" "$connected_dir" "$disconnected_dir"; do
    for file in "${required_files[@]}"; do
      [[ -f "${phase}/${file}" ]] || blockers+=("采证目录缺少 ${file}")
    done
  done
fi

extract_interface() {
  sed -n 's/^[[:space:]]*interface: //p' "$1" | head -1
}

list_utun() {
  sed -n 's/^\(utun[0-9][0-9]*\):.*/\1/p' "$1" | sort -u
}

default_route_restored=false
public_route_restored=false
connected_has_new_utun=false
connected_route_uses_new_utun=false
disconnected_has_no_extra_utun=false

if (( ${#blockers[@]} == 0 )); then
  before_default="$(extract_interface "${before_dir}/default_route.txt")"
  disconnected_default="$(extract_interface "${disconnected_dir}/default_route.txt")"
  if [[ -n "$before_default" && "$disconnected_default" == "$before_default" ]]; then
    default_route_restored=true
  else
    blockers+=("断开后的默认出口未恢复到连接前")
  fi

  before_public="$(extract_interface "${before_dir}/route_1_1_1_1.txt")"
  disconnected_public="$(extract_interface "${disconnected_dir}/route_1_1_1_1.txt")"
  if [[ -n "$before_public" && "$disconnected_public" == "$before_public" ]]; then
    public_route_restored=true
  else
    blockers+=("断开后的公网路由未恢复到连接前")
  fi

  new_utun="$(comm -13 <(list_utun "${before_dir}/ifconfig.txt") <(list_utun "${connected_dir}/ifconfig.txt"))"
  if [[ -n "$new_utun" ]]; then
    connected_has_new_utun=true
    while IFS= read -r interface; do
      if [[ -n "$interface" ]] && rg -q "(^|[[:space:]])${interface}([[:space:]]|$)" "${connected_dir}/routes.txt"; then
        connected_route_uses_new_utun=true
        break
      fi
    done <<<"$new_utun"
  else
    blockers+=("连接阶段没有发现新增 utun 接口")
  fi
  [[ "$connected_route_uses_new_utun" == true ]] || blockers+=("连接阶段路由没有引用新增 utun 接口")

  disconnected_extra="$(comm -13 <(list_utun "${before_dir}/ifconfig.txt") <(list_utun "${disconnected_dir}/ifconfig.txt"))"
  if [[ -z "$disconnected_extra" ]]; then
    disconnected_has_no_extra_utun=true
  else
    blockers+=("断开后仍残留连接阶段新增的 utun 接口")
  fi
fi

status=ready
(( ${#blockers[@]} )) && status=blocked
summary_path="${disconnected_dir:-build/tun-evidence}/verification-summary.txt"
if [[ -d "${disconnected_dir:-}" ]]; then
  cat >"$summary_path" <<EOF
status=${status}
default_route_restored=${default_route_restored}
public_route_restored=${public_route_restored}
connected_has_new_utun=${connected_has_new_utun}
connected_route_uses_new_utun=${connected_route_uses_new_utun}
disconnected_has_no_extra_utun=${disconnected_has_no_extra_utun}
blocker_count=${#blockers[@]}
EOF
fi

echo "macOS TUN 三阶段证据检查：${status}"
echo "default_route_restored=${default_route_restored}"
echo "public_route_restored=${public_route_restored}"
echo "connected_has_new_utun=${connected_has_new_utun}"
echo "connected_route_uses_new_utun=${connected_route_uses_new_utun}"
echo "disconnected_has_no_extra_utun=${disconnected_has_no_extra_utun}"
if (( ${#blockers[@]} )); then
  printf '阻塞：%s\n' "${blockers[@]}"
fi
echo "说明：摘要不包含网关、DNS、IP 或接口名称；原始证据继续保存在被忽略的本地目录。"

[[ "$strict" == "--strict" && "$status" != "ready" ]] && exit 1
exit 0
