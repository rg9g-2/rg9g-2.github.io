#!/bin/bash

# ==========================================
# CentOS 9 VM Manager (v7 - Network Fixed)
# ==========================================

# --- Configuration ---
VM_DIR="$HOME/qemu_vms"
IMG_DIR="$VM_DIR/images"
# Debian 12 Bookworm (Stable)
DEBIAN_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
BASE_IMG_PATH="$IMG_DIR/debian-12-base.qcow2"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- QEMU Detection ---
QEMU_CMD="NONE"
if [ -f "/usr/libexec/qemu-kvm" ]; then
    QEMU_CMD="/usr/libexec/qemu-kvm"
elif command -v qemu-system-x86_64 &> /dev/null; then
    QEMU_CMD="qemu-system-x86_64"
fi

mkdir -p "$VM_DIR"
mkdir -p "$IMG_DIR"

function pause() {
    echo ""
    read -p "Press Enter to continue..."
}

# --- 1. Dependencies ---
function check_dependencies() {
    clear
    if ! command -v wget &> /dev/null; then
        sudo dnf install -y wget
    fi

    if [ "$QEMU_CMD" == "NONE" ]; then
        echo -e "${YELLOW}Installing QEMU...${NC}"
        sudo dnf install -y qemu-kvm qemu-img
        if [ -f "/usr/libexec/qemu-kvm" ]; then QEMU_CMD="/usr/libexec/qemu-kvm"; fi
    fi

    if ! command -v virt-customize &> /dev/null; then
        echo -e "${YELLOW}Installing libguestfs-tools (Critical for network config)...${NC}"
        sudo dnf install -y guestfs-tools
    fi
}

# --- 2. Create VM ---
function create_vm() {
    clear
    echo -e "${YELLOW}--- Create New Debian 12 VM --- v2${NC}"
    
    read -p "Enter VM Name: " VM_NAME
    if [ -z "$VM_NAME" ]; then return; fi
    if [ -f "$VM_DIR/$VM_NAME.qcow2" ]; then echo -e "${RED}VM exists. Delete it first.${NC}"; pause; return; fi

    read -p "Disk Size (e.g. 20G): " DISK_SIZE

    # Download
    if [ ! -s "$BASE_IMG_PATH" ]; then
        echo -e "${BLUE}Downloading Debian 12...${NC}"
        wget --no-check-certificate -O "$BASE_IMG_PATH" "$DEBIAN_URL"
        if [ $? -ne 0 ]; then echo -e "${RED}Download failed.${NC}"; rm -f "$BASE_IMG_PATH"; pause; return; fi
    fi

    echo -e "${BLUE}1. Cloning & Resizing...${NC}"
    cp "$BASE_IMG_PATH" "$VM_DIR/$VM_NAME.qcow2"
    qemu-img resize "$VM_DIR/$VM_NAME.qcow2" "$DISK_SIZE" &>/dev/null

    echo -e "${BLUE}2. INJECTING NETWORK FIXES (virt-customize)...${NC}"
    echo -e "${YELLOW}Please wait 30-60 seconds...${NC}"

    # We configure eth0 AND ens3 AND ens4 to ensure one of them hits the QEMU device.
    # We also force standard DNS.
    export LIBGUESTFS_BACKEND=direct
    virt-customize -a "$VM_DIR/$VM_NAME.qcow2" \
        --root-password password:root \
        --uninstall cloud-init \
        --run-command 'echo "auto lo" > /etc/network/interfaces' \
        --run-command 'echo "iface lo inet loopback" >> /etc/network/interfaces' \
        --run-command 'echo "allow-hotplug ens3" >> /etc/network/interfaces' \
        --run-command 'echo "iface ens3 inet dhcp" >> /etc/network/interfaces' \
        --run-command 'echo "allow-hotplug ens4" >> /etc/network/interfaces' \
        --run-command 'echo "iface ens4 inet dhcp" >> /etc/network/interfaces' \
        --run-command 'echo "allow-hotplug eth0" >> /etc/network/interfaces' \
        --run-command 'echo "iface eth0 inet dhcp" >> /etc/network/interfaces' \
        --run-command 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}VM Ready! Login: root / root${NC}"
    else
        echo -e "${RED}Configuration failed.${NC}"
    fi
    pause
}

# --- 3. Run VM ---
function run_vm() {
    clear
    echo -e "${YELLOW}--- Run VM ---${NC}"
    
    ls "$VM_DIR"/*.qcow2 2>/dev/null | grep -v "images" | xargs -n 1 basename | sed 's/.qcow2//'
    echo ""
    read -p "VM Name: " VM_NAME
    DISK_PATH="$VM_DIR/$VM_NAME.qcow2"
    if [ ! -f "$DISK_PATH" ]; then echo "Not found."; pause; return; fi

    read -p "RAM (e.g. 4G): " RAM_SIZE
    read -p "Cores (e.g. 2): " CPU_CORES
    read -p "GUI Window? (y/n): " USE_GUI

    CMD="$QEMU_CMD -m $RAM_SIZE -smp $CPU_CORES -drive file=$DISK_PATH,format=qcow2"
    
    # === NETWORK FIX: Force DNS ===
    # We add dns=8.8.8.8 to the QEMU user network stack
    CMD="$CMD -device virtio-net-pci,netdev=net0 -netdev user,id=net0,dns=8.8.8.8"
    
    if [ -e /dev/kvm ]; then CMD="$CMD -enable-kvm -cpu host"; fi

    if [[ "$USE_GUI" == "y" ]]; then
        echo -e "${GREEN}VNC Started on :0${NC}"
        CMD="$CMD -vnc :0 -vga qxl"
    else
        echo -e "${GREEN}Starting Console...${NC}"
        CMD="$CMD -nographic"
    fi

    echo "Running..."
    eval $CMD
    pause
}

# --- 4. Delete VM ---
function delete_vm() {
    clear
    read -p "VM Name to delete: " VM_NAME
    if [ -f "$VM_DIR/$VM_NAME.qcow2" ]; then
        rm -f "$VM_DIR/$VM_NAME.qcow2"
        echo -e "${GREEN}Deleted.${NC}"
    else
        echo "Not found."
    fi
    pause
}

check_dependencies
while true; do
    clear
    echo -e "${CYAN}=== CentOS 9 VM Manager (Debian 12) ===${NC}"
    echo "1. Create VM (Recreate for Net Fix)"
    echo "2. Run VM"
    echo "3. Delete VM"
    echo "4. Exit"
    read -p "Select: " OPTION
    case $OPTION in
        1) create_vm ;;
        2) run_vm ;;
        3) delete_vm ;;
        4) exit 0 ;;
    esac
done
