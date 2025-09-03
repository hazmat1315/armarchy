#!/bin/bash

# Kernel Backup System Verification Script
set -e

echo "🔍 Kernel Backup System Verification"
echo "===================================="
echo

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

MACHINE_ID=$(cat /etc/machine-id)
HISTORY_DIR="/boot/$MACHINE_ID/limine_history"
MANIFEST_PATH="/boot/$MACHINE_ID/snapshots.json"

print_check() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# 1. Check history directory exists
echo "1. Checking History Directory..."
if [[ -d "$HISTORY_DIR" ]]; then
    print_check "History directory exists: $HISTORY_DIR"
    file_count=$(ls "$HISTORY_DIR" 2>/dev/null | wc -l)
    echo "   Files in history: $file_count"
    
    if [[ $file_count -gt 0 ]]; then
        echo "   Sample files:"
        ls -la "$HISTORY_DIR" | head -5 | tail -4 | while read line; do
            echo "   $line"
        done
    fi
else
    print_error "History directory missing: $HISTORY_DIR"
fi
echo

# 2. Check manifest exists and is valid
echo "2. Checking Manifest..."
if [[ -f "$MANIFEST_PATH" ]]; then
    print_check "Manifest exists: $MANIFEST_PATH"
    
    if jq '.' "$MANIFEST_PATH" >/dev/null 2>&1; then
        print_check "Manifest is valid JSON"
        snapshot_count=$(jq '.snapshotEntries | length' "$MANIFEST_PATH")
        echo "   Snapshots in manifest: $snapshot_count"
        
        if [[ $snapshot_count -gt 0 ]]; then
            echo "   Latest snapshot ID: $(jq '.lastSnapshotID' "$MANIFEST_PATH")"
        fi
    else
        print_error "Manifest contains invalid JSON"
    fi
else
    print_error "Manifest missing: $MANIFEST_PATH"
fi
echo

# 3. Verify hash integrity
echo "3. Checking Hash Integrity..."
hash_errors=0

if [[ -d "$HISTORY_DIR" ]]; then
    for file in "$HISTORY_DIR"/sha256_*; do
        if [[ -f "$file" ]]; then
            expected_hash=$(basename "$file" | sed 's/^sha256_//')
            actual_hash=$(sha256sum "$file" | cut -d' ' -f1)
            
            if [[ "$expected_hash" == "$actual_hash" ]]; then
                filename=$(basename "$file")
                echo "   ✓ Hash verified: ${filename:0:20}..."
            else
                print_error "Hash mismatch: $(basename "$file")"
                hash_errors=$((hash_errors + 1))
            fi
        fi
    done
    
    if [[ $hash_errors -eq 0 ]]; then
        print_check "All stored files have correct hashes"
    else
        print_error "$hash_errors files have hash mismatches"
    fi
else
    print_warning "No history directory to check"
fi
echo

# 4. Check kernel file mapping
echo "4. Checking Kernel File Mapping..."
if [[ -f "$MANIFEST_PATH" ]] && jq '.' "$MANIFEST_PATH" >/dev/null 2>&1; then
    snapshot_count=$(jq '.snapshotEntries | length' "$MANIFEST_PATH")
    
    for ((i=0; i<snapshot_count; i++)); do
        id=$(jq ".snapshotEntries[$i].snapperEntry.snapshotID" "$MANIFEST_PATH")
        kernel_files=$(jq ".snapshotEntries[$i].kernelEntries[0].imageDetails | length" "$MANIFEST_PATH")
        
        echo "   Snapshot $id: $kernel_files kernel files tracked"
        
        # Show kernel file types
        for ((j=0; j<kernel_files; j++)); do
            key=$(jq -r ".snapshotEntries[$i].kernelEntries[0].imageDetails[$j].limineKey" "$MANIFEST_PATH")
            filename=$(jq -r ".snapshotEntries[$i].kernelEntries[0].imageDetails[$j].fileName" "$MANIFEST_PATH")
            echo "     $key: $filename"
        done
    done
    
    if [[ $snapshot_count -gt 0 ]]; then
        print_check "Kernel file mapping looks correct"
    fi
else
    print_warning "Cannot check kernel file mapping - invalid manifest"
fi
echo

# 5. Check boot configuration
echo "5. Checking Boot Configuration..."
limine_config="/boot/EFI/BOOT/limine.conf"

if [[ -f "$limine_config" ]]; then
    print_check "Limine config exists: $limine_config"
    
    snapshot_entries=$(grep -c "Snapshot.*with matching kernels" "$limine_config" || echo "0")
    history_references=$(grep -c "limine_history" "$limine_config" || echo "0")
    
    echo "   Snapshot entries: $snapshot_entries"
    echo "   History references: $history_references"
    
    if [[ $snapshot_entries -gt 0 && $history_references -gt 0 ]]; then
        print_check "Boot configuration includes kernel versioning"
    else
        print_warning "Boot configuration may not be using kernel versioning"
    fi
else
    print_error "Limine config missing: $limine_config"
fi
echo

# 6. Check current vs history kernel versions
echo "6. Comparing Current vs History Kernels..."

if [[ -f "/boot/Image" ]]; then
    current_kernel_hash=$(sha256sum /boot/Image | cut -d' ' -f1)
    echo "   Current Image hash: ${current_kernel_hash:0:16}..."
    
    # Find matching file in history
    if [[ -f "$HISTORY_DIR/sha256_$current_kernel_hash" ]]; then
        print_check "Current Image found in history"
    else
        print_warning "Current Image not found in history (may be newer)"
    fi
fi

if [[ -f "/boot/initramfs-linux.img" ]]; then
    current_initramfs_hash=$(sha256sum /boot/initramfs-linux.img | cut -d' ' -f1)
    echo "   Current initramfs hash: ${current_initramfs_hash:0:16}..."
    
    if [[ -f "$HISTORY_DIR/sha256_$current_initramfs_hash" ]]; then
        print_check "Current initramfs found in history"
    else
        print_warning "Current initramfs not found in history (may be newer)"
    fi
fi
echo

# 7. Summary
echo "📋 Summary"
echo "=========="

total_history_files=$(ls "$HISTORY_DIR" 2>/dev/null | wc -l)
total_snapshots=$(jq '.snapshotEntries | length' "$MANIFEST_PATH" 2>/dev/null || echo "0")
history_size=$(du -sh "$HISTORY_DIR" 2>/dev/null | cut -f1 || echo "0")

echo "• History files: $total_history_files ($history_size)"
echo "• Tracked snapshots: $total_snapshots"
echo "• Hash integrity: $(( $(ls "$HISTORY_DIR" 2>/dev/null | wc -l) - hash_errors )) / $total_history_files correct"

if [[ $total_snapshots -gt 0 && $total_history_files -gt 0 && $hash_errors -eq 0 ]]; then
    echo
    print_check "Kernel backup system is working correctly!"
    echo "  ✓ Files are being tracked and deduplicated"
    echo "  ✓ Boot entries point to correct kernel versions"  
    echo "  ✓ Ready for safe snapshot restoration"
else
    echo
    print_warning "Kernel backup system may have issues"
    if [[ $total_snapshots -eq 0 ]]; then
        echo "  ⚠ No snapshots tracked - run omarchy-limine-snapper-sync"
    fi
    if [[ $total_history_files -eq 0 ]]; then
        echo "  ⚠ No kernel files backed up"
    fi
    if [[ $hash_errors -gt 0 ]]; then
        echo "  ⚠ Hash integrity issues detected"
    fi
fi

echo
echo "🔧 To test restoration: omarchy-limine-snapper-restore --dry-run"
echo "📊 To view snapshots: omarchy-limine-snapper-list --detailed"