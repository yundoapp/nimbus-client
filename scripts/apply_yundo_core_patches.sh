#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
core_dir="${repo_root}/hiddify-core"
patch_file="${repo_root}/patches/hiddify-core/0001-managed-route-options.patch"
rule_set_patch_file="${repo_root}/patches/hiddify-core/0002-rule-set-observability-and-root-domain.patch"
observability_patch_file="${repo_root}/patches/hiddify-core/0003-connection-observability-and-actual-outbound.patch"
exact_history_patch_file="${repo_root}/patches/hiddify-core/0004-exact-route-decision-history.patch"
bundled_rule_set_patch_file="${repo_root}/patches/hiddify-core/0005-bundled-rule-set-fallback.patch"
rule_set_status_patch_file="${repo_root}/patches/hiddify-core/0006-rule-set-status-api.patch"
active_outbound_delay_patch_file="${repo_root}/patches/hiddify-core/0007-active-outbound-url-test.patch"
sing_box_dir="${core_dir}/hiddify-sing-box"
expected_commit="c9d6f0f00b2eda34e4fb71863e4e0a62b3e931a0"

fail() {
  echo "Yundo Core patch failed: $*" >&2
  exit 1
}

[[ -f "${core_dir}/go.mod" ]] || fail "hiddify-core submodule is not initialized"
[[ -f "${patch_file}" ]] || fail "managed route patch is missing"
[[ -f "${rule_set_patch_file}" ]] || fail "rule-set patch is missing"
[[ -f "${observability_patch_file}" ]] || fail "connection observability patch is missing"
[[ -f "${exact_history_patch_file}" ]] || fail "exact route history patch is missing"
[[ -f "${bundled_rule_set_patch_file}" ]] || fail "bundled rule-set fallback patch is missing"
[[ -f "${rule_set_status_patch_file}" ]] || fail "rule-set status API patch is missing"
[[ -f "${active_outbound_delay_patch_file}" ]] || fail "active outbound delay patch is missing"
[[ -f "${sing_box_dir}/go.mod" ]] || fail "hiddify-sing-box submodule is not initialized"

actual_commit="$(git -C "${core_dir}" rev-parse HEAD)"
[[ "${actual_commit}" == "${expected_commit}" ]] \
  || fail "core source ${actual_commit} does not match reviewed commit ${expected_commit}"

if ! grep -Fq 'ManagedRouteRules' "${core_dir}/v2/config/hiddify_option.go" \
  || [[ ! -f "${core_dir}/v2/config/managed_route_test.go" ]]; then
  git -C "${core_dir}" apply --check "${patch_file}" \
    || fail "managed route patch does not apply cleanly"
  git -C "${core_dir}" apply "${patch_file}"
fi

if ! grep -Fq 'yundoCacheTag' "${sing_box_dir}/route/rule/rule_set_remote.go"; then
  git -C "${sing_box_dir}" apply --check "${rule_set_patch_file}" \
    || fail "rule-set patch does not apply cleanly"
  git -C "${sing_box_dir}" apply "${rule_set_patch_file}"
fi

if ! grep -Fq '"outbound":    outbound' "${sing_box_dir}/experimental/clashapi/trafficontrol/tracker.go"; then
  git -C "${sing_box_dir}" apply --check "${observability_patch_file}" \
    || fail "connection observability patch does not apply cleanly"
  git -C "${sing_box_dir}" apply "${observability_patch_file}"
fi

if ! grep -Fq 'yundo_exact_history' "${sing_box_dir}/experimental/clashapi/connections.go"; then
  git -C "${sing_box_dir}" apply --check "${exact_history_patch_file}" \
    || fail "exact route history patch does not apply cleanly"
  git -C "${sing_box_dir}" apply "${exact_history_patch_file}"
fi

if ! grep -Fq 'FallbackPath' "${sing_box_dir}/option/rule_set.go" \
  || ! grep -Fq 'loaded from bundled fallback' "${sing_box_dir}/route/rule/rule_set_remote.go"; then
  git -C "${sing_box_dir}" apply --check "${bundled_rule_set_patch_file}" \
    || fail "bundled rule-set fallback patch does not apply cleanly"
  git -C "${sing_box_dir}" apply "${bundled_rule_set_patch_file}"
fi

if ! grep -Fq 'func (r *Router) RuleSets()' "${sing_box_dir}/route/router.go" \
  || ! grep -Fq 'func (s *RemoteRuleSet) LastUpdated()' "${sing_box_dir}/route/rule/rule_set_remote.go" \
  || ! grep -Fq 'lastLoaded' "${sing_box_dir}/route/rule/rule_set_remote.go" \
  || ! grep -Fq 'RuleSets() []adapter.RuleSet' "${sing_box_dir}/experimental/clashapi/ruleprovider.go"; then
  git -C "${sing_box_dir}" apply --check "${rule_set_status_patch_file}" \
    || fail "rule-set status API patch does not apply cleanly"
  git -C "${sing_box_dir}" apply "${rule_set_status_patch_file}"
fi

if ! grep -Fq 'resolveSelectedOutboundTag' "${core_dir}/v2/hcore/proxy_info.go"; then
  git -C "${core_dir}" apply --ignore-whitespace --check "${active_outbound_delay_patch_file}" \
    || fail "active outbound delay patch does not apply cleanly"
  git -C "${core_dir}" apply --ignore-whitespace "${active_outbound_delay_patch_file}"
fi
