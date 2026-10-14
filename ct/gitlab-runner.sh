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

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Check your GitLab instance (Settings > CI/CD > Runners) for the new runner.${CL}"
