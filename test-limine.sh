#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/limine-bootloader/limine.git"
ESP="/boot"                 # ESP mount
EFI_DIR="$ESP/EFI/BOOT"
CONF_SRC="$ESP/limine.conf" # your limine.conf
DISK="/dev/sda"             # disk containing ESP
ESP_NUM="2"                 # ESP partition number
LIMINE_LABEL="Limine"

usage() {
  cat <<EOF
Usage: $0 <v9.X.Y-binary> [--no-reboot] | --list
EOF
}

list_tags() {
  echo "Fetching available v9.*-binary tags..."
  git ls-remote --tags "$REPO_URL" 'refs/tags/v9.*-binary' \
    | sed 's#.*/##' | sort -V
}

ensure_paths() {
  if ! mount | grep -q " $ESP "; then
    echo "ERROR: $ESP is not mounted; mount your ESP first." >&2
    exit 1
  fi
  sudo mkdir -p "$EFI_DIR"
  command -v efibootmgr >/dev/null 2>&1 || {
    echo "Installing efibootmgr..."
    sudo pacman -S --needed efibootmgr
  }
}

backup_once() {
  local BACKUP_DIR="${EFI_DIR}.bak"
  if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Backing up current $EFI_DIR → $BACKUP_DIR ..."
    sudo mkdir -p "$BACKUP_DIR"
    if compgen -G "$EFI_DIR/*" >/dev/null; then
      sudo cp -a "$EFI_DIR/." "$BACKUP_DIR/"
    fi
  fi
}

install_tag() {
  local tag="$1"
  local tmpdir="$HOME/limine-$tag"
  rm -rf "$tmpdir"
  echo "Cloning $tag ..."
  git clone "$REPO_URL" --branch "$tag" --depth 1 "$tmpdir"

  local efi_src="$tmpdir/BOOTAA64.EFI"  # binary tags store EFI at repo root
  if [[ ! -f "$efi_src" ]]; then
    echo "ERROR: $efi_src not found. Is '$tag' a *-binary tag?" >&2
    exit 2
  fi

  echo "Installing $efi_src → $EFI_DIR/BOOTAA64.EFI ..."
  sudo install -m 0644 "$efi_src" "$EFI_DIR/BOOTAA64.EFI"

  # Refresh limine.conf beside the loader; only copy to ESP root if it’s a different path.
  if [[ -f "$CONF_SRC" ]]; then
    echo "Refreshing limine.conf beside the loader ..."
    sudo install -m 0644 "$CONF_SRC" "$EFI_DIR/limine.conf"
    if [[ "$CONF_SRC" != "$ESP/limine.conf" ]]; then
      echo "Refreshing limine.conf at ESP root ..."
      sudo install -m 0644 "$CONF_SRC" "$ESP/limine.conf"
    fi
  else
    echo "WARNING: $CONF_SRC not found. Create it before rebooting."
  fi

  echo "Installed $tag ✓"
}

ensure_boot_entry_and_set_bootnext() {
  local entry=""
  entry="$(sudo efibootmgr -v \
    | awk '/^Boot[0-9A-Fa-f]{4}/ && (/Limine/ || /\\\\EFI\\\\BOOT\\\\BOOTAA64.EFI/){gsub("^Boot","",$1);gsub("\\*","",$1);print $1;exit}')"

  if [[ -z "$entry" ]]; then
    echo "No existing Limine boot entry found; creating one..."
    sudo efibootmgr -c -d "$DISK" -p "$ESP_NUM" -L "$LIMINE_LABEL" -l '\EFI\BOOT\BOOTAA64.EFI'
    entry="$(sudo efibootmgr -v \
      | awk '/^Boot[0-9A-Fa-f]{4}/ && (/Limine/ || /\\\\EFI\\\\BOOT\\\\BOOTAA64.EFI/){gsub("^Boot","",$1);gsub("\\*","",$1);print $1;exit}')"
  fi

  if [[ -z "$entry" ]]; then
    echo "ERROR: Failed to create/find a Limine boot entry." >&2
    exit 3
  fi

  echo "Setting one-time boot to Boot$entry ..."
  sudo efibootmgr --bootnext "$entry"
}

maybe_reboot() {
  local noreboot="${1:-}"
  if [[ "$noreboot" == "--no-reboot" ]]; then
    echo "Skipping reboot. You can reboot when ready."
  else
    echo "Rebooting now in 3s (Ctrl-C to cancel)..."
    sleep 3
    systemctl reboot
  fi
}

main() {
  if [[ $# -lt 1 ]]; then usage; exit 1; fi
  if [[ "$1" == "--list" ]]; then list_tags; exit 0; fi

  local tag="$1"; shift
  local flag="${1:-}"

  ensure_paths
  backup_once
  install_tag "$tag"
  ensure_boot_entry_and_set_bootnext
  maybe_reboot "$flag"
}

main "$@"
