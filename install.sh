#!/usr/bin/env bash
# claude-diff: Install hook scripts into ~/.claude/settings.json (global)
#
# Usage:
#   ./install.sh            # Install globally
#   ./install.sh --uninstall # Remove hooks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_DIR="$HOME/.claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required. Install with: brew install jq"
  exit 1
fi

# Uninstall mode
if [ "${1:-}" = "--uninstall" ]; then
  if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Nothing to uninstall."
    exit 0
  fi

  # Remove claude-diff hooks
  CURRENT=$(cat "$SETTINGS_FILE")
  CLEANED=$(echo "$CURRENT" | jq '
    if .hooks then
      .hooks.PreToolUse = [.hooks.PreToolUse[]? | select(.hooks[]?.command | test("claude-diff") | not)] |
      .hooks.PostToolUse = [.hooks.PostToolUse[]? | select(.hooks[]?.command | test("claude-diff") | not)] |
      if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end |
      if (.hooks.PostToolUse | length) == 0 then del(.hooks.PostToolUse) else . end |
      if (.hooks | length) == 0 then del(.hooks) else . end
    else . end
  ')
  echo "$CLEANED" > "$SETTINGS_FILE"
  echo "claude-diff hooks removed from $SETTINGS_FILE"
  exit 0
fi

echo "Installing claude-diff hooks (global)..."
echo "  Plugin dir: $SCRIPT_DIR"

# Ensure ~/.claude directory exists
mkdir -p "$SETTINGS_DIR"

# Create settings.json if it doesn't exist
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "{}" > "$SETTINGS_FILE"
fi

# Build the hooks configuration
PRE_HOOK="$SCRIPT_DIR/hooks/pre-tool-use.sh"
POST_HOOK="$SCRIPT_DIR/hooks/post-tool-use.sh"

# Verify hook scripts exist and are executable
for hook in "$PRE_HOOK" "$POST_HOOK"; do
  if [ ! -f "$hook" ]; then
    echo "ERROR: Hook script not found: $hook"
    exit 1
  fi
  if [ ! -x "$hook" ]; then
    chmod +x "$hook"
    echo "  Made executable: $hook"
  fi
done

# Merge hooks into settings.json
HOOKS_CONFIG=$(cat <<EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$PRE_HOOK"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$POST_HOOK"
          }
        ]
      }
    ]
  }
}
EOF
)

# Merge with existing settings (preserving other keys)
CURRENT=$(cat "$SETTINGS_FILE")
MERGED=$(echo "$CURRENT" | jq --argjson hooks "$HOOKS_CONFIG" '. * $hooks')

echo "$MERGED" > "$SETTINGS_FILE"

echo ""
echo "Hooks installed in: $SETTINGS_FILE"
echo "Active for ALL projects."
echo ""
echo "Now add the plugin to your Neovim config:"
echo ""
echo "  -- lazy.nvim"
echo "  {"
echo "    dir = '$SCRIPT_DIR',"
echo "    config = function()"
echo "      require('claude-diff').setup()"
echo "    end,"
echo "  }"
echo ""
echo "To uninstall: ./install.sh --uninstall"
