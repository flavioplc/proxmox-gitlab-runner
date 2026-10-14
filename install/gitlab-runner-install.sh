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

# This script runs under lxc-attach, where stdin is never a terminal: the
# settings are asked on the host by ct/gitlab-runner.sh and arrive as var_*.
if [[ -z "${var_gitlab_url:-}" || -z "${var_gitlab_runner_token:-}" ]]; then
  msg_error "var_gitlab_url and var_gitlab_runner_token were not passed to the container."
  msg_error "Run ct/gitlab-runner.sh on the Proxmox host (it asks for them), or export both variables."
  exit 1
fi

RUNNER_IMAGE="${var_gitlab_runner_image:-alpine:latest}"
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
