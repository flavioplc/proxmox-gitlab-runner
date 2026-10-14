#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Flavio Palacin
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.gitlab.com/runner/

APP="GitLab-Runner"
var_tags="${var_tags:-ci}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"

export var_gitlab_url="${var_gitlab_url:-}"
export var_gitlab_runner_token="${var_gitlab_runner_token:-}"
export var_gitlab_runner_image="${var_gitlab_runner_image:-}"
export var_gitlab_runner_concurrent="${var_gitlab_runner_concurrent:-}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/gitlab-runner ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  RELEASE=$(curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fgitlab-runner/releases/permalink/latest" | grep -oP '"tag_name":\s*"v\K[^"]+')
  if [[ -z "${RELEASE}" ]]; then
    msg_error "Unable to determine the latest GitLab Runner release."
    exit 1
  fi
  if [[ "${RELEASE}" == "$(cat ~/.gitlab-runner_version 2>/dev/null)" ]]; then
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
    exit
  fi

  msg_info "Stopping Services"
  systemctl stop gitlab-runner
  msg_ok "Stopped Services"

  msg_info "Updating GitLab Runner to v${RELEASE}"
  curl -fsSL "https://s3.dualstack.us-east-1.amazonaws.com/gitlab-runner-downloads/v${RELEASE}/binaries/gitlab-runner-linux-$(arch_resolve)" -o /usr/local/bin/gitlab-runner
  chmod +x /usr/local/bin/gitlab-runner
  echo "${RELEASE}" >~/.gitlab-runner_version
  msg_ok "Updated GitLab Runner"

  msg_info "Starting Services"
  systemctl start gitlab-runner
  msg_ok "Started Services"
  msg_ok "Updated successfully!"
  exit
}

if [[ -n "${mode:-}" ]]; then
  if [[ -z "${var_gitlab_url:-}" ]]; then
    msg_error "var_gitlab_url is required for unattended installs."
    exit 1
  fi
  if [[ -z "${var_gitlab_runner_token:-}" ]]; then
    msg_error "var_gitlab_runner_token is required for unattended installs."
    exit 1
  fi
fi

# The installer runs inside the container under lxc-attach, where stdin is never
# a terminal, so every question is asked here on the host, before the container
# is built. lxc-attach carries the exported var_* values into the container.
function ask_runner_settings() {
  [[ -n "${mode:-}" ]] && return 0 # unattended: required values checked above

  if ! : 2>/dev/null </dev/tty; then
    if [[ -n "${var_gitlab_url:-}" && -n "${var_gitlab_runner_token:-}" ]]; then
      return 0
    fi
    msg_error "No terminal available to ask for the GitLab settings."
    msg_error "Set var_gitlab_url and var_gitlab_runner_token for an unattended install."
    exit 1
  fi

  # A previous lxc-attach/pct call can leave us in a background process group.
  declare -F reclaim_tty >/dev/null && reclaim_tty

  echo
  if [[ -z "${var_gitlab_url:-}" ]]; then
    read -r -p "GitLab instance URL [https://gitlab.com]: " var_gitlab_url </dev/tty || true
    var_gitlab_url="${var_gitlab_url:-https://gitlab.com}"
  fi

  local attempts=0
  while [[ -z "${var_gitlab_runner_token:-}" ]]; do
    attempts=$((attempts + 1))
    if ((attempts > 3)); then
      msg_error "No runner authentication token provided. Cannot continue."
      exit 1
    fi
    read -r -s -p "GitLab Runner authentication token (glrt-...): " var_gitlab_runner_token </dev/tty || true
    echo
  done

  if [[ -z "${var_gitlab_runner_image:-}" ]]; then
    read -r -p "Default Docker image for jobs [alpine:latest]: " var_gitlab_runner_image </dev/tty || true
  fi

  export var_gitlab_url var_gitlab_runner_token var_gitlab_runner_image
}

start
ask_runner_settings
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Check your GitLab instance (Settings > CI/CD > Runners) for the new runner.${CL}"
