#!/usr/bin/env bash

set -euo pipefail

umask 077

source_file="${HOME}/.scp/cli-config.json"
target_dir="${HOME}/.scpconf"
auth_url=""
region=""

usage() {
  cat <<'EOF'
Usage:
  sync-scp-cli-terraform-config.sh [options]

Options:
  --source-file FILE  scp-cli config file (default: ~/.scp/cli-config.json)
  --auth-url URL      Terraform authentication URL override
  --region REGION     Terraform default region override
  --target-dir DIR    Output directory (default: ~/.scpconf)
  -h, --help          Show this help

The script reads the official scp-cli configuration and writes config.json and
credentials.json for the samsungcloudplatformv2 Terraform provider. Secret
values are never printed.
EOF
}

while (($# > 0)); do
  case "$1" in
    --source-file)
      [[ $# -ge 2 ]] || { echo "error: --source-file requires a value" >&2; exit 2; }
      source_file=$2
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

command -v jq >/dev/null 2>&1 || {
  echo "error: jq command not found" >&2
  exit 1
}

[[ -r "$source_file" ]] || {
  echo "error: scp-cli config is not readable: $source_file" >&2
  exit 1
}

jq -e '
  (.access_key | type == "string" and length > 0) and
  (.access_secret_key | type == "string" and length > 0) and
  (.auth_url | type == "string" and length > 0) and
  (.default_scp_region | type == "string" and length > 0)
' "$source_file" >/dev/null || {
  echo "error: scp-cli config requires access_key, access_secret_key, auth_url, and default_scp_region" >&2
  exit 1
}

access_key=$(jq -r '.access_key' "$source_file")
secret_key=$(jq -r '.access_secret_key' "$source_file")

if [[ -z "$auth_url" ]]; then
  auth_url=$(jq -r '.auth_url' "$source_file")
  auth_url=${auth_url%/endpoints}
fi

if [[ -z "$region" ]]; then
  region=$(jq -r '.default_scp_region' "$source_file")
fi

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

echo "Synchronized scp-cli config from $source_file to $target_dir"
echo "Created config.json and credentials.json with mode 0600 (secret values not displayed)."
