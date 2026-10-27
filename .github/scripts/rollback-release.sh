#!/usr/bin/env bash
#
# The CD rollback step. Redeploys $PREVIOUS_SHA through the same forced command
# as the deploy, which also restores that release's compose.yaml and
# Caddyfile, then waits on the same health check. It always exits 1: the
# release it was called for failed, and the run has to say so whether or not
# the rollback worked.
#
# One attempt, no retry. A second failure means the cause is not in the
# release, and repeating it against a live server makes that harder to read.
#
# Needs DEPLOY_USER, DEPLOY_HOST, RELEASE_SHA, PREVIOUS_SHA and HEREADER_API.
set -uo pipefail

echo "Rolling back to ${PREVIOUS_SHA}"
if ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes "$DEPLOY_USER@$DEPLOY_HOST" "$PREVIOUS_SHA" &&
  bash "$(dirname "${BASH_SOURCE[0]}")/wait-healthy.sh"; then
  echo "::error::Release ${RELEASE_SHA} failed to deploy or pass its health check; rolled back to ${PREVIOUS_SHA}."
else
  echo "::error::Rollback to ${PREVIOUS_SHA} also failed; the service is down and needs a manual fix."
fi
exit 1
