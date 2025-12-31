#!/bin/bash

# ==========================================
# CentOS 9 QEMU VM Manager (Display Fixed)
# ==========================================

VM_DIR="$HOME/qemu_vms"
ISO_DIR="$VM_DIR/isos"
DEBIAN_ISO_URL="https://cdimage.debian.org/mirror/cdimage/archive/11.11.0/amd64/iso-cd/debian-11.11.0-amd64-netinst.iso"
DEBIAN_ISO_PATH="$ISO_DIR/debian-11-netinst.iso"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# === STEP 1: FIND QEMU BINARY ===
if [ -f "/usr/libexec/qemu-kvm" ]; then
    QEMU_CMD="/usr/libexec/qemu-kvm"
elif command -v qemu-system-x86_64 &> /dev/null; then
    QEMU_CMD="qemu-system-x86_64"
else
    QEMU_CMD="NONE"
fi

mkdir -p "$VM_DIR"
mkdir -p "$ISO_DIR"

check_dependencies() {
    if [ "$QEMU_CMD" == "NONE" ]; then
        echo -e "${YELLOW}Installing QEMU...${NC}"
        sudo dnf install -y qemu-kvm qemu-img
        if [ -f "/usr/libexec/qemu-kvm" ]; then
            QEMU_CMD="/usr/libexec/qemu-kvm"
        else
            echo -e "${RED}Error: QEMU installed but not found.${NC}"
            exit 1
        fi
    fi
    if ! command -v wget &> /dev/null; then
        sudo dnf install -y wget
    fi
}

create_vm() {
    clear
    echo -e "${YELLOW}--- Create VM ---${NC}"
    read -p "Name (no spaces): " VM_NAME
    if [ -z "$VM_NAME" ]; then return; fi
    
    # Check if VM exists
    if [ -f "$VM_DIR/$VM_NAME.qcow2" ]; then echo "Exists!"; sleep 1; return; fi

    read -p "Size (e.g. 10G): " DISK_SIZE
    qemu-img create -f qcow2 "$VM_DIR/$VM_NAME.qcow2" "$DISK_SIZE"
    
    if [ ! -f "$DEBIAN_ISO_PATH" ]; then
        echo "Downloading Debian ISO..."
        wget -O "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_URL"
    fi
    echo -e "${GREEN}Created.${NC}"; read -p "Press Enter..."
}

run_vm() {
    clear
    echo -e "${YELLOW}--- Run VM ---${NC}"
    ls "$VM_DIR"/*.qcow2 2>/dev/null | xargs -n 1 basename | sed 's/.qcow2//'
    echo ""
    read -p "VM Name: " VM_NAME
    DISK_PATH="$VM_DIR/$VM_NAME.qcow2"
    
    if [ ! -f "$DISK_PATH" ]; then echo "Not found."; sleep 1; return; fi

    read -p "RAM (e.g. 2G): " RAM_SIZE
    read -p "Cores (e.g. 2): " CPU_CORES
    read -p "GUI Window? (y/n) [Say 'n' for terminal]: " USE_GUI
    read -p "Install Mode (ISO)? (y/n): " IS_INSTALL

    CMD="$QEMU_CMD -m $RAM_SIZE -smp $CPU_CORES -drive file=$DISK_PATH,format=qcow2"
    
    if [ -e /dev/kvm ]; then CMD="$CMD -enable-kvm -cpu host"; fi

    if [[ "$IS_INSTALL" == "y" ]]; then
        if [ ! -f "$DEBIAN_ISO_PATH" ]; then
            wget -O "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_URL"
        fi
        CMD="$CMD -cdrom $DEBIAN_ISO_PATH -boot d"
    fi

    if [[ "$USE_GUI" == "y" ]]; then
        CMD="$CMD -vga std"
    else
        # === THE FIX IS HERE ===
        # Use curses to draw the screen in the terminal
        CMD="$CMD -display curses"
        echo -e "${YELLOW}------------------------------------------------${NC}"
        echo -e "${YELLOW}IMPORTANT: When the Debian menu appears:${NC}"
        echo -e "${YELLOW}1. Use Arrow Keys to select 'Install'${NC}"
        echo -e "${RED}2. DO NOT select 'Graphical Install'${NC}"
        echo -e "${YELLOW}------------------------------------------------${NC}"
        sleep 3
    fi

    echo -e "${GREEN}Starting...${NC}"
    eval $CMD
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}QEMU Failed. Code: $?.${NC}"
    else
        echo -e "${GREEN}VM Shutdown.${NC}"
    fi
    read -p "Press Enter..."
}

check_dependencies
while true; do
    clear
    echo "1. Create VM"
    echo "2. Run VM"
    echo "3. Exit"
    read -p "Select: " OPTION
    case $OPTION in
        1) create_vm ;;
        2) run_vm ;;
        3) exit ;;
    esac
done
