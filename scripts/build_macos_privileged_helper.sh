#!/usr/bin/env bash
set -euo pipefail

source_dir="${SRCROOT}/PrivilegedHelper"
helper_name="YundoPrivilegedHelper"
service_name="${PRODUCT_BUNDLE_IDENTIFIER}.privileged-helper"
contents_dir="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}"
helper_dir="${contents_dir}/Library/HelperTools"
daemon_dir="${contents_dir}/Library/LaunchDaemons"
build_dir="${TARGET_TEMP_DIR}/yundo-privileged-helper"
generated_identity="${build_dir}/BuildIdentity.swift"
plist_path="${daemon_dir}/${service_name}.plist"

mkdir -p "$helper_dir" "$daemon_dir" "$build_dir"

cat >"$generated_identity" <<EOF
enum BuildIdentity {
  static let appBundleIdentifier = "${PRODUCT_BUNDLE_IDENTIFIER}"
  static let appExecutableName = "${EXECUTABLE_NAME}"
  static let serviceName = "${service_name}"
}
EOF

architectures=(${ARCHS:-$(uname -m)})
compiled=()
for architecture in "${architectures[@]}"; do
  output="${build_dir}/${helper_name}-${architecture}"
  xcrun --sdk macosx swiftc \
    -parse-as-library \
    -O \
    -target "${architecture}-apple-macos13.0" \
    "${source_dir}/YundoPrivilegedHelper.swift" \
    "$generated_identity" \
    -o "$output"
  compiled+=("$output")
done

helper_path="${helper_dir}/${helper_name}"
if (( ${#compiled[@]} == 1 )); then
  cp "${compiled[0]}" "$helper_path"
else
  lipo -create "${compiled[@]}" -output "$helper_path"
fi
chmod 0755 "$helper_path"

cp "${source_dir}/PrivilegedHelper.plist" "$plist_path"
/usr/libexec/PlistBuddy -c "Set :Label ${service_name}" "$plist_path"
/usr/libexec/PlistBuddy -c "Delete :MachServices" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :MachServices dict" "$plist_path"
/usr/libexec/PlistBuddy -c "Add :MachServices:${service_name} bool true" "$plist_path"
plutil -lint "$plist_path" >/dev/null

identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ -z "$identity" ]]; then
  identity="-"
fi
codesign_args=(--force --sign "$identity" --identifier "$service_name")
if [[ "$identity" != "-" ]]; then
  codesign_args+=(--options runtime --timestamp)
fi
codesign "${codesign_args[@]}" "$helper_path"
