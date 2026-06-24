#!/usr/bin/env bash
# Launch Barricade under XWayland to avoid Wayland portal screen-cast dialogs.
# libwebrtc will use X11 desktop capture (silent, no portal prompts).
# media_kit's mpv gets vo=x11 from _x11Vo() in Dart when WAYLAND_DISPLAY is unset.
exec env -u WAYLAND_DISPLAY GDK_BACKEND=x11 \
  "$(dirname "$0")/client/build/linux/x64/debug/bundle/privchat" "$@"
