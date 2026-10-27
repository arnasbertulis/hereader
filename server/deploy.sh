#!/usr/bin/env bash
#
# The deploy step, run on the VPS. This is the forced command attached to the
# CD key in the deploy user's authorized_keys:
#
#   command="/home/deploy/hereader/server/deploy.sh",no-agent-forwarding,\
#   no-port-forwarding,no-pty,no-user-rc ssh-ed25519 AAAA... hereader-cd
#
# A forced command means the key cannot be used for anything else, so a leak
# of the private half out of GitHub Actions costs a redeploy of an existing
# commit rather than a shell on the server. The commit to deploy arrives in
# SSH_ORIGINAL_COMMAND and is checked against a sha pattern before it reaches
# git, because everything on that string comes from the client.
set -euo pipefail

# The whole body is a function so bash parses this file before running any of
# it. `git checkout` below rewrites this script, and bash otherwise reads a
# script incrementally — it would resume at a byte offset into new content.
main() {
  local tag=${SSH_ORIGINAL_COMMAND:-}

  if [[ ! $tag =~ ^[0-9a-f]{40}$ ]]; then
    echo "deploy: expected a 40-character commit sha, got '${tag}'" >&2
    exit 64
  fi

  cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

  # Report the release this one replaces, so the CD workflow can redeploy it
  # through this same script if the new one fails its health check. It is
  # printed before anything below can fail, and only when .env holds a full
  # sha: a missing line or `local` means there is nothing to go back to, and
  # the workflow treats silence as "rollback unavailable".
  local previous
  previous=$(sed -n 's/^HEREADER_TAG=//p' .env 2>/dev/null | tail -n 1 | tr -d '\r') || true
  if [[ $previous =~ ^[0-9a-f]{40}$ ]]; then
    echo "deploy: previous release ${previous}"
  fi

  # compose.yaml and the Caddyfile are read from the working tree rather than
  # from an image, so the checkout has to land before compose runs. The
  # application code is not read from here at all — it is inside the images.
  git fetch --quiet --tags origin
  git checkout --quiet --force "$tag"

  # Compose substitutes ${HEREADER_TAG} from .env, so writing it to the file
  # rather than exporting it for this one command means the running release
  # is recorded on the box. Rolling back is deploying an earlier sha through
  # this script, which restores its compose.yaml and Caddyfile as well.
  if grep -q '^HEREADER_TAG=' .env 2>/dev/null; then
    sed -i "s|^HEREADER_TAG=.*|HEREADER_TAG=${tag}|" .env
  else
    echo "HEREADER_TAG=${tag}" >>.env
  fi

  docker compose pull
  docker compose up -d --remove-orphans

  # Untagged layers from previous releases, which accumulate at roughly a JRE
  # and a bundle per deploy on a 40GB disk.
  docker image prune --force
}

main "$@"
