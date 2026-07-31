#!/bin/bash
# SessionStart: warn when the agents installed into agy differ from the ones this plugin ships.
#
# The system prompts live in agy, not in this plugin, so a plugin upgrade does not carry them
# along — and `agy --agent` never reports a stale agent. Without this check, running an
# outdated prompt looks exactly like running the current one.
#
# No jq: the gemini plugin advertises no dependencies beyond agy itself.

set -uo pipefail

shipped_manifest="${CLAUDE_PLUGIN_ROOT:-}/agy/plugin.json"
installed_manifest="${GEMINI_CONFIG_DIR:-$HOME/.gemini}/config/plugins/gemini-agents/plugin.json"

# Missing either side is not worth a warning. The installed manifest is absent both when the
# agents were never installed and when agy keeps its config somewhere this script does not know
# about — and a never-installed agent already announces itself, as review output with no
# `## Verdict:` heading. A wrong guess here would fire on every single session, which teaches
# people to ignore the message we actually need them to read.
[ -f "$installed_manifest" ] || exit 0
[ -f "$shipped_manifest" ] || exit 0

read_version() {
  grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$1" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true
}

shipped=$(read_version "$shipped_manifest")
installed=$(read_version "$installed_manifest")

[ -n "$shipped" ] && [ -n "$installed" ] || exit 0
[ "$shipped" = "$installed" ] && exit 0

printf '[gemini] The review prompts installed in agy are v%s; this plugin ships v%s. Prompts do not travel with a plugin upgrade, and `--agent` will not warn you about the mismatch — run /gemini:setup to reinstall them.\n' "$installed" "$shipped"
