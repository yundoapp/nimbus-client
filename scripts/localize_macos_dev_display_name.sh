#!/usr/bin/env bash
set -euo pipefail

case "${CONFIGURATION:-}" in
  Debug|Profile) ;;
  *) exit 0 ;;
esac

resources_dir="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
plist_buddy="/usr/libexec/PlistBuddy"

set_display_name() {
  local locale="$1"
  local display_name="$2"
  local strings_file="${resources_dir}/${locale}.lproj/InfoPlist.strings"

  [[ -f "${strings_file}" ]] || return 0
  "${plist_buddy}" -c "Set :CFBundleDisplayName ${display_name}" "${strings_file}"
  "${plist_buddy}" -c "Set :CFBundleName ${display_name}" "${strings_file}"
}

for locale in zh-Hans zh-CN zh_CN; do
  set_display_name "${locale}" "云渡开发版"
done

for locale in zh-Hant zh-TW zh_TW; do
  set_display_name "${locale}" "雲渡開發版"
done
