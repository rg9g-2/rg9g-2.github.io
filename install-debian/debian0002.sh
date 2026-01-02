#!/bin/bash

# --- CONFIGURATION ---
VM_NAME="Debian 11 Auto-Cloud"
RAM="15G"
CORES="6"
TARGET_DISK_SIZE="76G"

# URLs and Filenames
DEBIAN_URL="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"
BASE_IMAGE="debian-11-base.qcow2"
RUN_IMAGE="debian-11-76G.qcow2"

# --- STEP 1: DOWNLOAD ---
if [ ! -f "$BASE_IMAGE" ]; then
    echo "Base image not found. Downloading official Debian 11 Cloud Image..."
    echo "Source: $DEBIAN_URL"
    wget -O "$BASE_IMAGE" "$DEBIAN_URL"
    if [ $? -ne 0 ]; then
        echo "Error: Download failed."
        exit 1
    fi
    echo "Download complete."
else
    echo "Base image already exists. Skipping download."
fi

# --- STEP 2: PREPARE AND RESIZE DISK ---
if [ ! -f "$RUN_IMAGE" ]; then
    echo "Creating working disk from base image..."
    # Copy the base image so we don't have to download it again if we mess up
    cp "$BASE_IMAGE" "$RUN_IMAGE"
    
    echo "Resizing disk to $TARGET_DISK_SIZE..."
    qemu-img resize "$RUN_IMAGE" "$TARGET_DISK_SIZE"
    echo "Disk resized."
fi

# --- STEP 3: WARNING ABOUT PASSWORD ---
echo "----------------------------------------------------------------"
echo "IMPORTANT: This is a Cloud Image. It has NO DEFAULT PASSWORD."
echo "If you have not set a password using 'virt-customize' or 'cloud-init',"
echo "you may be unable to log in at the prompt."
echo "----------------------------------------------------------------"
read -p "Press Enter to launch QEMU..."

# --- STEP 4: LAUNCH QEMU ---
# We use virtio-scsi here for better disk performance on resized images
qemu-system-x86_64 \
    -name "$VM_NAME" \
    -enable-kvm \
    -m $RAM \
    -smp $CORES \
    -cpu host \
    -drive file="$RUN_IMAGE",format=qcow2,if=virtio \
    -vga virtio \
    -display default \
    -device intel-hda -device hda-duplex \
    -usb -device usb-tablet \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0
