#!/bin/bash

VOICEFLOW_LOCAL_SIGNING_NAME="VoiceFlow Local Development"

voiceflow_list_signing_identities() {
  security find-identity -v -p codesigning 2>/dev/null || true
}

voiceflow_identity_line_for_pattern() {
  local pattern="$1"
  voiceflow_list_signing_identities | grep "$pattern" | head -1 || true
}

voiceflow_identity_hash_from_line() {
  local line="$1"
  echo "$line" | awk '{print $2}'
}

voiceflow_identity_name_from_line() {
  local line="$1"
  echo "$line" | sed -n 's/.*"\([^"]*\)".*/\1/p'
}

voiceflow_identity_name_for_identity() {
  local identity="$1"
  local line=""

  if [ -z "$identity" ]; then
    return 1
  fi

  if echo "$identity" | grep -Eq '^[A-Fa-f0-9]{40}$'; then
    line=$(voiceflow_list_signing_identities | awk -v hash="$identity" '$2 == hash { print; exit }')
  else
    line=$(voiceflow_list_signing_identities | grep -F "\"$identity\"" | head -1 || true)
  fi

  if [ -n "$line" ]; then
    voiceflow_identity_name_from_line "$line"
    return 0
  fi

  echo "$identity"
}

voiceflow_is_developer_id_identity() {
  local identity="$1"
  local resolved_name=""

  resolved_name="$(voiceflow_identity_name_for_identity "$identity" || true)"
  [[ "$resolved_name" == Developer\ ID\ Application* ]]
}

voiceflow_detect_signing_identity() {
  local explicit_identity="${CODE_SIGN_IDENTITY:-${VOICEFLOW_CODE_SIGN_IDENTITY:-}}"
  local line=""
  local patterns=(
    "Developer ID Application"
    "Apple Development"
    "Mac Developer"
    "$VOICEFLOW_LOCAL_SIGNING_NAME"
  )
  local pattern

  if [ -n "$explicit_identity" ]; then
    echo "$explicit_identity"
    return 0
  fi

  for pattern in "${patterns[@]}"; do
    line=$(voiceflow_identity_line_for_pattern "$pattern")
    if [ -n "$line" ]; then
      voiceflow_identity_hash_from_line "$line"
      return 0
    fi
  done

  return 1
}

voiceflow_detect_signing_identity_name() {
  local explicit_identity="${CODE_SIGN_IDENTITY:-${VOICEFLOW_CODE_SIGN_IDENTITY:-}}"
  local line=""
  local patterns=(
    "Developer ID Application"
    "Apple Development"
    "Mac Developer"
    "$VOICEFLOW_LOCAL_SIGNING_NAME"
  )
  local pattern

  if [ -n "$explicit_identity" ]; then
    echo "$explicit_identity"
    return 0
  fi

  for pattern in "${patterns[@]}"; do
    line=$(voiceflow_identity_line_for_pattern "$pattern")
    if [ -n "$line" ]; then
      voiceflow_identity_name_from_line "$line"
      return 0
    fi
  done

  return 1
}

voiceflow_signature_kind() {
  local app_path="$1"
  local details

  if ! details=$(codesign -dvvv "$app_path" 2>&1); then
    echo "unsigned"
    return 0
  fi

  if echo "$details" | grep -q "Signature=adhoc"; then
    echo "adhoc"
    return 0
  fi

  echo "stable"
}

voiceflow_sign_app_bundle() {
  local app_path="$1"
  local entitlements_path="$2"
  local nested_binary_path="$3"
  local identity="${4:-}"
  local sign_target="${identity:--}"

  if [ -f "$nested_binary_path" ]; then
    if [ "$sign_target" = "-" ]; then
      codesign --force --sign - "$nested_binary_path"
    else
      codesign --force --sign "$sign_target" --options runtime --entitlements "$entitlements_path" "$nested_binary_path"
    fi
  fi

  if [ "$sign_target" = "-" ]; then
    codesign --force --deep --sign - --identifier "com.voiceflow.app" "$app_path"
  else
    codesign --force --deep --sign "$sign_target" --options runtime --entitlements "$entitlements_path" "$app_path"
  fi
}
