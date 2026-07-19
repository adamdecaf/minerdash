#!/bin/sh
# Fix bind-mount ownership for SQLite, then drop to the hasherdash user.
# Docker creates host bind-mount dirs as root; the app runs as uid 10001.
set -eu

DATA_DIR="${HASHERDASH_DATA_DIR:-/app/data}"
# Also honor SQLITE_PATH parent when set to a path under a different mount.
SQLITE_PATH="${SQLITE_PATH:-/app/data/hasherdash.db}"

fix_dir() {
  dir="$1"
  [ -n "$dir" ] || return 0
  [ "$dir" = "." ] && return 0
  mkdir -p "$dir"
  if [ "$(id -u)" -eq 0 ]; then
    chown -R hasherdash:hasherdash "$dir" 2>/dev/null || true
    # Ensure the process can create .db / -wal / -shm even if chown of
    # contents failed (e.g. odd mount options); at least the directory itself.
    chown hasherdash:hasherdash "$dir" 2>/dev/null || true
    chmod u+rwx "$dir" 2>/dev/null || true
  fi
}

fix_dir "$DATA_DIR"
case "$SQLITE_PATH" in
  off|OFF|:memory:|"") ;;
  *)
    sqlite_dir=$(dirname "$SQLITE_PATH")
    if [ "$sqlite_dir" != "$DATA_DIR" ]; then
      fix_dir "$sqlite_dir"
    fi
    ;;
esac

if [ "$(id -u)" -eq 0 ]; then
  exec setpriv --reuid=hasherdash --regid=hasherdash --init-groups \
    -- /usr/local/bin/hasherdash "$@"
fi

exec /usr/local/bin/hasherdash "$@"
