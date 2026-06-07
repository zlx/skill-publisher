#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# platform_skillhub.sh — SkillHub CN (国内 Skills 社区) adapter
# ============================================================

# @platform_name: skillhub
# @platform_label: SkillHub CN (国内 Skills 社区)
# @auth_method: api_key
# @auth_check: echo $SKILLHUB_TOKEN
# @auth_hint: "请设置环境变量: export SKILLHUB_TOKEN=your_token"
# @upload_type: http_api
# @upload_command: curl POST tarball
# @requires_bin: curl
# @install_hint: "apt install curl / brew install curl"
# @supports_changelog: false
# @supports_version: true

# SkillHub CN API base URL
SKILLHUB_API_BASE="${SKILLHUB_API_BASE:-https://skillhub.cn/api/v1}"

# ----------------------------------------------------------
# platform_skillhub_manifest
# Returns platform manifest as JSON.
# ----------------------------------------------------------
platform_skillhub_manifest() {
  cat <<EOF
{
  "name": "skillhub",
  "label": "SkillHub CN (国内 Skills 社区)",
  "auth_method": "api_key",
  "auth_check": "echo \$SKILLHUB_TOKEN",
  "auth_hint": "请设置环境变量: export SKILLHUB_TOKEN=your_token",
  "upload_type": "http_api",
  "upload_command": "curl POST tarball to $SKILLHUB_API_BASE/skills",
  "requires_bin": "curl",
  "install_hint": "apt install curl / brew install curl",
  "supports_changelog": false,
  "supports_version": true,
  "api_base": "$SKILLHUB_API_BASE"
}
EOF
}

# ----------------------------------------------------------
# platform_skillhub_check_auth
# Checks if SKILLHUB_TOKEN environment variable is set.
# ----------------------------------------------------------
platform_skillhub_check_auth() {
  local token="${SKILLHUB_TOKEN:-}"

  if [[ -z "$token" ]]; then
    cat <<EOF
{
  "module": "platform_skillhub",
  "function": "check_auth",
  "status": "fail",
  "error": "SKILLHUB_TOKEN environment variable not set",
  "hint": "export SKILLHUB_TOKEN=your_token"
}
EOF
    return 1
  fi

  # Verify token by calling a lightweight endpoint
  local verify_output
  if verify_output=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $token" \
    "$SKILLHUB_API_BASE/auth/verify" 2>&1); then
    if [[ "$verify_output" == "200" ]]; then
      cat <<EOF
{
  "module": "platform_skillhub",
  "function": "check_auth",
  "status": "ok",
  "token_set": true
}
EOF
    else
      cat <<EOF
{
  "module": "platform_skillhub",
  "function": "check_auth",
  "status": "fail",
  "error": "Token verification failed (HTTP $verify_output)",
  "hint": "请检查 SKILLHUB_TOKEN 是否有效"
}
EOF
      return 1
    fi
  else
    # If verify endpoint doesn't exist, just confirm token is set
    cat <<EOF
{
  "module": "platform_skillhub",
  "function": "check_auth",
  "status": "ok",
  "token_set": true,
  "warning": "Could not verify token (API endpoint may be unreachable)"
}
EOF
  fi
}

# ----------------------------------------------------------
# platform_skillhub_publish <tarball_path> <skill_path>
# Uploads tarball to SkillHub CN API.
# TODO: Confirm actual API endpoint and request format.
# ----------------------------------------------------------
platform_skillhub_publish() {
  local tarball_path="${1:?Usage: platform_skillhub_publish <tarball> <skill-path>}"
  local skill_path="${2:?Usage: platform_skillhub_publish <tarball> <skill-path>}"
  local token="${SKILLHUB_TOKEN:-}"

  # Validate tarball exists
  if [[ ! -f "$tarball_path" ]]; then
    cat <<EOF
{
  "module": "platform_skillhub",
  "function": "publish",
  "status": "fail",
  "error": "Tarball not found: $tarball_path"
}
EOF
    return 1
  fi

  if [[ -z "$token" ]]; then
    cat <<EOF
{
  "module": "platform_skillhub",
  "function": "publish",
  "status": "fail",
  "error": "SKILLHUB_TOKEN not set"
}
EOF
    return 1
  fi

  # TODO: This endpoint is provisional — needs confirmation from skillhub.cn
  local publish_url="$SKILLHUB_API_BASE/skills"

  local http_code response_body
  response_body=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: Bearer $token" \
    -F "file=@$tarball_path" \
    "$publish_url" 2>&1) || true

  http_code=$(echo "$response_body" | tail -1)
  response_body=$(echo "$response_body" | sed '$d')

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    cat <<EOF
{
  "module": "platform_skillhub",
  "function": "publish",
  "status": "ok",
  "http_code": $http_code,
  "response": "$(echo "$response_body" | head -5 | tr '\n' ' ' | sed 's/"/\\"/g')"
}
EOF
  else
    cat <<EOF
{
  "module": "platform_skillhub",
  "function": "publish",
  "status": "fail",
  "http_code": $http_code,
  "error": "$(echo "$response_body" | head -3 | tr '\n' ' ' | sed 's/"/\\"/g')",
  "note": "API endpoint may be provisional (TODO: confirm with skillhub.cn)"
}
EOF
    return 1
  fi
}

# ----------------------------------------------------------
# platform_skillhub_status <skill-name>
# Queries SkillHub CN for remote version/status.
# TODO: Confirm actual API endpoint.
# ----------------------------------------------------------
platform_skillhub_status() {
  local skill_name="${1:?Usage: platform_skillhub_status <skill-name>}"
  local token="${SKILLHUB_TOKEN:-}"

  local auth_header=""
  if [[ -n "$token" ]]; then
    auth_header="-H \"Authorization: Bearer $token\""
  fi

  # TODO: Provisional endpoint
  local status_url="$SKILLHUB_API_BASE/skills/$skill_name"

  local http_code response_body
  response_body=$(curl -s -w "\n%{http_code}" \
    ${auth_header:+-H "Authorization: Bearer $token"} \
    "$status_url" 2>&1) || true

  http_code=$(echo "$response_body" | tail -1)
  response_body=$(echo "$response_body" | sed '$d')

  if [[ "$http_code" == "200" ]]; then
    cat <<EOF
{
  "module": "platform_skillhub",
  "function": "status",
  "status": "ok",
  "skill_name": "$skill_name",
  "remote_info": "$(echo "$response_body" | head -10 | tr '\n' ' ' | sed 's/"/\\"/g')"
}
EOF
  elif [[ "$http_code" == "404" ]]; then
    cat <<EOF
{
  "module": "platform_skillhub",
  "function": "status",
  "status": "not_found",
  "skill_name": "$skill_name"
}
EOF
  else
    cat <<EOF
{
  "module": "platform_skillhub",
  "function": "status",
  "status": "error",
  "skill_name": "$skill_name",
  "http_code": $http_code,
  "note": "API endpoint may be provisional (TODO: confirm with skillhub.cn)"
}
EOF
    return 1
  fi
}

# ----------------------------------------------------------
# platform_skillhub_post_publish <skill-name> <version>
# ----------------------------------------------------------
platform_skillhub_post_publish() {
  local skill_name="${1:-unknown}"
  local version="${2:-unknown}"

  cat <<EOF
{
  "module": "platform_skillhub",
  "function": "post_publish",
  "status": "ok",
  "message": "Published $skill_name@$version to SkillHub CN",
  "url_hint": "https://skillhub.cn/skills/$skill_name",
  "note": "API endpoint is provisional (TODO: confirm with skillhub.cn)"
}
EOF
}

# ----------------------------------------------------------
# platform_skillhub_help
# ----------------------------------------------------------
platform_skillhub_help() {
  cat <<'EOF'
SkillHub CN — 国内 Skills 社区平台

认证: export SKILLHUB_TOKEN=your_token
API 基础 URL: https://skillhub.cn/api/v1

TODO: 当前端点为临时方案，待 skillhub.cn 确认最终 API 文档。

上传: curl -X POST -H "Authorization: Bearer $TOKEN" -F "file=@skill.tar.gz" \
       https://skillhub.cn/api/v1/skills

查询: curl -H "Authorization: Bearer $TOKEN" \
       https://skillhub.cn/api/v1/skills/<name>
EOF
}

# ----------------------------------------------------------
# Allow direct execution
# ----------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-manifest}"
  shift || true
  case "$cmd" in
    manifest)   platform_skillhub_manifest ;;
    check_auth) platform_skillhub_check_auth ;;
    publish)    platform_skillhub_publish "$@" ;;
    status)     platform_skillhub_status "$@" ;;
    help)       platform_skillhub_help ;;
    *)          echo "Unknown command: $cmd" >&2; exit 1 ;;
  esac
fi
