#!/bin/bash
# Memonex Imprints Skill Installer
#
# One command:
#   curl -sL https://raw.githubusercontent.com/Nazbot999/Memonex-Imprints/main/install.sh | bash
#
# Customizable via env vars:
#   OPENCLAW_ROOT=~/.myagent bash install.sh   # non-default root
#   IMPRINTS_HOME=/opt/imprints bash install.sh # explicit SDK location
#
set -e

REPO="https://github.com/Nazbot999/Memonex-Imprints.git"

# --- Detect OpenClaw root ---
detect_openclaw_root() {
  if [ -n "$OPENCLAW_ROOT" ]; then
    echo "$OPENCLAW_ROOT"
    return
  fi
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/openclaw.json" ]; then
      echo "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  echo "$HOME/.openclaw"
}

OPENCLAW_ROOT="$(detect_openclaw_root)"
SDK_DIR="${IMPRINTS_HOME:-$OPENCLAW_ROOT/memonex-imprints}"
SKILL_DIR="$OPENCLAW_ROOT/workspace/skills/imprints"

# Dev-only dirs to remove from a fresh clone (users don't need Foundry artifacts)
DEV_DIRS="contracts test lib out cache cache_forge broadcast"
DEV_FILES="foundry.toml"

echo "=== Memonex Imprints Installer ==="
echo ""
echo "  OPENCLAW_ROOT: $OPENCLAW_ROOT"
echo "  SDK dir:       $SDK_DIR"
echo "  Skill dir:     $SKILL_DIR"
echo ""

# --- Install or update ---
if [ -d "$SDK_DIR/sdk/src" ]; then
  echo "Updating Memonex Imprints SDK..."
  TEMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TEMP_DIR"' EXIT

  git clone --depth 1 --quiet "$REPO" "$TEMP_DIR"

  # Replace code files, preserve user data (.env, node_modules, genesis/)
  rm -rf "$SDK_DIR/sdk/src" "$SDK_DIR/skill"
  cp -r "$TEMP_DIR/sdk/src" "$SDK_DIR/sdk/src"
  cp -r "$TEMP_DIR/skill" "$SDK_DIR/skill"
  cp "$TEMP_DIR/sdk/package.json" "$SDK_DIR/sdk/package.json"
  cp "$TEMP_DIR/sdk/tsconfig.json" "$SDK_DIR/sdk/tsconfig.json"
  cp "$TEMP_DIR/package.json" "$SDK_DIR/package.json"

  rm -rf "$TEMP_DIR"
  trap - EXIT
else
  echo "Downloading Memonex Imprints SDK..."
  mkdir -p "$(dirname "$SDK_DIR")"
  git clone --depth 1 --quiet "$REPO" "$SDK_DIR"

  # Remove dev-only directories and files
  cd "$SDK_DIR"
  for d in $DEV_DIRS; do
    rm -rf "$SDK_DIR/$d"
  done
  for f in $DEV_FILES; do
    rm -f "$SDK_DIR/$f"
  done
  rm -rf "$SDK_DIR/.git"
fi

# --- Install npm dependencies ---
echo "Installing SDK dependencies..."
cd "$SDK_DIR/sdk" && npm install --silent

# --- Install the OpenClaw skill ---
echo "Installing OpenClaw skill..."
mkdir -p "$SKILL_DIR/.clawhub"
cp "$SDK_DIR/skill/SKILL.md" "$SKILL_DIR/SKILL.md"
if [ -f "$SDK_DIR/skill/.clawhub/origin.json" ]; then
  cp "$SDK_DIR/skill/.clawhub/origin.json" "$SKILL_DIR/.clawhub/origin.json"
fi

# --- Persist OPENCLAW_ROOT to sdk/.env so dotenv.config() resolves paths ---
# Scripts run from sdk/ via `cd $IMPRINTS_SDK && npx tsx ...` so .env must be there.
ENV_FILE="$SDK_DIR/sdk/.env"
if [ -f "$ENV_FILE" ]; then
  if ! grep -q '^OPENCLAW_ROOT=' "$ENV_FILE"; then
    echo "" >> "$ENV_FILE"
    echo "OPENCLAW_ROOT=$OPENCLAW_ROOT" >> "$ENV_FILE"
    echo "Appended OPENCLAW_ROOT to existing sdk/.env"
  fi
else
  echo "OPENCLAW_ROOT=$OPENCLAW_ROOT" > "$ENV_FILE"
  echo "Created sdk/.env with OPENCLAW_ROOT"
fi

echo ""
echo "=== Memonex Imprints installed! ==="
echo ""
echo "  SDK:       $SDK_DIR/sdk"
echo "  Skill:     $SKILL_DIR"
echo "  Workspace: $OPENCLAW_ROOT/workspace"
echo ""
echo "Next step: tell your agent /imprints setup"
echo ""
