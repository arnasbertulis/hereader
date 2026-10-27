#!/usr/bin/env bash
#
# Polls $HEREADER_API/health until it answers, for the deploy step's health
# check and the rollback's. One script serves both so the two cannot drift
# apart on what "healthy" means or how long it is given.
#
# /health reports whether the service can reach Postgres rather than whether
# the process is up, so this fails on a bad migration as well as on a
# container that never started. Compose returns as soon as the containers are
# created, which is before Flyway has finished.
#
# HEALTH_ATTEMPTS and HEALTH_INTERVAL exist so a test can shrink the budget;
# the workflow never sets them, which leaves 30 x 5 s = 150 s.
set -euo pipefail

attempts=${HEALTH_ATTEMPTS:-30}
interval=${HEALTH_INTERVAL:-5}

for attempt in $(seq 1 "$attempts"); do
  if curl --fail --silent --show-error "$HEREADER_API/health"; then
    echo
    echo "healthy after ${attempt} attempt(s)"
    exit 0
  fi
  sleep "$interval"
done
echo "no healthy response in $((attempts * interval))s" >&2
exit 1
