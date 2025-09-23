# Omarchy Limine-Snapper

A complete bash implementation of limine-snapper-sync functionality, providing **full EFI/kernel versioning** alongside Btrfs snapshot restoration.

## Overview

This toolset replicates the complete functionality of the Java limine-snapper-sync application in pure bash, including:

- ✅ **Btrfs Snapshot Restoration** - Proper subvolume manipulation and rollback
- ✅ **Kernel Version Tracking** - Hash-based deduplication and history management  
- ✅ **Boot Entry Generation** - Automatic Limine configuration updates
- ✅ **Manifest Management** - JSON-based snapshot-to-kernel mapping
- ✅ **File Deduplication** - Efficient storage using SHA256/Blake3 hashing
- ✅ **Child Subvolume Handling** - Proper `.snapshots`, `var/lib/portables` management

## Components

### Core Scripts

1. **omarchy-limine-snapper-restore** - Restore snapshots with kernel versioning
2. **omarchy-limine-snapper-sync** - Sync Snapper snapshots to Limine boot menu  
3. **omarchy-limine-snapper-list** - Display available snapshots and statistics
4. **omarchy-limine-lib** - Shared library with kernel management functions

### Key Features

**Kernel Versioning System:**
- Scans `/boot/` for kernel files (vmlinuz, initramfs, *.efi)
- Creates hash-based copies in `$ESP/machine-id/limine_history/`
- Tracks which kernel versions belong to each snapshot
- Restores matching kernel files during snapshot rollback

**Manifest Management:**
- JSON manifest at `$ESP/machine-id/snapshots.json`
- Maps snapshot IDs to kernel file hashes
- Tracks boot configuration and metadata
- Automatic pruning and cleanup

**Boot Configuration:**
- Generates Limine boot entries for each snapshot
- Points to correct kernel versions from history
- Updates `limine.conf` automatically
- Supports nested boot entry structures

## Installation

1. **Copy scripts to your system:**
   ```bash
   sudo cp bin/* /usr/local/bin/
   sudo cp etc/default/limine /etc/default/limine
   ```

2. **Install dependencies:**
   ```bash
   # Required
   sudo pacman -S jq btrfs-progs snapper
   
   # Optional (for blake3 hashing)
   sudo pacman -S b3sum
   ```

3. **Configure the system:**
   Edit `/etc/default/limine` with your setup:
   ```bash
   ESP_PATH="/boot"
   MACHINE_ID="$(cat /etc/machine-id)"
   LIMINE_CONFIG_PATH="/boot/limine.conf"
   MAX_SNAPSHOT_ENTRIES=10
   ```

## Usage

### Initial Setup

1. **Sync existing snapshots:**
   ```bash
   sudo omarchy-limine-snapper-sync
   ```

2. **List available snapshots:**
   ```bash
   sudo omarchy-limine-snapper-list
   ```

### Snapshot Restoration

**Interactive restore:**
```bash
sudo omarchy-limine-snapper-restore
```

**Dry-run mode:**
```bash
sudo omarchy-limine-snapper-restore --dry-run
```

**Help:**
```bash
omarchy-limine-snapper-restore --help
```

### Ongoing Management

**Sync new snapshots:**
```bash
sudo omarchy-limine-snapper-sync --max-entries 15
```

**List with details:**
```bash
sudo omarchy-limine-snapper-list --detailed
```

**Show statistics:**
```bash
sudo omarchy-limine-snapper-list --stats
```

## How It Works

### 1. Snapshot Creation & Sync
When you create a Snapper snapshot, run the sync command:

```bash
sudo snapper create -d "Before system update"
sudo omarchy-limine-snapper-sync
```

This will:
1. Scan current kernel files in `/boot/`
2. Create hash-based copies in history directory
3. Add snapshot entry to manifest with kernel mapping
4. Generate Limine boot entry pointing to snapshot + kernels
5. Update `limine.conf` with new boot menu

### 2. Snapshot Restoration
When restoring a snapshot:

```bash
sudo omarchy-limine-snapper-restore
```

The process:
1. **Filesystem Level:**
   - Mount Btrfs root filesystem
   - Create writable snapshot from selected snapshot
   - Backup current @ subvolume 
   - Move restored snapshot to @ location
   - Handle child subvolumes (.snapshots, etc.)

2. **Kernel Level:**
   - Backup current kernel files to manifest
   - Restore matching kernel files from history
   - Update boot configuration
   - Verify file integrity

3. **Cleanup:**
   - Add backup to Snapper list with proper metadata
   - Set backup snapshot as read-only
   - Sync filesystem changes

### 3. File Structure
```
/boot/
├── limine.conf                    # Updated with snapshot entries
├── <machine-id>/
│   ├── snapshots.json            # Manifest with snapshot-kernel mappings
│   └── limine_history/           # Deduplicated kernel files
│       ├── sha256_abc123...      # Hashed kernel files
│       └── sha256_def456...      # Hashed initramfs files
└── vmlinuz-linux                 # Current kernel (replaced during restore)
```

## Advanced Features

### Kernel File Deduplication
- Files stored as `hash_<actual_hash>` in history
- Identical files across snapshots share storage
- Automatic corruption detection and repair
- Support for SHA256, SHA1, and Blake3 hashing

### Manifest Format
JSON structure tracking:
- Snapshot metadata (ID, date, description)
- Kernel file mappings with hashes
- Boot configuration templates
- Machine identification

### Error Handling
- Automatic rollback on restore failure
- Corruption detection for history files
- Missing dependency checks
- Dry-run mode for testing

### Child Subvolume Support
Handles common Btrfs layouts:
- `.snapshots` (Snapper snapshots)
- `var/lib/portables` (systemd portables) 
- `var/lib/machines` (systemd machines)
- Dynamic detection of other child subvolumes

## Configuration Options

See `/etc/default/limine` for full configuration options:

- `ESP_PATH` - EFI System Partition mount point
- `MAX_SNAPSHOT_ENTRIES` - Boot menu entry limit
- `HASH_FUNCTION` - File deduplication algorithm
- `SNAPPER_CONFIG` - Snapper configuration name
- Custom pre/post-save commands

## Comparison with Java Implementation

| Feature | Java limine-snapper-sync | Omarchy (Bash) |
|---------|-------------------------|----------------|
| Btrfs Snapshot Restore | ✅ | ✅ |
| Kernel Version Tracking | ✅ | ✅ |
| File Deduplication | ✅ | ✅ |
| Manifest Management | ✅ | ✅ |
| Boot Entry Generation | ✅ | ✅ |
| Child Subvolume Handling | ✅ | ✅ |
| Corruption Detection | ✅ | ✅ |
| Dependencies | Java + many libs | bash + jq + standard tools |
| Performance | Fast | Fast (comparable) |
| Memory Usage | High (JVM) | Low (native bash) |
| Size | ~2MB JAR + JVM | ~50KB scripts |

## Troubleshooting

### Common Issues

1. **jq not found:**
   ```bash
   sudo pacman -S jq
   ```

2. **Manifest corruption:**
   ```bash
   sudo rm /boot/<machine-id>/snapshots.json
   sudo omarchy-limine-snapper-sync
   ```

3. **Missing kernel files:**
   - Check that `/boot/` contains kernel files before creating snapshots
   - Verify `ESP_PATH` is correctly configured

4. **Boot failures after restore:**
   - Use another snapshot or original system backup
   - Check that initramfs contains required modules
   - Verify root filesystem UUID/LABEL matches

### Debug Mode

Enable verbose output:
```bash
bash -x omarchy-limine-snapper-restore --dry-run
```

## Security Considerations

- Scripts require root access (like original Java app)
- File hashing prevents corruption and tampering
- Backup creation before every restore
- No automatic reboots (manual confirmation required)

## Contributing

This implementation aims for 100% functional compatibility with limine-snapper-sync while providing the benefits of native bash (no JVM dependency, smaller size, easier modification).

The codebase is modular with shared library functions, making it easy to extend or customize for specific needs.

## License

Based on the limine-snapper-sync project architecture and functionality.