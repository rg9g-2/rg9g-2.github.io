#!/bin/bash

# ==============================================================================
#  CENTOS/KVM DEBIAN AUTOMATOR (GUI EDITION)
# ==============================================================================

# --- 1. DETECT QEMU BINARY ON CENTOS ---
# CentOS puts qemu in weird places sometimes. Let's find it.
if command -v qemu-system-x86_64 &> /dev/null; then
    QEMU_BIN="qemu-system-x86_64"
elif command -v /usr/libexec/qemu-kvm &> /dev/null; then
    QEMU_BIN="/usr/libexec/qemu-kvm"
elif command -v qemu-kvm &> /dev/null; then
    QEMU_BIN="qemu-kvm"
else
    zenity --error --text="Could not find qemu-system-x86_64 or qemu-kvm. Please install virtualization packages:\nsudo yum install qemu-kvm"
    exit 1
fi

# --- 2. GUI INPUT FORM ---
# Default values are pre-filled as requested
OUTPUT=$(zenity --forms --title="Debian 11 KVM Launcher" \
	--text="Configure your Virtual Machine" \
	--separator="," \
	--add-entry="VM Name" \
	--add-entry="RAM (e.g. 15G)" \
	--add-entry="CPU Cores" \
	--add-entry="Disk Size (e.g. 76G)" \
	--add-entry="Disk Filename" \
	--add-entry="Download URL" \
    --confirm-overwrite \
	--icon-name="computer" \
    --entry-text "Debian 11 VM" "15G" "6" "76G" "debian11-disk.qcow2" "https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2")

if [ $? -ne 0 ]; then
    echo "Canceled by user."
    exit 0
fi

# Parse the comma-separated output
IFS=, read -r VM_NAME RAM CORES DISK_SIZE DISK_NAME DOWNLOAD_URL <<< "$OUTPUT"

# --- 3. DOWNLOAD IMAGE (With GUI Progress Bar) ---
if [ ! -f "$DISK_NAME" ]; then
    # We rename it to .orig first to keep a backup
    zenity --info --text="Disk not found. Downloading Debian 11 Cloud Image.\nThis may take a moment." --timeout=3

    # Curl with progress bar, piped into Zenity
    # We use sed to parse curl's output into a format zenity accepts
    curl -L "$DOWNLOAD_URL" --progress-bar -o "${DISK_NAME}.orig" 2>&1 | \
    stdbuf -o0 tr '\r' '\n' | \
    sed -u 's/^[#]*\s*//; s/ .*//' | \
    zenity --progress --title="Downloading Debian 11" --text="Downloading from cloud.debian.org..." --auto-close

    if [ $? -ne 0 ]; then
        zenity --error --text="Download canceled or failed."
        exit 1
    fi

    # --- 4. RESIZE DISK ---
    cp "${DISK_NAME}.orig" "$DISK_NAME"
    
    # Run qemu-img resize and capture output
    RESIZE_OUT=$(qemu-img resize "$DISK_NAME" "$DISK_SIZE" 2>&1)
    
    if [ $? -eq 0 ]; then
        zenity --notification --text="Disk resized to $DISK_SIZE successfully."
    else
        zenity --error --text="Error resizing disk:\n$RESIZE_OUT"
        exit 1
    fi
else
    # Disk exists, just notify
    zenity --notification --text="Existing disk found. Launching..."
fi

# --- 5. PASSWORD WARNING ---
zenity --warning --title="IMPORTANT: LOGIN INFO" \
    --text="<b>READ CAREFULLY:</b>\n\nThis is a Cloud Image. It has <b>NO DEFAULT PASSWORD</b>.\n\nWhen the login screen appears, you will be locked out unless you set a password.\n\n<b>HOW TO FIX:</b>\n1. When the GRUB boot menu appears, immediately press 'e'.\n2. Find the line starting with 'linux'.\n3. Add 'rw init=/bin/bash' to the end of that line.\n4. Press Ctrl+x to boot.\n5. Type 'passwd root' to set your password.\n6. Reboot." \
    --width=500

# --- 6. LAUNCH VM ---
$QEMU_BIN \
    -name "$VM_NAME" \
    -enable-kvm \
    -m $RAM \
    -smp $CORES \
    -cpu host \
    -drive file="$DISK_NAME",format=qcow2,if=virtio \
    -vga virtio \
    -display default \
    -device intel-hda -device hda-duplex \
    -usb -device usb-tablet \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 &

exit 0
