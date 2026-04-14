#!/bin/bash
# Shared clipboard sync installation for VMware/Parallels
# Sets up bidirectional X11 ↔ Wayland clipboard synchronization

# Skip unless running under VMware or Parallels — clipboard sync is only
# needed for those two. Bare-metal installs (and other virt types) don't
# need the deps or the user services. Matches the pattern used by the
# sibling vmware-tools.sh / parallels-tools.sh scripts.
if command -v systemd-detect-virt &>/dev/null; then
  case "$(systemd-detect-virt)" in
    vmware|parallels) ;;
    *) return 0 ;;
  esac
else
  return 0
fi

# Install clipboard dependencies
echo "Installing clipboard dependencies..."
sudo pacman -S --noconfirm --needed xclip clipnotify wl-clipboard wl-clip-persist

# Install clipboard sync scripts
echo "Installing clipboard sync scripts..."
sudo install -m 755 "$OMARCHY_PATH/bin/omarchy-clipboard-wl-to-x11" /usr/local/bin/omarchy-clipboard-wl-to-x11
sudo install -m 755 "$OMARCHY_PATH/bin/omarchy-clipboard-x11-to-wl" /usr/local/bin/omarchy-clipboard-x11-to-wl

# Create clipboard sync services
# Ensure the target directory exists first — on fresh installs where no
# user-level systemd unit has been dropped before, /etc/systemd/user may
# be missing and the tee calls below would fail.
sudo mkdir -p /etc/systemd/user
echo "Creating clipboard sync services..."
sudo tee /etc/systemd/user/omarchy-clipboard-wl-to-x11.service <<'EOF' >/dev/null
[Unit]
Description=Omarchy Wayland → X11 Clipboard Sync
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/omarchy-clipboard-wl-to-x11
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

sudo tee /etc/systemd/user/omarchy-clipboard-x11-to-wl.service <<'EOF' >/dev/null
[Unit]
Description=Omarchy X11 → Wayland Clipboard Sync
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/omarchy-clipboard-x11-to-wl
Restart=always
RestartSec=3

[Install]
WantedBy=graphical-session.target
EOF

# Enable clipboard sync services
sudo systemctl --global enable omarchy-clipboard-wl-to-x11.service
sudo systemctl --global enable omarchy-clipboard-x11-to-wl.service

# Add wl-clip-persist to Hyprland autostart if not already present
AUTOSTART_FILE="$HOME/.config/omarchy/current/config/hypr/autostart.conf"
if [ -f "$AUTOSTART_FILE" ]; then
    if ! grep -q "wl-clip-persist" "$AUTOSTART_FILE"; then
        echo "" >> "$AUTOSTART_FILE"
        echo "# Clipboard persistence for Wayland (added by VM tools)" >> "$AUTOSTART_FILE"
        echo "exec-once = wl-clip-persist --clipboard regular" >> "$AUTOSTART_FILE"
        echo "Added wl-clip-persist to Hyprland autostart"
    fi
fi

echo "Clipboard synchronization configured for Wayland ↔ X11"
