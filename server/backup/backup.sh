#!/usr/bin/env bash
#
# One backup run. Executed inside the db-backup container, which mounts this
# directory read-only and runs the file on a schedule — see compose.yaml.
#
# Connection settings come from the standard PG* environment variables that
# compose sets, so nothing here names a host, a user or a password.
#
#   docker exec hereader-db-backup /opt/backup/backup.sh
#
# is a backup taken now, and is also how this was first verified.
set -euo pipefail

# The body is a function so bash parses the whole file before running any of
# it, the same reason deploy.sh is written this way: a deploy replaces this
# file, and bash otherwise reads a script incrementally.
main() {
  local dir=${BACKUP_DIR:-/backups}
  local keep=${BACKUP_KEEP_DAYS:-14}

  local stamp
  stamp=$(date -u +%Y%m%dT%H%M%SZ)

  local final="${dir}/hereader-${stamp}.dump"
  local partial="${final}.partial"

  mkdir -p "$dir"

  # Custom format rather than plain SQL: it is compressed, pg_restore can
  # load a single table out of it, and it carries a table of contents that
  # can be read back without a database — which is what makes the check
  # below possible at all.
  pg_dump --format=custom --file="$partial"

  # A dump is only worth having if it can be read. Listing the archive's
  # table of contents fails on a truncated or corrupt file, and costs
  # milliseconds on an archive this size. It is not a restore, and it is not
  # claimed to be one: it proves the container is intact, not that the rows
  # inside it are the rows expected.
  pg_restore --list "$partial" >/dev/null

  # The rename is what publishes the file, so a dump interrupted part-way
  # leaves a .partial that nothing will mistake for a backup. Same
  # filesystem, so the rename is atomic.
  mv "$partial" "$final"

  # Pruning happens after a new dump has landed and been checked, never
  # before. The failure mode of the other order is a broken dump path that
  # quietly deletes the last good backups on its way to writing nothing.
  find "$dir" -maxdepth 1 -name 'hereader-*.dump' -mtime "+${keep}" -delete
  find "$dir" -maxdepth 1 -name 'hereader-*.dump.partial' -mtime +1 -delete

  echo "backup: wrote ${final} ($(du -h "$final" | cut -f1))"
}

main "$@"
