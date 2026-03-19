#!/usr/bin/env python3

import json
import os
import subprocess
import sys
import time
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
ROFI_CONFIG = SCRIPT_DIR / "config.rasi"
RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
SELECTION_CACHE = RUNTIME_DIR / "hypr-share-picker-selection.json"
CACHE_TTL_SECONDS = 25
CACHE_REUSE_COUNT = 3


def ensure_hypr_env() -> dict[str, str]:
    env = os.environ.copy()
    if env.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return env

    runtime_dir = Path(env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
    hypr_dir = runtime_dir / "hypr"
    try:
        instances = sorted(
            (path for path in hypr_dir.iterdir() if path.is_dir()),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
    except FileNotFoundError:
        instances = []

    if instances:
        env["HYPRLAND_INSTANCE_SIGNATURE"] = instances[0].name

    return env


def run_checked(cmd: list[str], *, input_text: str | None = None, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        cmd,
        input=input_text,
        text=True,
        capture_output=True,
        env=env,
    )
    if result.returncode != 0:
        message = (result.stderr or result.stdout).strip() or f"command failed: {' '.join(cmd)}"
        raise RuntimeError(message)
    return result.stdout


def hyprctl_json(topic: str) -> list[dict]:
    output = run_checked(["hyprctl", "-j", topic], env=ensure_hypr_env())
    return json.loads(output)


def load_cached_selection() -> str | None:
    try:
        state = json.loads(SELECTION_CACHE.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None

    selection = str(state.get("selection", "")).strip()
    expires_at = state.get("expires_at")
    remaining_reuses = state.get("remaining_reuses")
    if not selection or not isinstance(expires_at, (int, float)) or not isinstance(remaining_reuses, int):
        clear_cached_selection()
        return None
    if time.time() >= expires_at or remaining_reuses <= 0:
        clear_cached_selection()
        return None

    return selection


def save_cached_selection(selection: str) -> None:
    state = {
        "selection": selection,
        "expires_at": time.time() + CACHE_TTL_SECONDS,
        "remaining_reuses": CACHE_REUSE_COUNT,
    }
    try:
        SELECTION_CACHE.write_text(json.dumps(state))
    except OSError:
        pass


def mark_cached_selection_used() -> None:
    try:
        state = json.loads(SELECTION_CACHE.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return

    remaining_reuses = state.get("remaining_reuses")
    if not isinstance(remaining_reuses, int):
        clear_cached_selection()
        return

    remaining_reuses -= 1
    if remaining_reuses <= 0:
        clear_cached_selection()
        return

    state["remaining_reuses"] = remaining_reuses
    try:
        SELECTION_CACHE.write_text(json.dumps(state))
    except OSError:
        pass


def clear_cached_selection() -> None:
    try:
        SELECTION_CACHE.unlink()
    except FileNotFoundError:
        pass
    except OSError:
        pass


def rofi_select(options: list[dict[str, str]], *, prompt: str, message: str = "") -> dict[str, str] | None:
    if not options:
        return None

    cmd = [
        "rofi",
        "-dmenu",
        "-i",
        "-format",
        "i",
        "-no-custom",
        "-no-sort",
        "-no-sidebar-mode",
        "-no-hover-select",
        "-no-click-to-exit",
        "-p",
        prompt,
    ]
    if message:
        cmd += ["-mesg", message]
    if ROFI_CONFIG.exists():
        cmd += ["-config", str(ROFI_CONFIG)]

    input_text = "\n".join(option["label"] for option in options)
    result = subprocess.run(cmd, input=input_text, text=True, capture_output=True)
    if result.returncode != 0:
        return None

    selection = result.stdout.strip()
    if not selection:
        return None

    try:
        return options[int(selection)]
    except (ValueError, IndexError):
        return None


def screen_options() -> list[dict[str, str]]:
    monitors = hyprctl_json("monitors")
    options = []
    for monitor in monitors:
        name = str(monitor.get("name", "")).strip()
        if not name:
            continue
        width = monitor.get("width") or monitor.get("widthPx") or "?"
        height = monitor.get("height") or monitor.get("heightPx") or "?"
        refresh = monitor.get("refreshRate") or monitor.get("refresh") or "?"
        focused = monitor.get("focused") is True
        description = str(monitor.get("description", "")).strip()
        parts = [name, f"{width}x{height}@{refresh}"]
        if description:
            parts.append(description)
        label = "  ".join(parts)
        if focused:
            label = f"[focused] {label}"
        options.append({"label": label, "value": f"screen:{name}"})

    return options


def window_options() -> list[dict[str, str]]:
    raw = os.environ.get("XDPH_WINDOW_SHARING_LIST", "")
    if not raw:
        return []

    options = []
    rolling = raw
    while rolling:
        id_sep = rolling.find("[HC>]")
        class_sep = rolling.find("[HT>]")
        title_sep = rolling.find("[HE>]")
        window_sep = rolling.find("[HA>]")
        if min(id_sep, class_sep, title_sep, window_sep) < 0:
            break

        handle = rolling[:id_sep].strip()
        app_id = rolling[id_sep + 5 : class_sep].strip()
        title = rolling[class_sep + 5 : title_sep].strip()
        rolling = rolling[window_sep + 5 :]

        if not handle:
            continue
        if not app_id:
            app_id = title or handle
        if not title:
            title = app_id

        label = app_id if title == app_id else f"{app_id}: {title}"
        options.append(
            {
                "label": label,
                "value": f"window:{handle}",
                "sort_key": f"{app_id.lower()} {title.lower()} {handle}",
            }
        )

    options.sort(key=lambda option: option["sort_key"])
    for option in options:
        option.pop("sort_key", None)
    return options


def selection_is_still_valid(selection: str) -> bool:
    if selection.startswith("screen:"):
        return any(option["value"] == selection for option in screen_options())

    if selection.startswith("window:"):
        return any(option["value"] == selection for option in window_options())

    if selection.startswith("region:"):
        output_name, _, _ = selection[7:].partition("@")
        return any(option["value"] == f"screen:{output_name}" for option in screen_options())

    return False


def choose_region() -> str | None:
    result = subprocess.run(["slurp", "-f", "%o %x %y %w %h"], text=True, capture_output=True)
    if result.returncode != 0:
        return None

    selection = result.stdout.strip()
    if not selection:
        return None

    parts = selection.split()
    if len(parts) != 5:
        return None

    output_name, x_raw, y_raw, width_raw, height_raw = parts
    monitors = {str(monitor.get("name", "")).strip(): monitor for monitor in hyprctl_json("monitors")}
    monitor = monitors.get(output_name)
    if monitor is None:
        return None

    try:
        rel_x = int(x_raw) - int(monitor.get("x", 0))
        rel_y = int(y_raw) - int(monitor.get("y", 0))
    except ValueError:
        return None

    return f"region:{output_name}@{rel_x},{rel_y},{width_raw},{height_raw}"


def choose_target() -> str | None:
    cached_selection = load_cached_selection()
    if cached_selection and selection_is_still_valid(cached_selection):
        mark_cached_selection_used()
        return cached_selection
    if cached_selection:
        clear_cached_selection()

    kind = rofi_select(
        [
            {"label": "Screen", "value": "screen"},
            {"label": "Window", "value": "window"},
            {"label": "Region", "value": "region"},
        ],
        prompt="share",
        message="Select what to share",
    )
    if kind is None:
        return None

    value = kind["value"]
    if value == "region":
        selection = choose_region()
        if selection is not None:
            save_cached_selection(selection)
        return selection

    if value == "screen":
        selection = rofi_select(screen_options(), prompt="screen", message="Pick a monitor")
        if selection is None:
            return None
        save_cached_selection(selection["value"])
        return selection["value"]

    if value == "window":
        selection = rofi_select(window_options(), prompt="window", message="Pick a window")
        if selection is None:
            return None
        save_cached_selection(selection["value"])
        return selection["value"]

    return None


def main() -> int:
    allow_token = "--allow-token" in sys.argv[1:]

    try:
        selection = choose_target()
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        return 1

    if selection is None:
        return 1

    flags = "r" if allow_token else ""
    sys.stdout.write(f"[SELECTION]{flags}/{selection}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
