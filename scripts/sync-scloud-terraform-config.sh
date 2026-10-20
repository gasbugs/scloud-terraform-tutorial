#!/usr/bin/env bash

set -euo pipefail

umask 077

profile="default"
auth_url=""
region=""
target_dir="${HOME}/.scpconf"

usage() {
  cat <<'EOF'
Usage:
  sync-scloud-terraform-config.sh [options]

Options:
  --profile NAME   scloud profile to copy (default: default)
  --auth-url URL   Terraform authentication URL if absent from the profile
  --region REGION  Terraform default region if absent from the profile
  --target-dir DIR Output directory (default: ~/.scpconf)
  -h, --help       Show this help

The script reads `scloud configure list` and writes config.json and
credentials.json for the samsungcloudplatformv2 Terraform provider.
EOF
}

while (($# > 0)); do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { echo "error: --profile requires a value" >&2; exit 2; }
      profile=$2
      shift 2
      ;;
    --auth-url)
      [[ $# -ge 2 ]] || { echo "error: --auth-url requires a value" >&2; exit 2; }
      auth_url=$2
      shift 2
      ;;
    --region)
      [[ $# -ge 2 ]] || { echo "error: --region requires a value" >&2; exit 2; }
      region=$2
      shift 2
      ;;
    --target-dir)
      [[ $# -ge 2 ]] || { echo "error: --target-dir requires a value" >&2; exit 2; }
      target_dir=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v scloud >/dev/null 2>&1 || {
  echo "error: scloud command not found" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || {
  echo "error: jq command not found" >&2
  exit 1
}

profile_data=$(scloud configure list)

profile_value() {
  local key=$1
  awk -v wanted_profile="$profile" -v wanted_key="$key" '
    { sub(/\r$/, "") }
    /^\[[^]]+\]$/ {
      section = substr($0, 2, length($0) - 2)
      next
    }
    section == wanted_profile {
      separator = index($0, "=")
      if (separator == 0) next
      candidate = substr($0, 1, separator - 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", candidate)
      if (candidate == wanted_key) {
        value = substr($0, separator + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  ' <<<"$profile_data"
}

access_key=$(profile_value "access-key")
secret_key=$(profile_value "access-secret")

if [[ -z "$auth_url" ]]; then
  auth_url=$(profile_value "auth-url")
fi

if [[ -z "$region" ]]; then
  region=$(profile_value "default-region")
fi

if [[ -z "$region" ]]; then
  region=$(profile_value "default-region-name")
fi

[[ -n "$access_key" ]] || {
  echo "error: access-key is missing from scloud profile [$profile]" >&2
  exit 1
}

[[ -n "$secret_key" ]] || {
  echo "error: access-secret is missing from scloud profile [$profile]" >&2
  exit 1
}

[[ -n "$auth_url" ]] || {
  echo "error: auth URL is absent; pass the URL for your SCP environment (for example https://iam.e.samsungsdscloud.com/v1 for Enterprise)" >&2
  exit 1
}

[[ -n "$region" ]] || {
  echo "error: default region is absent; pass --region (for example kr-west1)" >&2
  exit 1
}

mkdir -p "$target_dir"
chmod 700 "$target_dir"

timestamp=$(date +%Y%m%d%H%M%S)
for existing_file in "$target_dir/config.json" "$target_dir/credentials.json"; do
  if [[ -f "$existing_file" ]]; then
    cp -p "$existing_file" "${existing_file}.bak.${timestamp}"
    chmod 600 "${existing_file}.bak.${timestamp}"
  fi
done

config_tmp=$(mktemp "$target_dir/.config.json.tmp.XXXXXX")
credentials_tmp=$(mktemp "$target_dir/.credentials.json.tmp.XXXXXX")

cleanup() {
  rm -f "$config_tmp" "$credentials_tmp"
}
trap cleanup EXIT

jq -n \
  --arg auth_url "$auth_url" \
  --arg default_region "$region" \
  '{"auth-url": $auth_url, "default-region": $default_region}' >"$config_tmp"

jq -n \
  --arg access_key "$access_key" \
  --arg secret_key "$secret_key" \
  '{"access-key": $access_key, "secret-key": $secret_key}' >"$credentials_tmp"

chmod 600 "$config_tmp" "$credentials_tmp"
mv -f "$config_tmp" "$target_dir/config.json"
mv -f "$credentials_tmp" "$target_dir/credentials.json"
trap - EXIT

echo "Synchronized scloud profile [$profile] to $target_dir"
echo "Created config.json and credentials.json with mode 0600 (secret values not displayed)."
