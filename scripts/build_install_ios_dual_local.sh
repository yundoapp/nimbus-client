#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
flutter_bin="${FLUTTER_BIN:-$(command -v flutter || true)}"
team_id="${APPLE_TEAM_ID:-W684N2R45F}"
device_id="${IOS_DEVICE_ID:-00008140-00163DEE1160801C}"
simulator_id="${IOS_SIMULATOR_ID:-03D52C64-8BE2-41BC-B3A1-9DE2ADBC0912}"
build_number="${YUNDO_LOCAL_BUILD_NUMBER:-$(awk -F+ '/^version: / { print $2; exit }' "${repo_root}/pubspec.yaml")}"
simulator_api_base_url="${IOS_SIMULATOR_API_BASE_URL:-http://127.0.0.1:4000/api/v1}"
device_api_base_url="${IOS_DEVICE_API_BASE_URL:-http://$(ipconfig getifaddr en0)/api/v1}"
production_api_base_url="${NIMBUS_PROD_API_BASE_URL:-https://api.yundo.app/api/v1}"
dual_root="${IOS_DUAL_BUILD_DIR:-${repo_root}/build/ios/dual-${build_number}}"

fail() {
  echo "错误：$*" >&2
  exit 1
}

[[ -d "${developer_dir}" ]] || fail "找不到 Xcode Developer 目录：${developer_dir}"
[[ -x "${flutter_bin}" ]] || fail "找不到 Flutter；请设置 FLUTTER_BIN"
[[ "${build_number}" =~ ^[0-9]+$ ]] || fail "构建号必须是纯数字：${build_number}"
for command_name in awk curl ditto ipconfig make plutil xcodebuild; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "缺少 ${command_name}"
done

export DEVELOPER_DIR="${developer_dir}"
export PATH="$(dirname "${flutter_bin}"):${PATH}"
cd "${repo_root}"
mkdir -p "${dual_root}"

[[ "$(curl -fsS -o /dev/null -w '%{http_code}' "${device_api_base_url}/health")" == 200 ]] \
  || fail "本地 API 不可用：${device_api_base_url}"
[[ "$(curl -fsS -o /dev/null -w '%{http_code}' "${production_api_base_url}/health")" == 200 ]] \
  || fail "生产 API 不可用：${production_api_base_url}"

make common-prepare
"${script_dir}/build_yundo_ios_core.sh"
(cd ios && pod install)

install_simulator_app() {
  local app_path="$1"
  local bundle_id="$2"
  xcrun simctl terminate "${simulator_id}" "${bundle_id}" >/dev/null 2>&1 || true
  xcrun simctl install "${simulator_id}" "${app_path}"
  xcrun simctl launch "${simulator_id}" "${bundle_id}"
}

build_simulator_dev() {
  flutter build ios --simulator --debug \
    --target=lib/main.dart \
    --build-number="${build_number}" \
    --dart-define="NIMBUS_API_BASE_URL=${simulator_api_base_url}"
  local app_path="${dual_root}/Yundo Dev-iOS-Simulator.app"
  ditto build/ios/iphonesimulator/Runner.app "${app_path}"
  [[ "$(plutil -extract CFBundleIdentifier raw -o - "${app_path}/Info.plist")" == app.yundo.client.dev ]] \
    || fail "iOS Simulator 开发版 Bundle ID 不正确"
  install_simulator_app "${app_path}" app.yundo.client.dev
}

build_simulator_prod() {
  flutter build ios --simulator --release \
    --target=lib/main_prod.dart \
    --build-number="${build_number}" \
    --dart-define="NIMBUS_API_BASE_URL=${production_api_base_url}"
  local app_path="${dual_root}/Yundo-iOS-Simulator.app"
  ditto build/ios/iphonesimulator/Runner.app "${app_path}"
  [[ "$(plutil -extract CFBundleIdentifier raw -o - "${app_path}/Info.plist")" == app.yundo.client ]] \
    || fail "iOS Simulator 正式版 Bundle ID 不正确"
  install_simulator_app "${app_path}" app.yundo.client
}

install_device_app() {
  local app_path="$1"
  local bundle_id="$2"
  xcrun devicectl device install app --device "${device_id}" "${app_path}"
  xcrun devicectl device process launch --device "${device_id}" "${bundle_id}"
}

build_device_dev() {
  flutter build ios --profile --no-codesign \
    --target=lib/main.dart \
    --build-number="${build_number}" \
    --dart-define="NIMBUS_API_BASE_URL=${device_api_base_url}"
  xcodebuild \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -configuration Profile \
    -destination "id=${device_id}" \
    -derivedDataPath "${dual_root}/device-dev-derived" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="${team_id}" \
    CODE_SIGN_STYLE=Automatic \
    BASE_BUNDLE_IDENTIFIER=app.yundo.client.dev \
    SERVICE_IDENTIFIER=app.yundo.client.dev.service \
    APP_DISPLAY_NAME="Yundo Dev" \
    FLUTTER_BUILD_NUMBER="${build_number}" \
    -quiet build
  local app_path="${dual_root}/Yundo Dev-iPhone.app"
  ditto "${dual_root}/device-dev-derived/Build/Products/Profile-iphoneos/Runner.app" "${app_path}"
  install_device_app "${app_path}" app.yundo.client.dev
}

build_device_prod() {
  flutter build ios --release --no-codesign \
    --target=lib/main_prod.dart \
    --build-number="${build_number}" \
    --dart-define="NIMBUS_API_BASE_URL=${production_api_base_url}"
  xcodebuild \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -configuration Release \
    -destination "id=${device_id}" \
    -derivedDataPath "${dual_root}/device-prod-derived" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="${team_id}" \
    CODE_SIGN_STYLE=Automatic \
    BASE_BUNDLE_IDENTIFIER=app.yundo.client \
    SERVICE_IDENTIFIER=app.yundo.client.service \
    APP_DISPLAY_NAME=Yundo \
    FLUTTER_BUILD_NUMBER="${build_number}" \
    -quiet build
  local app_path="${dual_root}/Yundo-iPhone.app"
  ditto "${dual_root}/device-prod-derived/Build/Products/Release-iphoneos/Runner.app" "${app_path}"
  install_device_app "${app_path}" app.yundo.client
}

xcrun simctl bootstatus "${simulator_id}" -b
build_simulator_dev
build_simulator_prod
build_device_dev
build_device_prod

echo "iOS 双版本构建、Simulator 安装和 iPhone 安装/启动已完成。归档目录：${dual_root}"
