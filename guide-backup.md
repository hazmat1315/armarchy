# Limine + Btrfs Snapshots on Parallels ARM64

## Prerequisites

- Fresh Arch Linux ARM64 on Parallels Desktop
- Btrfs filesystem with `/root` subvolume

## Step 1: Install Development Tools

```bash
# Install base requirements
sudo pacman -S --needed base-devel git

# Install yay AUR helper
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
# Choose option 1 (jdk-openjdk) when prompted
```

## Step 2: Install Snapshot Tools

```bash
# Install Snapper
sudo pacman -S snapper

# Install limine-mkinitcpio-hook for the btrfs-overlayfs hook (needed for snapshot booting)
yay -S limine-mkinitcpio-hook
# You'll see this prompt
#
# :: There are 3 providers available for java-environment>=17:
# :: Repository extra
#     1) jdk-openjdk 2) jdk17-openjdk 3) jdk21-openjdk
#
# Enter a number (default=1):
#
# Type 1 (jdk-openjdk) when prompted and press enter
#
# Next it'll prompt for Packages to cleanBuild?
#
# ==> Packages to cleanBuild?
# ==> [N]one [A]ll [Ab]ort [I]nstalled [No]tInstalled or (1 2 3, 1-3, ^4)
#
# Choose `N` for None
#
# Next it'll prompt for Diffs to show?
#
# ==> Diffs to show?
# ==> [N]one [A]ll [Ab]ort [I]nstalled [No]tInstalled or (1 2 3, 1-3, ^4)
#
# Choose `N` for None
#
# Next it'll prompt to remove dependencies after install? [y/N]
#
# Choose `N` or just press enter as `N` is the default
#
# Then proceed with the installation
```

## Step 3: Configure Snapper

```bash
# Create Snapper config
sudo snapper -c root create-config /

# Configure settings (Omarchy defaults)
sudo sed -i 's/^TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' /etc/snapper/configs/root
sudo sed -i 's/^NUMBER_LIMIT="50"/NUMBER_LIMIT="5"/' /etc/snapper/configs/root
sudo sed -i 's/^NUMBER_LIMIT_IMPORTANT="10"/NUMBER_LIMIT_IMPORTANT="5"/' /etc/snapper/configs/root
```

## Step 4: Create Custom Sync Script for ARM64

We'll create a custom script since the Java-based tools don't work with ARM64 Limine v9 syntax:

```bash
# Create custom sync script
sudo tee /usr/local/bin/limine-snapshot-sync-arm <<'EOF'
#!/bin/bash

LIMINE_CONF="/boot/limine.conf"
UUID=$(blkid | grep 'TYPE="btrfs"' | grep -oP 'UUID="\K[^"]+' | head -1)

# Remove old snapshot entries (everything after the fallback entry)
sed -i '/^\/Snapshot/,$d' "$LIMINE_CONF"

# Add snapshot entries using simple parsing
snapper -c root list | tail -n +3 | while read -r line; do
    # Extract snapshot number (first field)
    num=$(echo "$line" | awk '{print $1}')

    # Extract description (everything after the last │)
    desc=$(echo "$line" | sed 's/.*│ \([^│]*\) │$/\1/' | xargs)

    if [[ $num != "0" && -n $num && $num =~ ^[0-9]+$ ]]; then
        # Clean description or use default
        [[ -z "$desc" || "$desc" == " " || "$desc" == "-" ]] && desc="System snapshot"

        cat >> "$LIMINE_CONF" <<ENTRY

/Snapshot $num - $desc
    protocol: linux
    path: boot():/Image
    module_path: boot():/initramfs-linux.img
    cmdline: root=UUID=$UUID rw rootfstype=btrfs rootflags=subvol=root/.snapshots/$num/snapshot
ENTRY
    fi
done

# Copy updated config to where Limine looks for it (same directory as EFI file)
cp "$LIMINE_CONF" /boot/EFI/BOOT/limine.conf

echo "Synchronized snapshots to Limine boot menu"
EOF

sudo chmod +x /usr/local/bin/limine-snapshot-sync-arm
```

## Step 5: Create Test Snapshots

```bash
# Create snapshots
sudo snapper -c root create --description "Initial setup"
sudo snapper -c root list

# Note: We'll test the sync script after Limine is installed
```

## Step 6: Install Plymouth and Set Up mkinitcpio Hooks

```bash
# Install Plymouth for boot splash screen
sudo pacman -S plymouth

# Configure hooks with Plymouth and btrfs-overlayfs for snapshot booting
sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<'EOF'
HOOKS=(base udev plymouth keyboard autodetect modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
EOF

# Regenerate initramfs
sudo mkinitcpio -P
# NOTE: When prompted "Would you like to run 'limine-mkinitcpio' now? [Y/n]:", type 'n'
# We use our custom ARM64 sync script instead
```

## 🎯 PARALLELS SNAPSHOT POINT

**Create a Parallels snapshot here!** This allows you to easily test different Limine versions or revert if something goes wrong with the bootloader installation.

## Step 7: Install and Configure Limine

This step combines downloading Limine, creating the configuration, and installing everything:

```bash
# Download Limine 9.5.3 binary directly
cd /tmp
git clone --depth 1 --branch v9.5.3-binary https://github.com/limine-bootloader/limine.git
cd limine

# Verify the EFI file exists (binary tags store EFI at repo root)
ls -la BOOTAA64.EFI

# Create Tokyo Night themed config with working ARM64 syntax
sudo tee /boot/limine.conf <<'EOF'
# /boot/limine.conf (Limine v9 syntax)
timeout: 12
interface_branding: Omarchy Bootloader
interface_branding_color: 2
hash_mismatch_panic: no

term_background: 1a1b26
backdrop: 1a1b26
term_palette: 15161e;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;a9b1d6
term_palette_bright: 414868;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;c0caf5
term_foreground: c0caf5
term_foreground_bright: c0caf5
term_background_bright: 24283b

/Arch Linux ARM (Parallels)
    protocol: linux
    path: boot():/Image
    module_path: boot():/initramfs-linux.img
    cmdline: root=UUID=YOUR_ROOT_UUID_HERE rw rootfstype=btrfs
EOF

# Replace placeholder with actual UUID
ROOT_UUID=$(blkid | grep 'TYPE="btrfs"' | grep -oP 'UUID="\K[^"]+' | head -1)
sudo sed -i "s/YOUR_ROOT_UUID_HERE/$ROOT_UUID/g" /boot/limine.conf

# Ensure ESP is mounted and create EFI directory
ESP="/boot"
EFI_DIR="$ESP/EFI/BOOT"
sudo mkdir -p "$EFI_DIR"

# Create backup directory if it doesn't exist
BACKUP_DIR="${EFI_DIR}.bak"
if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Backing up current $EFI_DIR → $BACKUP_DIR ..."
    sudo mkdir -p "$BACKUP_DIR"
    if compgen -G "$EFI_DIR/*" >/dev/null; then
        sudo cp -a "$EFI_DIR/." "$BACKUP_DIR/"
    fi
fi

# Install Limine bootloader
TMPDIR="/tmp/limine"
echo "Installing $TMPDIR/BOOTAA64.EFI → $EFI_DIR/BOOTAA64.EFI ..."
sudo install -m 0644 "$TMPDIR/BOOTAA64.EFI" "$EFI_DIR/BOOTAA64.EFI"

# Create or find Limine boot entry
DISK="/dev/sda"
ESP_NUM="2"
LIMINE_LABEL="Limine"

# Check if Limine boot entry already exists
ENTRY=$(sudo efibootmgr -v \
  | awk '/^Boot[0-9A-Fa-f]{4}/ && (/Limine/ || /\\\\EFI\\\\BOOT\\\\BOOTAA64.EFI/){gsub("^Boot","",$1);gsub("\\*","",$1);print $1;exit}')

if [[ -z "$ENTRY" ]]; then
    echo "No existing Limine boot entry found; creating one..."
    sudo efibootmgr -c -d "$DISK" -p "$ESP_NUM" -L "$LIMINE_LABEL" -l '\EFI\BOOT\BOOTAA64.EFI'

    # Find the newly created entry
    ENTRY=$(sudo efibootmgr -v \
      | awk '/^Boot[0-9A-Fa-f]{4}/ && (/Limine/ || /\\\\EFI\\\\BOOT\\\\BOOTAA64.EFI/){gsub("^Boot","",$1);gsub("\\*","",$1);print $1;exit}')
else
    echo "Found existing Limine boot entry: Boot$ENTRY"
fi

# Keep GRUB as default for safety (don't change boot order yet)
echo "Limine boot entry ready: Boot$ENTRY"
LIMINE_NUM=$(sudo efibootmgr | grep "Limine" | cut -c5-8)
sudo efibootmgr --bootorder 0005,${LIMINE_NUM},0002,0003,0000,0004

# Test the snapshot sync script
sudo limine-snapshot-sync-arm

# Verify both files are installed and snapshots are synced
ls -la "$EFI_DIR/BOOTAA64.EFI" "$ESP/limine.conf"
echo "Installed Limine ✓"
cat "$ESP/limine.conf"
```

## Test Limine (One-Time Boot)

Before making Limine the default, test it safely with a one-time boot:

```bash
# Get the Limine boot number
LIMINE_NUM=$(sudo efibootmgr | grep "Limine" | cut -c5-8)

# Boot Limine ONLY on the next reboot (keeps GRUB as default)
sudo efibootmgr --bootnext ${LIMINE_NUM}

# Verify it's set for next boot only
```

Now reboot. You should see:

- Limine bootloader with Tokyo Night theme
- "Omarchy Bootloader" branding
- Arch Linux ARM entries
- Snapshot entries

If it doesn't work, the system will automatically boot back to GRUB on subsequent reboots.

## Make Limine Permanent (After Testing)

Once you've verified Limine works correctly:

```bash
# Make Limine the permanent default
LIMINE_NUM=$(sudo efibootmgr | grep "Limine" | cut -c5-8)
sudo efibootmgr --bootorder ${LIMINE_NUM},0005,0002,0003,0000,0004

# Verify Limine is now first
sudo efibootmgr
```

## Automatic Update Snapshots

When using `omarchy-update` or `pacman -Syu`, snapshots will be created automatically and synced to the boot menu via the limine-snapper-sync service.

## Manual Snapshot Creation (optional)

```bash
sudo snapper -c root create --description "Description here"
sudo limine-snapshot-sync-arm
# Snapshots automatically appear in boot menu via the sync script
```

## Troubleshooting

If Limine shows "No volume contained a Limine configuration file":

```bash
# Check that both files exist in the same directory
ls -la /boot/EFI/BOOT/BOOTAA64.EFI /boot/EFI/BOOT/limine.conf
# Both should be present in /boot/EFI/BOOT/

# If BOOTAA64.EFI is missing:
sudo mkdir -p /boot/EFI/BOOT
sudo cp /usr/share/limine/BOOTAA64.EFI /boot/EFI/BOOT/BOOTAA64.EFI

# If limine.conf is missing in EFI directory:
sudo cp /boot/limine.conf /boot/EFI/BOOT/limine.conf

# Verify the boot entry points to the correct path:
sudo efibootmgr -v | grep Limine
# Should show: \EFI\BOOT\BOOTAA64.EFI
```
