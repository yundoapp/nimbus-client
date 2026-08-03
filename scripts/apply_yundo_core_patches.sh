#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
core_dir="${repo_root}/hiddify-core"
patch_file="${repo_root}/patches/hiddify-core/0001-managed-route-options.patch"
expected_commit="c9d6f0f00b2eda34e4fb71863e4e0a62b3e931a0"

fail() {
  echo "Yundo Core patch failed: $*" >&2
  exit 1
}

[[ -f "${core_dir}/go.mod" ]] || fail "hiddify-core submodule is not initialized"
[[ -f "${patch_file}" ]] || fail "managed route patch is missing"

actual_commit="$(git -C "${core_dir}" rev-parse HEAD)"
[[ "${actual_commit}" == "${expected_commit}" ]] \
  || fail "core source ${actual_commit} does not match reviewed commit ${expected_commit}"

if grep -Fq 'ManagedRouteRules' "${core_dir}/v2/config/hiddify_option.go" \
  && [[ -f "${core_dir}/v2/config/managed_route_test.go" ]]; then
  exit 0
fi

git -C "${core_dir}" apply --check "${patch_file}" \
  || fail "managed route patch does not apply cleanly"
git -C "${core_dir}" apply "${patch_file}"
