#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
assets_dir="${repo_root}/assets/rules"
api_base_url="${YUNDO_API_BASE_URL:-${NIMBUS_API_BASE_URL:-https://api.yundo.app/api/v1}}"
api_base_url="${api_base_url%/}"
package_url="${api_base_url}/rules/public-package"
# Keep provenance stable even when a local API is used to refresh the checked-in
# snapshot. A localhost URL must never become the public app's rule source.
snapshot_source_url="${YUNDO_RULE_SNAPSHOT_SOURCE_URL:-https://api.yundo.app/api/v1/rules/public-package}"
package_connect_timeout="${YUNDO_RULE_PACKAGE_CONNECT_TIMEOUT:-10}"
package_max_time="${YUNDO_RULE_PACKAGE_MAX_TIME:-30}"
package_retry="${YUNDO_RULE_PACKAGE_RETRY:-1}"
source_connect_timeout="${YUNDO_RULE_SOURCE_CONNECT_TIMEOUT:-10}"
source_max_time="${YUNDO_RULE_SOURCE_MAX_TIME:-30}"
source_retry="${YUNDO_RULE_SOURCE_RETRY:-0}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/yundo-rule-cache.XXXXXX")"
package_source_mode="remote"

cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

log() {
  echo "Yundo rules: $*"
}

keep_existing_snapshot() {
  if [[ -s "${assets_dir}/manifest.json" ]] && find "${assets_dir}" -maxdepth 1 -type f -name '*.srs' -print -quit | grep -q .; then
    log "远程规则包不可用，继续使用已有内置快照"
    return 0
  fi
  echo "Yundo rules: 远程规则包不可用，且没有可用的内置快照" >&2
  return 1
}

use_checked_in_manifest_as_package() {
  local manifest_file="${assets_dir}/manifest.json"
  [[ -s "${manifest_file}" ]] || return 1
  jq -e '
    (.items | type == "array" and length > 0)
    and all(.items[];
      ((.tag // .pattern) | type == "string")
      and (.sourceUrl | type == "string")
    )
  ' "${manifest_file}" >/dev/null || return 1

  jq -n --slurpfile snapshot "${manifest_file}" '
    ($snapshot[0]) as $manifest |
    {
      manifest: {
        publicRulesVersion: ($manifest.publicRulesVersion // null),
        publicRulesSourceVersion: ($manifest.publicRulesSourceVersion // ""),
        publicRulesUpdatedAt: ($manifest.publicRulesUpdatedAt // null)
      },
      publicRules: [
        $manifest.items[] |
        {
          kind: "rule_set",
          pattern: (.tag // .pattern),
          patternType: (.patternType // null),
          action: (.action // "accelerate"),
          sourceUrl: .sourceUrl
        }
      ]
    }
  ' >"${response_file}"
  package_source_mode="checked-in-manifest"
  log "远程公共规则包不可用，使用已有可信规则清单刷新内置快照"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

for command_name in curl date find grep jq mktemp mv awk; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "Yundo rules: 缺少 ${command_name}" >&2
    keep_existing_snapshot
    exit $?
  }
done

response_file="${work_dir}/public-package.json"
if ! curl --fail --location --silent --show-error \
  --connect-timeout "${package_connect_timeout}" --max-time "${package_max_time}" \
  --retry "${package_retry}" --retry-all-errors \
  -H 'accept: application/json' "${package_url}" -o "${response_file}"; then
  if ! use_checked_in_manifest_as_package; then
    keep_existing_snapshot
    exit $?
  fi
fi

if ! jq -e '.manifest and (.publicRules | type == "array")' "${response_file}" >/dev/null; then
  log "公共规则包响应格式无效：${package_url}" >&2
  if ! use_checked_in_manifest_as_package; then
    keep_existing_snapshot
    exit $?
  fi
fi

items_file="${work_dir}/rule-set-items.jsonl"
jq -c '.publicRules[] | select(.kind == "rule_set" and (.pattern | type == "string") and (.sourceUrl | type == "string"))' \
  "${response_file}" >"${items_file}"

rule_count="$(wc -l <"${items_file}" | awk '{print $1}')"
if [[ "${rule_count}" -eq 0 ]]; then
  log "公共规则包没有可下载的 rule_set，拒绝覆盖已有快照" >&2
  keep_existing_snapshot
  exit $?
fi

stage_dir="${work_dir}/rules"
mkdir -p "${stage_dir}"
downloaded_items='[]'
while IFS= read -r item; do
  tag="$(jq -r '.pattern' <<<"${item}")"
  pattern_type="$(jq -r '.patternType // (if (.pattern | startswith("geoip-")) then "geoip" else "geosite" end)' <<<"${item}")"
  action="$(jq -r '.action // "accelerate"' <<<"${item}")"
  source_url="$(jq -r '.sourceUrl' <<<"${item}")"
  if [[ ! "${tag}" =~ ^[A-Za-z0-9_.!-]+$ ]]; then
    log "规则标签包含不安全字符：${tag}" >&2
    keep_existing_snapshot
    exit $?
  fi

  asset_path="${stage_dir}/${tag}.srs"
  log "下载 ${tag}"
  if ! curl --fail --location --silent --show-error \
    --connect-timeout "${source_connect_timeout}" --max-time "${source_max_time}" \
    --retry "${source_retry}" --retry-all-errors \
    -H 'accept: application/octet-stream' "${source_url}" -o "${asset_path}"; then
    log "下载失败：${tag}（${source_url}）" >&2
    keep_existing_snapshot
    exit $?
  fi

  file_size="$(wc -c <"${asset_path}" | awk '{print $1}')"
  [[ "${file_size}" -gt 0 ]] || {
    log "下载内容为空：${tag}" >&2
    keep_existing_snapshot
    exit $?
  }
  sha256="$(sha256_file "${asset_path}")"
  downloaded_items="$(jq -c \
    --arg tag "${tag}" \
    --arg patternType "${pattern_type}" \
    --arg action "${action}" \
    --arg sourceUrl "${source_url}" \
    --arg sha256 "${sha256}" \
    --arg asset "assets/rules/${tag}.srs" \
    '. + [{tag: $tag, patternType: $patternType, action: $action, sourceUrl: $sourceUrl, sha256: $sha256, asset: $asset}]' \
    <<<"${downloaded_items}")"
done <"${items_file}"

public_version_json="$(jq -c '.manifest.publicRulesVersion // null' "${response_file}")"
source_version="$(jq -r '.manifest.publicRulesSourceVersion // ""' "${response_file}")"
updated_at_json="$(jq -c '.manifest.publicRulesUpdatedAt // null' "${response_file}")"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
jq -n \
  --argjson publicRulesVersion "${public_version_json}" \
  --arg publicRulesSourceVersion "${source_version}" \
  --argjson publicRulesUpdatedAt "${updated_at_json}" \
  --arg generatedAt "${generated_at}" \
  --arg source "${snapshot_source_url}" \
  --argjson items "${downloaded_items}" \
  '{schemaVersion: 1, publicRulesVersion: $publicRulesVersion, publicRulesSourceVersion: $publicRulesSourceVersion, publicRulesUpdatedAt: $publicRulesUpdatedAt, generatedAt: $generatedAt, source: $source, items: $items}' \
  >"${stage_dir}/manifest.json"

# Keep the checked-in snapshot stable when the published package did not
# change. Build metadata must describe an actual rules change, not merely a
# repeated client build.
if [[ -f "${assets_dir}/manifest.json" ]]; then
  current_fingerprint="${work_dir}/current-fingerprint.json"
  next_fingerprint="${work_dir}/next-fingerprint.json"
  jq -S 'del(.generatedAt)' "${assets_dir}/manifest.json" >"${current_fingerprint}"
  jq -S 'del(.generatedAt)' "${stage_dir}/manifest.json" >"${next_fingerprint}"
  if cmp -s "${current_fingerprint}" "${next_fingerprint}"; then
    log "公共规则包未变化，保留现有内置快照（版本 $(jq -r '.publicRulesVersion // "-"' "${assets_dir}/manifest.json")）"
    exit 0
  fi
fi

backup_dir="${work_dir}/previous-rules"
if [[ -d "${assets_dir}" ]]; then
  mv "${assets_dir}" "${backup_dir}"
fi
if ! mv "${stage_dir}" "${assets_dir}"; then
  if [[ -d "${backup_dir}" ]]; then mv "${backup_dir}" "${assets_dir}"; fi
  echo "Yundo rules: 无法替换内置规则快照" >&2
  exit 1
fi

if [[ "${package_source_mode}" == "checked-in-manifest" ]]; then
  log "已用可信清单缓存 ${rule_count} 个云渡公共规则集，版本 $(jq -r '.manifest.publicRulesVersion // "-"' "${response_file}")"
else
  log "已缓存 ${rule_count} 个云渡公共规则集，版本 $(jq -r '.manifest.publicRulesVersion // "-"' "${response_file}")"
fi
