#!/bin/bash

# --- CONFIGURATION ---
VM_NAME="Debian 11 VM"
RAM="15G"               # 15 GB RAM
CORES="6"               # 6 CPU Cores
DISK_SIZE="76G"         # 76 GB Disk Size
DISK_NAME="debian11.qcow2"
ISO_FILE="debian-11-amd64-netinst.iso" 

# --- CHECKS ---

# 1. Check if KVM is supported on host
if [ ! -e /dev/kvm ]; then
    echo "Error: KVM is not supported or enabled on this machine."
    exit 1
fi

# 2. Check if the ISO file exists
if [ ! -f "$ISO_FILE" ]; then
    echo "Error: ISO file '$ISO_FILE' not found!"
    echo "Please download Debian 11 and place it in this folder, or update the ISO_FILE variable."
    exit 1
fi

# 3. Create the Hard Disk if it doesn't exist
if [ ! -f "$DISK_NAME" ]; then
    echo "Creating $DISK_SIZE qcow2 hard disk..."
    qemu-img create -f qcow2 "$DISK_NAME" "$DISK_SIZE"
    echo "Disk created."
fi

# --- LAUNCH QEMU ---
echo "Starting $VM_NAME..."
echo "RAM: $RAM | Cores: $CORES | Disk: $DISK_SIZE"
echo "Press Ctrl+Alt+G to release mouse cursor if captured."

qemu-system-x86_64 \
    -name "$VM_NAME" \
    -enable-kvm \
    -m $RAM \
    -smp $CORES \
    -cpu host \
    -drive file="$DISK_NAME",format=qcow2,if=virtio \
    -cdrom "$ISO_FILE" \
    -boot menu=on \
    -vga virtio \
    -display default \
    -device intel-hda -device hda-duplex \
    -usb -device usb-tablet \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0
