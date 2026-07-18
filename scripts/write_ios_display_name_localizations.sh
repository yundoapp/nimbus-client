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
  {
    printf '"CFBundleDisplayName" = "%s";\n' "${display_name}"
    printf '"CFBundleName" = "%s";\n' "${display_name}"
  } | /usr/bin/iconv -f UTF-8 -t UTF-16 >"${strings_file}"
  /usr/bin/plutil -lint "${strings_file}" >/dev/null
}

write_display_name "zh-Hans" "${zh_hans_name}"
write_display_name "zh-Hans-CN" "${zh_hans_name}"
write_display_name "zh_CN" "${zh_hans_name}"
write_display_name "zh-Hant" "${zh_hant_name}"
write_display_name "zh-Hant-TW" "${zh_hant_name}"
write_display_name "zh-Hant-HK" "${zh_hant_name}"
write_display_name "zh-Hant-MO" "${zh_hant_name}"
write_display_name "zh_TW" "${zh_hant_name}"
write_display_name "zh_HK" "${zh_hant_name}"
write_display_name "zh_MO" "${zh_hant_name}"
