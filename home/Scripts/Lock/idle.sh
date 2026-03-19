#!/usr/bin/env bash

# Idle management for Hyprland using swayidle + hyprlock.

swayidle -w \
  timeout 1800 'hyprlock' \
  before-sleep 'hyprlock'
