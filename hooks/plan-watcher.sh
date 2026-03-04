#!/usr/bin/env bash
# claude-diff: PostToolUse hook for Write
# Detects when Claude writes a plan file to ~/.claude/plans/
# and saves the path to .claude-diff/current-plan for the plugin.

set -euo pipefail

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Only proceed if this is a plan file write
if [[ -z "$FILE_PATH" ]] || [[ ! "$FILE_PATH" =~ \.claude/plans/.*\.md$ ]]; then
  exit 0
fi

if [[ -z "$CWD" ]]; then
  exit 0
fi

STORAGE_DIR="$CWD/.claude-diff"
mkdir -p "$STORAGE_DIR"
echo "$FILE_PATH" > "$STORAGE_DIR/current-plan"

exit 0
