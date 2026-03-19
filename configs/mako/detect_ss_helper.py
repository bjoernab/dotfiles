#!/usr/bin/env python3

import json
import hashlib
import os
import struct
import subprocess
import sys
import time
import zlib


MASK_CHAR = "∗"
ICON_CACHE_DIR = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR", "/tmp"),
    "mako-detect-ss-icons",
)


def mode_enabled(mode_name: str) -> bool:
    try:
        result = subprocess.run(
            ["makoctl", "mode"],
            check=True,
            capture_output=True,
            text=True,
        )
    except Exception:
        return False
    return mode_name in result.stdout.split()


def mask_text(text: str) -> str:
    return "".join(MASK_CHAR if not ch.isspace() else ch for ch in text)


def urgency_name(hints: object) -> str:
    if not isinstance(hints, dict):
        return "normal"

    urgency = hints.get("urgency")
    if not isinstance(urgency, dict):
        return "normal"

    level = urgency.get("data")
    return {0: "low", 1: "normal", 2: "critical"}.get(level, "normal")


def string_hint(hints: object, name: str) -> str:
    if not isinstance(hints, dict):
        return ""

    hint = hints.get(name)
    if not isinstance(hint, dict):
        return ""

    value = hint.get("data")
    if isinstance(value, str):
        return value

    return ""


def bool_hint(hints: object, name: str) -> bool:
    if not isinstance(hints, dict):
        return False

    hint = hints.get(name)
    if not isinstance(hint, dict):
        return False

    return bool(hint.get("data"))


def png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    checksum = zlib.crc32(chunk_type)
    checksum = zlib.crc32(data, checksum)
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", checksum)


def image_data_hint(hints: object) -> tuple[int, int, int, bool, int, int, list[int]] | None:
    if not isinstance(hints, dict):
        return None

    for name in ("image-data", "image_data", "icon_data", "icon-data"):
        hint = hints.get(name)
        if not isinstance(hint, dict) or hint.get("type") != "(iiibiiay)":
            continue

        data = hint.get("data")
        if not isinstance(data, list) or len(data) != 7:
            continue

        width, height, rowstride, has_alpha, bits_per_sample, channels, pixels = data
        if not all(isinstance(value, int) for value in (width, height, rowstride, bits_per_sample, channels)):
            continue
        if not isinstance(has_alpha, bool):
            continue
        if not isinstance(pixels, list) or not all(isinstance(value, int) for value in pixels):
            continue

        return width, height, rowstride, has_alpha, bits_per_sample, channels, pixels

    return None


def image_data_to_png_path(hints: object) -> str:
    image_data = image_data_hint(hints)
    if image_data is None:
        return ""

    width, height, rowstride, has_alpha, bits_per_sample, channels, pixels = image_data
    if width <= 0 or height <= 0 or bits_per_sample != 8 or channels not in {3, 4}:
        return ""

    bytes_per_pixel = channels
    pixel_bytes = bytes(value & 0xFF for value in pixels)
    expected_length = rowstride * height
    if rowstride < width * bytes_per_pixel or len(pixel_bytes) < expected_length:
        return ""

    rows: list[bytes] = []
    row_width = width * bytes_per_pixel
    for row_index in range(height):
        offset = row_index * rowstride
        row = pixel_bytes[offset : offset + row_width]
        if len(row) != row_width:
            return ""
        rows.append(b"\x00" + row)

    color_type = 6 if has_alpha or channels == 4 else 2
    ihdr = struct.pack(">IIBBBBB", width, height, bits_per_sample, color_type, 0, 0, 0)
    raw_image = b"".join(rows)
    png_data = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(raw_image))
        + png_chunk(b"IEND", b"")
    )

    digest = hashlib.sha256()
    digest.update(struct.pack(">IIII?", width, height, rowstride, channels, has_alpha))
    digest.update(pixel_bytes)

    os.makedirs(ICON_CACHE_DIR, exist_ok=True)
    icon_path = os.path.join(ICON_CACHE_DIR, f"{digest.hexdigest()}.png")
    if not os.path.exists(icon_path):
        with open(icon_path, "wb") as icon_file:
            icon_file.write(png_data)

    return icon_path


def find_original_notification_id(app_name: str, summary: str) -> int | None:
    deadline = time.monotonic() + 0.4

    while time.monotonic() < deadline:
        try:
            result = subprocess.run(
                ["makoctl", "list"],
                check=True,
                capture_output=True,
                text=True,
            )
        except Exception:
            return None

        notification_id = None
        current_id = None
        current_summary = None

        for line in result.stdout.splitlines():
            if line.startswith("Notification "):
                header, _, title = line.partition(":")
                try:
                    current_id = int(header.removeprefix("Notification ").strip())
                except ValueError:
                    current_id = None
                current_summary = title.strip()
                continue

            if line.startswith("  App name: ") and current_id is not None:
                current_app_name = line.removeprefix("  App name: ").strip()
                if current_app_name == app_name and current_summary == summary:
                    notification_id = current_id

        if notification_id is not None:
            return notification_id

        time.sleep(0.03)

    return None


def watch_notifications(mask_app_name: str, mode_name: str) -> int:
    for raw_line in sys.stdin:
        raw_line = raw_line.strip()
        if not raw_line:
            continue

        try:
            payload = json.loads(raw_line)["payload"]["data"]
        except Exception:
            continue

        if len(payload) < 8:
            continue

        app_name = payload[0]
        app_icon = payload[2]
        summary = payload[3]
        body = payload[4]
        hints = payload[6]
        timeout = payload[7]

        if app_name == mask_app_name or not mode_enabled(mode_name):
            continue

        has_body = isinstance(body, str) and bool(body.strip())
        masked_summary = summary if has_body else mask_text(summary)
        masked_body = mask_text(body)

        if not masked_summary and not masked_body:
            continue

        original_id = find_original_notification_id(app_name, summary)
        cmd = [
            "notify-send",
            "-a",
            mask_app_name,
            "-u",
            urgency_name(hints),
        ]

        if original_id is not None:
            cmd.extend(["-r", str(original_id)])

        image_path = (
            string_hint(hints, "image-path")
            or string_hint(hints, "image_path")
            or image_data_to_png_path(hints)
        )
        desktop_entry = string_hint(hints, "desktop-entry")
        app_icon_name = app_icon if isinstance(app_icon, str) else ""
        icon = image_path or app_icon_name or desktop_entry
        if icon:
            cmd.extend(["-i", icon])

        if app_icon_name:
            cmd.extend(["-n", app_icon_name])

        if image_path:
            cmd.extend(["-h", f"string:image-path:{image_path}"])

        if desktop_entry:
            cmd.extend(["-h", f"string:desktop-entry:{desktop_entry}"])

        category = string_hint(hints, "category")
        if category:
            cmd.extend(["-c", category])

        if bool_hint(hints, "transient"):
            cmd.append("-e")

        if isinstance(timeout, int) and timeout >= 0:
            cmd.extend(["-t", str(timeout)])

        cmd.append(masked_summary or " ")

        if masked_body:
            cmd.append(masked_body)

        subprocess.run(cmd, check=False)

    return 0


def watch_portal_events() -> int:
    for raw_line in sys.stdin:
        raw_line = raw_line.strip()
        if not raw_line:
            continue

        try:
            message = json.loads(raw_line)
        except Exception:
            continue

        interface = message.get("interface")
        member = message.get("member")
        path = message.get("path")

        if member == "Start" and interface in {
            "org.freedesktop.portal.ScreenCast",
            "org.freedesktop.portal.RemoteDesktop",
        }:
            payload = message.get("payload", {}).get("data", [])
            if payload and isinstance(payload[0], str):
                print(f"start\t{payload[0]}", flush=True)
        elif member == "Closed" and interface == "org.freedesktop.portal.Session" and path:
            print(f"closed\t{path}", flush=True)

    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: detect_ss_helper.py <notifications|portal> [...]", file=sys.stderr)
        return 1

    mode = sys.argv[1]
    if mode == "notifications":
        if len(sys.argv) != 4:
            print(
                "usage: detect_ss_helper.py notifications <mask-app-name> <mode-name>",
                file=sys.stderr,
            )
            return 1
        return watch_notifications(sys.argv[2], sys.argv[3])

    if mode == "portal":
        return watch_portal_events()

    print(f"unknown mode: {mode}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
