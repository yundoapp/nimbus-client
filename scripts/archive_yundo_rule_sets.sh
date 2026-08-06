#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
config_file="${YUNDO_RULE_CONFIG:-$HOME/Library/Application Support/app.yundo.client/data/current-config.json}"
output_dir="${YUNDO_RULE_ARCHIVE_DIR:-/Users/kandejian/workspace/nimbus资料/yundo-rule-sets}"
sing_box_bin="${SING_BOX_BIN:-/tmp/yundo-sing-box-go125}"
cache_dir="${YUNDO_RULE_CACHE_DIR:-$HOME/Library/Application Support/app.yundo.client/yundo-rule-sets}"
temp_dir=""

fail() {
  echo "Yundo rule-set archive failed: $*" >&2
  exit 1
}

cleanup() {
  [[ -z "${temp_dir}" || ! -d "${temp_dir}" ]] || rm -rf "${temp_dir}"
}

trap cleanup EXIT

for command_name in curl find jq shasum; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "missing ${command_name}"
done
[[ -f "${config_file}" ]] || fail "config file not found: ${config_file}"
[[ -x "${sing_box_bin}" ]] || fail "sing-box binary not found: ${sing_box_bin}"

mkdir -p "${output_dir}"
temp_dir="$(mktemp -d)"
manifest_items="${temp_dir}/manifest-items.jsonl"
: >"${manifest_items}"
tool_version="$(${sing_box_bin} version | head -n 1)"
archived_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

while IFS=$'\t' read -r tag url; do
  [[ -n "${tag}" && -n "${url}" ]] || continue
  source_name="$(basename "${url}")"
  local_source="${cache_dir}/${source_name}"
  downloaded_source="${temp_dir}/${tag}.srs"
  if [[ -f "${local_source}" ]]; then
    source_path="${local_source}"
    source_kind="local-cache"
  else
    curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 "${url}" -o "${downloaded_source}"
    source_path="${downloaded_source}"
    source_kind="remote-download"
  fi

  sha256="$(shasum -a 256 "${source_path}" | awk '{print $1}')"
  short_sha="${sha256:0:12}"
  stem="${tag}.${short_sha}"
  archived_srs="${output_dir}/${stem}.srs"
  archived_json="${output_dir}/${stem}.json"
  [[ -f "${archived_srs}" ]] || cp "${source_path}" "${archived_srs}"
  if [[ ! -f "${archived_json}" ]]; then
    "${sing_box_bin}" rule-set decompile "${source_path}" -o "${archived_json}"
  fi

  jq -cn \
    --arg tag "${tag}" \
    --arg url "${url}" \
    --arg sourceKind "${source_kind}" \
    --arg sha256 "${sha256}" \
    --arg srs "$(basename "${archived_srs}")" \
    --arg json "$(basename "${archived_json}")" \
    --arg sourceName "${source_name}" \
    '{tag:$tag, sourceUrl:$url, sourceKind:$sourceKind, sourceName:$sourceName, sha256:$sha256, srsFile:$srs, decodedJsonFile:$json}' \
    >>"${manifest_items}"
done < <(jq -r '.route.rule_set[] | select(.url != null) | [.tag, .url] | @tsv' "${config_file}")

jq -s \
  --arg generatedAt "${archived_at}" \
  --arg configFile "${config_file}" \
  --arg toolVersion "${tool_version}" \
  --arg sourceRepo "${repo_root}" \
  '{generatedAt:$generatedAt, configFile:$configFile, decoder:{binary:$toolVersion, command:"rule-set decompile <binary-path>"}, sourceRepo:$sourceRepo, items:sort_by(.tag, .sha256)}' \
  "${manifest_items}" >"${output_dir}/manifest.json"

echo "Archived $(jq '.items | length' "${output_dir}/manifest.json") rule sets to ${output_dir}"
