#!/usr/bin/env bash
# claude-diff: PreToolUse hook for Edit|Write
# Saves a snapshot of the file BEFORE Claude modifies it.

set -euo pipefail

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Resolve to absolute path if relative
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$CWD/$FILE_PATH"
fi

# Determine storage directory
STORAGE_DIR="$CWD/.claude-diff"
SNAPSHOTS_DIR="$STORAGE_DIR/snapshots"

# Ensure directories exist
mkdir -p "$SNAPSHOTS_DIR"

# Ensure .gitignore exists
if [ ! -f "$STORAGE_DIR/.gitignore" ]; then
  echo "*" > "$STORAGE_DIR/.gitignore"
fi

# Encode the file path: replace / with __ (strip leading /)
RELATIVE_PATH="${FILE_PATH#$CWD/}"
ENCODED_PATH=$(echo "$RELATIVE_PATH" | sed 's|/|__|g')
SNAPSHOT_PATH="$SNAPSHOTS_DIR/$ENCODED_PATH"

# Only save snapshot if we don't already have one (preserve the original)
if [ -f "$SNAPSHOT_PATH" ]; then
  exit 0
fi

if [ -f "$FILE_PATH" ]; then
  # File exists — save a copy as snapshot
  cp "$FILE_PATH" "$SNAPSHOT_PATH"
else
  # File doesn't exist yet (new file) — create a marker
  echo "__CLAUDE_DIFF_NEW_FILE__" > "$SNAPSHOT_PATH"
fi

exit 0
