#!/usr/bin/env bash
# claude-diff: PostToolUse hook for Edit|Write
# Registers the modified file in pending.json for review.

set -euo pipefail

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Resolve to absolute path if relative
if [[ "$FILE_PATH" != /* ]]; then
  FILE_PATH="$CWD/$FILE_PATH"
fi

# Track plan file writes (~/.claude/plans/*.md)
if [[ "$FILE_PATH" =~ \.claude/plans/.*\.md$ ]] && [[ -n "$CWD" ]]; then
  mkdir -p "$CWD/.claude-diff"
  echo "$FILE_PATH" > "$CWD/.claude-diff/current-plan"
fi

STORAGE_DIR="$CWD/.claude-diff"
PENDING_FILE="$STORAGE_DIR/pending.json"
SNAPSHOTS_DIR="$STORAGE_DIR/snapshots"

mkdir -p "$SNAPSHOTS_DIR"

RELATIVE_PATH="${FILE_PATH#$CWD/}"
ENCODED_PATH=$(echo "$RELATIVE_PATH" | sed 's|/|__|g')
SNAPSHOT_PATH="$SNAPSHOTS_DIR/$ENCODED_PATH"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Determine if this is a new file
IS_NEW=false
if [ -f "$SNAPSHOT_PATH" ] && grep -q "^__CLAUDE_DIFF_NEW_FILE__$" "$SNAPSHOT_PATH" 2>/dev/null; then
  IS_NEW=true
fi

# Initialize pending.json if it doesn't exist
if [ ! -f "$PENDING_FILE" ]; then
  echo "[]" > "$PENDING_FILE"
fi

# Check if file is already in pending list
EXISTS=$(jq --arg file "$RELATIVE_PATH" '[.[] | select(.file == $file)] | length' "$PENDING_FILE")

if [ "$EXISTS" -gt 0 ]; then
  # Update timestamp
  jq --arg file "$RELATIVE_PATH" \
     --arg ts "$TIMESTAMP" \
     --arg tool "$TOOL_NAME" \
     --arg session "$SESSION_ID" \
     'map(if .file == $file then .timestamp = $ts | .last_tool = $tool | .session_id = $session else . end)' \
     "$PENDING_FILE" > "$PENDING_FILE.tmp" && mv "$PENDING_FILE.tmp" "$PENDING_FILE"
else
  # Add new entry
  jq --arg file "$RELATIVE_PATH" \
     --arg snapshot "$ENCODED_PATH" \
     --arg ts "$TIMESTAMP" \
     --arg tool "$TOOL_NAME" \
     --arg session "$SESSION_ID" \
     --argjson is_new "$IS_NEW" \
     '. += [{"file": $file, "snapshot": $snapshot, "timestamp": $ts, "last_tool": $tool, "session_id": $session, "is_new": $is_new}]' \
     "$PENDING_FILE" > "$PENDING_FILE.tmp" && mv "$PENDING_FILE.tmp" "$PENDING_FILE"
fi

exit 0
