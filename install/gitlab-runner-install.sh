#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Flavio Palacin
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.gitlab.com/runner/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

if [[ ! -t 0 ]] && [[ -z "${var_gitlab_url:-}" || -z "${var_gitlab_runner_token:-}" ]]; then
  msg_error "No interactive terminal available (script piped into bash?)."
  msg_error "Launch it with: bash -c \"\$(curl -fsSL <url>/ct/gitlab-runner.sh)\""
  msg_error "or set var_gitlab_url and var_gitlab_runner_token for an unattended install."
  exit 1
fi

if [[ -z "${var_gitlab_url:-}" ]]; then
  read -r -p "${TAB3}GitLab instance URL (e.g. https://gitlab.com): " var_gitlab_url || true
  var_gitlab_url="${var_gitlab_url:-https://gitlab.com}"
fi

if [[ -z "${var_gitlab_runner_token:-}" ]]; then
  read -r -s -p "${TAB3}GitLab Runner authentication token (glrt-...): " var_gitlab_runner_token || true
  echo
fi

if [[ -z "${var_gitlab_runner_token:-}" ]]; then
  msg_error "No runner authentication token provided. Cannot continue."
  exit 1
fi

DEFAULT_RUNNER_IMAGE="alpine:latest"
if [[ -z "${var_gitlab_runner_image:-}" ]]; then
  read -r -p "${TAB3}Default Docker image for jobs (leave blank for ${DEFAULT_RUNNER_IMAGE}): " var_gitlab_runner_image || true
fi
RUNNER_IMAGE="${var_gitlab_runner_image:-$DEFAULT_RUNNER_IMAGE}"
RUNNER_CONCURRENT="${var_gitlab_runner_concurrent:-2}"

msg_info "Installing Dependencies"
$STD apt install -y \
  git \
  docker.io
systemctl enable -q --now docker
msg_ok "Installed Dependencies"

msg_info "Installing GitLab Runner"
RUNNER_VERSION=$(curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fgitlab-runner/releases/permalink/latest" | grep -oP '"tag_name":\s*"v\K[^"]+')
if [[ -z "${RUNNER_VERSION}" ]]; then
  msg_error "Unable to determine the latest GitLab Runner release."
  exit 1
fi
curl -fsSL "https://s3.dualstack.us-east-1.amazonaws.com/gitlab-runner-downloads/v${RUNNER_VERSION}/binaries/gitlab-runner-linux-$(arch_resolve)" -o /usr/local/bin/gitlab-runner
chmod +x /usr/local/bin/gitlab-runner
echo "${RUNNER_VERSION}" >~/.gitlab-runner_version
useradd --comment 'GitLab Runner' --create-home --shell /bin/bash gitlab-runner
usermod -aG docker gitlab-runner
$STD /usr/local/bin/gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
msg_ok "Installed GitLab Runner v${RUNNER_VERSION}"

msg_info "Registering GitLab Runner"
$STD /usr/local/bin/gitlab-runner register \
  --non-interactive \
  --url "${var_gitlab_url}" \
  --token "${var_gitlab_runner_token}" \
  --executor "docker" \
  --docker-image "${RUNNER_IMAGE}" \
  --docker-pull-policy "if-not-present" \
  --description "$(hostname)"
sed -i "s/^concurrent = .*/concurrent = ${RUNNER_CONCURRENT}/" /etc/gitlab-runner/config.toml
chmod 600 /etc/gitlab-runner/config.toml
msg_ok "Registered GitLab Runner"

msg_info "Starting Services"
systemctl enable -q gitlab-runner
systemctl restart gitlab-runner
msg_ok "Started Services"

motd_ssh
customize
cleanup_lxc
