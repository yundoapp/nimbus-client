#!/bin/sh

set -eu

resources_root="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

case "${APP_DISPLAY_NAME:-Yundo}" in
  *Dev*)
    simplified_name="云渡开发版"
    traditional_name="雲渡開發版"
    ;;
  *)
    simplified_name="云渡"
    traditional_name="雲渡"
    ;;
esac

write_localized_name() {
  locale="$1"
  display_name="$2"
  locale_dir="${resources_root}/${locale}.lproj"
  strings_file="${locale_dir}/InfoPlist.strings"

  mkdir -p "${locale_dir}"
  rm -f "${strings_file}"
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ${display_name}" "${strings_file}"
  /usr/libexec/PlistBuddy -c "Add :CFBundleName string ${display_name}" "${strings_file}"
}

write_localized_name "zh-Hans" "${simplified_name}"
write_localized_name "zh-Hant" "${traditional_name}"
