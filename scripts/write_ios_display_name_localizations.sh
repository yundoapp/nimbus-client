#!/bin/sh

set -eu

if [ "${CONFIGURATION}" = "Debug" ]; then
  zh_hans_name="云渡开发版"
  zh_hant_name="雲渡開發版"
else
  zh_hans_name="云渡"
  zh_hant_name="雲渡"
fi

resources_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"

write_display_name() {
  locale="$1"
  display_name="$2"
  locale_dir="${resources_dir}/${locale}.lproj"
  strings_file="${locale_dir}/InfoPlist.strings"

  /bin/mkdir -p "${locale_dir}"
  /usr/bin/plutil -create xml1 "${strings_file}"
  /usr/bin/plutil -insert CFBundleDisplayName -string "${display_name}" "${strings_file}"
}

write_display_name "zh-Hans" "${zh_hans_name}"
write_display_name "zh-Hant" "${zh_hant_name}"
