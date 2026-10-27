#!/usr/bin/env bash
#
# The CD deploy step. Sends $RELEASE_SHA to the forced command on the server
# (server/deploy.sh) and records the release that command reports it replaced,
# as the step output `previous`, for the rollback step to use.
#
# The key is restricted to server/deploy.sh by a forced command in
# authorized_keys, so the whole argument string arrives there as
# SSH_ORIGINAL_COMMAND and is pattern-checked before it reaches git.
#
# Needs DEPLOY_USER, DEPLOY_HOST, RELEASE_SHA and GITHUB_OUTPUT.
set -euo pipefail

log=$(mktemp)
status=0
ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes "$DEPLOY_USER@$DEPLOY_HOST" "$RELEASE_SHA" 2>&1 | tee "$log" || status=$?

# Read even when ssh failed: the server prints the line before it does
# anything that can fail, and a deploy that dies half way is the one a
# rollback is for. The pattern admits only a full sha, so nothing else the
# server prints can reach the step output.
previous=$(sed -n 's/^deploy: previous release \([0-9a-f]\{40\}\)$/\1/p' "$log" | tail -n 1)

if [[ -z $previous ]]; then
  echo "::warning::The server reported no previous release, so a failure of this deploy cannot be rolled back."
elif [[ $previous == "$RELEASE_SHA" ]]; then
  echo "::warning::The server is already on ${RELEASE_SHA}, so a failure of this deploy has nothing earlier to roll back to."
else
  echo "previous=${previous}" >>"$GITHUB_OUTPUT"
fi

exit "$status"
