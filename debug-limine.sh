#!/bin/bash

echo "========================================"
echo "Limine Bootloader Debug Script"
echo "========================================"
echo

echo "1. System Information:"
echo "----------------------"
uname -a
echo "Architecture: $(uname -m)"
echo "Current boot: $(cat /proc/cmdline 2>/dev/null || echo 'N/A')"
echo

echo "2. EFI Boot Manager Status:"
echo "---------------------------"
if command -v efibootmgr &>/dev/null; then
    sudo efibootmgr -v
else
    echo "efibootmgr not available"
fi
echo

echo "3. Block Device Information:"
echo "----------------------------"
if command -v blkid &>/dev/null; then
    sudo blkid
else
    echo "blkid not available"
fi
echo

echo "4. Mount Information:"
echo "---------------------"
df -h /
echo "Root mount details:"
mount | grep " / "
echo "Boot mount details:"
mount | grep "/boot" || echo "No /boot mount found"
echo

echo "5. Limine Installation Check:"
echo "------------------------------"
echo "Limine binary location:"
which limine 2>/dev/null || echo "limine command not found"
if [ -x /usr/local/bin/limine ]; then
    echo "Found: /usr/local/bin/limine"
    /usr/local/bin/limine --version 2>/dev/null || echo "Version check failed"
fi

echo
echo "Limine files in /usr/share/limine/:"
ls -la /usr/share/limine/ 2>/dev/null || echo "Directory not found"
echo

echo "6. EFI Directory Structure:"
echo "---------------------------"
echo "EFI directories:"
find /boot -type d -name "*EFI*" 2>/dev/null || echo "No EFI directories found"
echo
echo "Limine EFI files:"
find /boot -name "*BOOT*.EFI" -o -name "*limine*" 2>/dev/null || echo "No Limine EFI files found"
echo

echo "7. Limine Configuration Files:"
echo "-------------------------------"
for config in /boot/limine.conf /boot/EFI/limine.conf /boot/EFI/EFI/LIMINE/limine.conf; do
    if [ -f "$config" ]; then
        echo "=== $config ==="
        cat "$config"
        echo
    else
        echo "$config: Not found"
    fi
done

echo "8. Kernel and Initramfs Files:"
echo "------------------------------"
echo "Boot directory contents:"
ls -la /boot/ | grep -E "(Image|vmlinuz|initramfs)"
echo

echo "9. Snapper Configuration:"
echo "-------------------------"
if command -v snapper &>/dev/null; then
    echo "Snapper configs:"
    sudo snapper list-configs 2>/dev/null || echo "No snapper configs found"
    echo
    echo "Root snapshots:"
    sudo snapper -c root list 2>/dev/null || echo "Root config not available"
else
    echo "Snapper not installed"
fi
echo

echo "10. Custom Sync Script:"
echo "-----------------------"
if [ -f /usr/local/bin/limine-snapshot-sync-arm ]; then
    echo "Custom sync script found:"
    ls -la /usr/local/bin/limine-snapshot-sync-arm
    echo
    echo "Script contents:"
    cat /usr/local/bin/limine-snapshot-sync-arm
else
    echo "Custom sync script not found"
fi
echo

echo "11. mkinitcpio Configuration:"
echo "-----------------------------"
echo "Omarchy hooks config:"
if [ -f /etc/mkinitcpio.conf.d/omarchy_hooks.conf ]; then
    cat /etc/mkinitcpio.conf.d/omarchy_hooks.conf
else
    echo "/etc/mkinitcpio.conf.d/omarchy_hooks.conf not found"
fi
echo
echo "Main mkinitcpio config (HOOKS line):"
grep "^HOOKS" /etc/mkinitcpio.conf 2>/dev/null || echo "HOOKS not found in main config"
echo

echo "12. Recent Boot Logs (if available):"
echo "------------------------------------"
if command -v journalctl &>/dev/null; then
    echo "Recent boot messages:"
    sudo journalctl -b -n 50 | grep -i -E "(limine|grub|boot|efi)" || echo "No relevant boot messages"
else
    echo "journalctl not available"
fi
echo

echo "13. EFI Variables (if accessible):"
echo "----------------------------------"
if [ -d /sys/firmware/efi/efivars ]; then
    echo "EFI system detected"
    echo "Boot entries in efivars:"
    ls /sys/firmware/efi/efivars/ | grep "Boot[0-9]" | head -10 || echo "No boot entries found"
else
    echo "Not an EFI system or efivars not accessible"
fi
echo

echo "========================================"
echo "Debug script completed"
echo "========================================"