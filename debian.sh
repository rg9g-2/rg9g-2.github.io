#!/bin/bash

# ==========================================
# CentOS 9 QEMU VM Manager (Fixed Error View)
# ==========================================

# Configuration
VM_DIR="$HOME/qemu_vms"
ISO_DIR="$VM_DIR/isos"
DEBIAN_ISO_URL="https://cdimage.debian.org/mirror/cdimage/archive/11.11.0/amd64/iso-cd/debian-11.11.0-amd64-netinst.iso"
DEBIAN_ISO_NAME="debian-11-netinst.iso"
DEBIAN_ISO_PATH="$ISO_DIR/$DEBIAN_ISO_NAME"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

mkdir -p "$VM_DIR"
mkdir -p "$ISO_DIR"

check_dependencies() {
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        echo -e "${YELLOW}Installing QEMU...${NC}"
        sudo dnf install -y qemu-kvm qemu-img
    fi
    if ! command -v wget &> /dev/null; then
        sudo dnf install -y wget
    fi
}

show_host_data() {
    clear
    echo -e "${BLUE}=== HOST SYSTEM DATA ===${NC}"
    echo -e "CPU: $(lscpu | grep 'Model name' | cut -d ':' -f2 | xargs)"
    echo -e "RAM Free: $(free -h | awk '/^Mem:/ {print $4}')"
    echo -e "Disk Avail: $(df -h $HOME | awk 'NR==2 {print $4}')"
    echo -e "${BLUE}========================${NC}"
    echo ""
}

create_vm() {
    echo -e "${YELLOW}--- Create New VM ---${NC}"
    read -p "Enter VM Name (no spaces): " VM_NAME
    
    if [ -z "$VM_NAME" ]; then echo "Name cannot be empty"; sleep 1; return; fi
    if [ -f "$VM_DIR/$VM_NAME.qcow2" ]; then echo "Exists already!"; sleep 2; return; fi

    read -p "Enter Disk Size (e.g. 10G): " DISK_SIZE
    qemu-img create -f qcow2 "$VM_DIR/$VM_NAME.qcow2" "$DISK_SIZE"
    
    # Download ISO if missing
    if [ ! -f "$DEBIAN_ISO_PATH" ]; then
        echo -e "${YELLOW}Downloading Debian 11 ISO...${NC}"
        wget -O "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_URL"
    fi
    
    echo -e "${GREEN}Created. Press Enter.${NC}"
    read temp
}

run_vm() {
    echo -e "${YELLOW}--- Run VM ---${NC}"
    
    # Check if any VMs exist
    count=$(ls "$VM_DIR"/*.qcow2 2>/dev/null | wc -l)
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}No VMs created yet! Go create one first.${NC}"
        read -p "Press Enter..."
        return
    fi

    ls "$VM_DIR"/*.qcow2 | xargs -n 1 basename | sed 's/.qcow2//'
    echo ""
    read -p "Enter VM Name to run: " VM_NAME
    DISK_PATH="$VM_DIR/$VM_NAME.qcow2"
    
    if [ ! -f "$DISK_PATH" ]; then
        echo -e "${RED}File $DISK_PATH not found!${NC}"
        read -p "Press Enter..."
        return
    fi

    read -p "RAM (e.g. 2G): " RAM_SIZE
    read -p "Cores (e.g. 2): " CPU_CORES
    read -p "GUI Window? (y/n): " USE_GUI
    read -p "Boot from ISO (Install mode)? (y/n): " IS_INSTALL

    # Base Command
    CMD="qemu-system-x86_64 -m $RAM_SIZE -smp $CPU_CORES -drive file=$DISK_PATH,format=qcow2"
    
    # KVM Check
    if [ -e /dev/kvm ]; then
        CMD="$CMD -enable-kvm -cpu host"
    else
        echo -e "${RED}WARNING: /dev/kvm missing. Using slow emulation.${NC}"
        sleep 2
    fi

    # ISO Logic
    if [[ "$IS_INSTALL" == "y" ]]; then
         if [ ! -f "$DEBIAN_ISO_PATH" ]; then
            echo "Downloading ISO..."
            wget -O "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_URL"
        fi
        CMD="$CMD -cdrom $DEBIAN_ISO_PATH -boot d"
    fi

    # Display Logic
    if [[ "$USE_GUI" == "y" ]]; then
        CMD="$CMD -vga std"
    else
        CMD="$CMD -nographic" # Using nographic usually works better for pure console
        echo -e "${YELLOW}Starting in Console Mode. If screen is black, press Enter.${NC}"
        echo -e "${YELLOW}To exit QEMU console: Ctrl+A then X${NC}"
    fi

    echo -e "${GREEN}EXECUTING: $CMD${NC}"
    echo "------------------------------------------------"
    
    # Run the command
    eval $CMD
    
    # === CRITICAL FIX: CAPTURE ERROR ===
    EXIT_CODE=$?
    echo "------------------------------------------------"
    if [ $EXIT_CODE -ne 0 ]; then
        echo -e "${RED}ERROR: QEMU crashed with code $EXIT_CODE.${NC}"
        echo "Read the error message above."
    else
        echo -e "${GREEN}VM closed successfully.${NC}"
    fi
    
    read -p "Press Enter to return to menu..."
}

check_dependencies

while true; do
    show_host_data
    echo "1. Create VM"
    echo "2. Run VM"
    echo "3. Exit"
    read -p "Opt: " OPTION
    case $OPTION in
        1) create_vm ;;
        2) run_vm ;;
        3) exit 0 ;;
    esac
done
