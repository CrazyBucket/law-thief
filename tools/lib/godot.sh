#!/usr/bin/env bash
set -euo pipefail

resolve_godot() {
  if [[ -n "${GODOT:-}" ]]; then
    if command -v "$GODOT" >/dev/null 2>&1; then
      command -v "$GODOT"
      return 0
    fi
    if [[ -x "$GODOT" ]]; then
      printf '%s\n' "$GODOT"
      return 0
    fi
    echo "GODOT is set but not executable: $GODOT" >&2
    return 127
  fi

  local candidates=(
    godot
    godot4
    Godot_v4.6.3-stable_win64_console.exe
    Godot_v4.6.3-stable_win64.exe
    /opt/homebrew/bin/godot
    /usr/local/bin/godot
    /Applications/Godot.app/Contents/MacOS/Godot
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  cat >&2 <<'EOF'
Could not find Godot.
Set GODOT to the executable path, for example:
  GODOT=/opt/homebrew/bin/godot ./tools/verify changed
  GODOT=Godot_v4.6.3-stable_win64_console.exe ./tools/verify changed
EOF
  return 127
}

godot_host_path() {
  local path="$1"
  if command -v wslpath >/dev/null 2>&1 && [[ "$path" == /* ]]; then
    wslpath -m "$path"
    return 0
  fi
  printf '%s\n' "$path"
}
