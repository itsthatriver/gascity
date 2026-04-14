#!/bin/sh
# gc dolt cleanup — Find and remove orphaned Dolt databases.
#
# By default, lists orphaned databases (dry-run). Use --force to remove them.
# Use --max to set a safety limit (refuses if more orphans than --max).
#
# Environment: GC_CITY_PATH
set -e

force=false
max_orphans=50
PACK_DIR="${GC_PACK_DIR:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}"
. "$PACK_DIR/scripts/runtime.sh"
data_dir="$DOLT_DATA_DIR"

while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=true; shift ;;
    --max)   max_orphans="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: gc dolt cleanup [--force] [--max N]"
      echo ""
      echo "Find Dolt databases not referenced by any rig's metadata."
      echo ""
      echo "Flags:"
      echo "  --force    Actually remove orphaned databases"
      echo "  --max N    Refuse if more than N orphans (default: 50)"
      exit 0
      ;;
    *) echo "gc dolt cleanup: unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [ ! -d "$data_dir" ]; then
  echo "No orphaned databases found."
  exit 0
fi

# Collect referenced database names from all rig metadata.json files.
# Use gc rig list to discover rigs at external paths (not just under GC_CITY_PATH).
referenced=""
_collect_db() {
  meta="$1"
  [ -f "$meta" ] || return 0
  db=$(jq -r '.dolt_database // empty' "$meta" 2>/dev/null || true)
  [ -n "$db" ] && referenced="$referenced $db "
}

rig_paths=$(gc rig list --json 2>/dev/null | jq -r '.rigs[].path' 2>/dev/null || true)
if [ -n "$rig_paths" ]; then
  # gc rig list available — iterate all known rigs.
  for rp in $rig_paths; do
    _collect_db "$rp/.beads/metadata.json"
  done
else
  # Fallback: scan city path and rigs/ subdirectory (legacy layout).
  _collect_db "$GC_CITY_PATH/.beads/metadata.json"
  for meta in "$GC_CITY_PATH"/rigs/*/.beads/metadata.json; do
    _collect_db "$meta"
  done
fi

# Find orphans.
orphans=""
orphan_count=0
for d in "$data_dir"/*/; do
  [ ! -d "$d/.dolt" ] && continue
  name="$(basename "$d")"
  case "$name" in information_schema|mysql|dolt_cluster) continue ;; esac
  case "$referenced" in
    *" $name "*) continue ;; # referenced, not orphan
  esac
  # Calculate size (du -sk is POSIX-portable; du -sb is GNU-only).
  size_kb=$(du -sk "$d" 2>/dev/null | cut -f1 || echo 0)
  if [ "$size_kb" -ge 1048576 ]; then
    size=$(awk "BEGIN {printf \"%.1f GB\", $size_kb/1048576}")
  elif [ "$size_kb" -ge 1024 ]; then
    size=$(awk "BEGIN {printf \"%.1f MB\", $size_kb/1024}")
  else
    size="${size_kb} KB"
  fi
  orphans="$orphans$name|$size|$d
"
  orphan_count=$((orphan_count + 1))
done

if [ "$orphan_count" -eq 0 ]; then
  echo "No orphaned databases found."
  exit 0
fi

# Print orphan table.
printf "%-30s  %s\n" "NAME" "SIZE"
echo "$orphans" | while IFS='|' read -r name size path; do
  [ -z "$name" ] && continue
  printf "%-30s  %s\n" "$name" "$size"
done

# Safety limit.
if [ "$orphan_count" -gt "$max_orphans" ]; then
  echo "" >&2
  echo "gc dolt cleanup: $orphan_count orphans exceeds --max $max_orphans; remove manually or increase --max" >&2
  exit 1
fi

if [ "$force" != true ]; then
  echo ""
  echo "$orphan_count orphaned database(s). Use --force to remove."
  exit 0
fi

# Remove each orphan.
removed=0
echo "$orphans" | while IFS='|' read -r name size path; do
  [ -z "$name" ] && continue
  rm -rf "$path"
  echo "  Removed $name"
done

# Count removed (re-check since we're in a subshell).
removed=$(echo "$orphans" | grep -c '|' || true)
echo ""
echo "Removed $removed of $orphan_count orphaned database(s)."
