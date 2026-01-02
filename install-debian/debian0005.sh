#!/bin/bash

# ==============================================================================
#  CENTOS/KVM DEBIAN LAUNCHER (WHIPTAIL EDITION)
# ==============================================================================

# --- 1. CHECK FOR WHIPTAIL (THE GUI) ---
if ! command -v whiptail &> /dev/null; then
    echo "Error: 'whiptail' is not installed."
    echo "Please run: sudo yum install newt -y"
    exit 1
fi

# --- 2. DETECT QEMU BINARY ---
# CentOS/RHEL/Fedora locations for the hypervisor binary
if command -v qemu-system-x86_64 &> /dev/null; then
    QEMU_BIN="qemu-system-x86_64"
elif command -v /usr/libexec/qemu-kvm &> /dev/null; then
    QEMU_BIN="/usr/libexec/qemu-kvm"
elif command -v qemu-kvm &> /dev/null; then
    QEMU_BIN="qemu-kvm"
else
    whiptail --title "Error" --msgbox "Could not find QEMU/KVM binary.\nPlease install: sudo yum install qemu-kvm" 8 60
    exit 1
fi

# --- 3. GET USER INPUTS (GUI) ---
# We use file descriptors (3>&1 1>&2 2>&3) to capture whiptail output into variables

VM_NAME=$(whiptail --inputbox "Virtual Machine Name:" 8 60 "Debian 11 VM" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then exit; fi # Exit if Cancel hit

RAM=$(whiptail --inputbox "RAM Amount (e.g. 15G):" 8 60 "15G" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then exit; fi

CORES=$(whiptail --inputbox "CPU Cores:" 8 60 "6" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then exit; fi

DISK_SIZE=$(whiptail --inputbox "Disk Size (e.g. 76G):" 8 60 "76G" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then exit; fi

# URL Config
DEBIAN_URL="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"
DISK_NAME="debian11-76G.qcow2"

# --- 4. DOWNLOAD LOGIC ---
if [ ! -f "$DISK_NAME" ]; then
    whiptail --title "Download Required" --yesno "Disk image not found.\n\nDownload Official Debian 11 Cloud Image now?" 10 60
    if [ $? -ne 0 ]; then
        echo "Aborted by user."
        exit 0
    fi

    # clear screen for curl output
    clear
    echo "Downloading Debian 11 Cloud Image..."
    echo "URL: $DEBIAN_URL"
    echo "-----------------------------------------------------"
    
    # Download using curl
    curl -L "$DEBIAN_URL" -o "${DISK_NAME}.base"
    
    if [ $? -ne 0 ]; then
        whiptail --title "Error" --msgbox "Download failed. Check internet connection." 8 60
        exit 1
    fi

    echo "-----------------------------------------------------"
    echo "Resizing image to $DISK_SIZE..."
    
    # Copy base to actual disk name
    cp "${DISK_NAME}.base" "$DISK_NAME"
    
    # Resize
    qemu-img resize "$DISK_NAME" "$DISK_SIZE"
    if [ $? -ne 0 ]; then
        whiptail --title "Error" --msgbox "Failed to resize disk." 8 60
        exit 1
    fi
    
    whiptail --title "Success" --msgbox "Download and Resize complete.\n\nReady to launch." 8 60
fi

# --- 5. PASSWORD WARNING ---
whiptail --title "IMPORTANT: ROOT PASSWORD" --msgbox \
"This is a Cloud Image. It has NO DEFAULT PASSWORD.\n\n
To log in, you must reset the password on boot:\n
1. When the GRUB menu appears, press 'e' immediately.\n
2. Find the line starting with 'linux'.\n
3. Add 'rw init=/bin/bash' to the end of that line.\n
4. Press Ctrl+x to boot.\n
5. Type 'passwd root' to set your password.\n
6. Reboot." 18 70

# --- 6. LAUNCH QEMU ---
clear
echo "Starting $VM_NAME..."
echo "RAM: $RAM | Cores: $CORES | Disk: $DISK_SIZE"
echo "Press Ctrl+A, then X to kill the VM from terminal."

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
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0
