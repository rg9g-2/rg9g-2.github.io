#!/bin/bash

# ==============================================================================
#  CENTOS HEADLESS DEBIAN LAUNCHER (TERMINAL EDITION)
# ==============================================================================

VM_NAME="Debian11_Terminal"
RAM="15G"
CORES="6"
DISK_NAME="debian11-76G.qcow2"
DISK_SIZE="76G"
DEBIAN_URL="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"

# --- 1. FIND QEMU ---
if command -v qemu-system-x86_64 &> /dev/null; then
    QEMU_BIN="qemu-system-x86_64"
elif command -v /usr/libexec/qemu-kvm &> /dev/null; then
    QEMU_BIN="/usr/libexec/qemu-kvm"
else
    QEMU_BIN="qemu-kvm"
fi

# --- 2. PREPARE DISK ---
if [ ! -f "$DISK_NAME" ]; then
    echo ">>> Downloading Debian 11 Cloud Image..."
    curl -L "$DEBIAN_URL" -o "${DISK_NAME}.base"
    
    echo ">>> Resizing disk to $DISK_SIZE..."
    cp "${DISK_NAME}.base" "$DISK_NAME"
    qemu-img resize "$DISK_NAME" "$DISK_SIZE"
    
    # --- 3. INJECT PASSWORD (CRITICAL FOR CLOUD IMAGES) ---
    echo ">>> SETTING ROOT PASSWORD..."
    echo "Since you have no GUI, we must set the password from the outside."
    
    if ! command -v virt-customize &> /dev/null; then
        echo "Installing libguestfs-tools to modify disk image..."
        sudo yum install libguestfs-tools -y
    fi

    # Set root password to 'root'
    virt-customize -a "$DISK_NAME" --root-password password:root
    
    echo ">>> PASSWORD SET. User: root | Pass: root"
    sleep 3
fi

# --- 4. LAUNCH IN TERMINAL MODE ---
echo "------------------------------------------------------------"
echo "STARTING VM IN TEXT MODE"
echo "To exit the VM and return to CentOS: Press 'Ctrl+A' then 'x'"
echo "------------------------------------------------------------"
echo "Booting..."
sleep 2

$QEMU_BIN \
    -name "$VM_NAME" \
    -enable-kvm \
    -m $RAM \
    -smp $CORES \
    -cpu host \
    -drive file="$DISK_NAME",format=qcow2,if=virtio \
    -nographic \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0

# Note on -nographic:
# This forces QEMU to use your current terminal as the monitor and serial port.
# Debian Cloud images are configured to output to Serial (ttyS0) by default.
