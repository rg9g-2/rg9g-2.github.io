#!/bin/bash

# ==========================================
# CentOS 9 VM Manager (Pre-Installed QCOW2)
# ==========================================

VM_DIR="$HOME/qemu_vms"
IMG_DIR="$VM_DIR/images"
# Official Debian 11 Cloud Image
DEBIAN_URL="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
BASE_IMG="$IMG_DIR/debian-base.qcow2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# === FIND QEMU BINARY ===
if [ -f "/usr/libexec/qemu-kvm" ]; then
    QEMU_CMD="/usr/libexec/qemu-kvm"
elif command -v qemu-system-x86_64 &> /dev/null; then
    QEMU_CMD="qemu-system-x86_64"
else
    QEMU_CMD="NONE"
fi

mkdir -p "$VM_DIR"
mkdir -p "$IMG_DIR"

check_dependencies() {
    echo -e "${BLUE}Checking dependencies...${NC}"
    
    # 1. Check QEMU
    if [ "$QEMU_CMD" == "NONE" ]; then
        echo -e "${YELLOW}Installing QEMU...${NC}"
        sudo dnf install -y qemu-kvm qemu-img
        if [ -f "/usr/libexec/qemu-kvm" ]; then QEMU_CMD="/usr/libexec/qemu-kvm"; fi
    fi

    # 2. Check for virt-customize (Needed to set password)
    if ! command -v virt-customize &> /dev/null; then
        echo -e "${YELLOW}Installing libguestfs-tools (to set root password)...${NC}"
        # Enable CRB repo usually needed for some dependencies, but try install first
        sudo dnf install -y guestfs-tools
    fi
    
    # 3. Download Base Image
    if [ ! -f "$BASE_IMG" ]; then
        echo -e "${YELLOW}Downloading Debian 11 Cloud Image (Pre-installed)...${NC}"
        wget -O "$BASE_IMG" "$DEBIAN_URL"
        if [ $? -ne 0 ]; then echo -e "${RED}Download failed.${NC}"; exit 1; fi
    fi
}

create_vm() {
    clear
    echo -e "${YELLOW}--- Create New VM (From Pre-installed Image) ---${NC}"
    read -p "Name (no spaces): " VM_NAME
    if [ -z "$VM_NAME" ]; then return; fi
    if [ -f "$VM_DIR/$VM_NAME.qcow2" ]; then echo "Exists!"; sleep 1; return; fi

    read -p "Disk Size (e.g. 10G): " DISK_SIZE

    echo -e "${BLUE}1. cloning base image...${NC}"
    cp "$BASE_IMG" "$VM_DIR/$VM_NAME.qcow2"

    echo -e "${BLUE}2. Resizing disk to $DISK_SIZE...${NC}"
    qemu-img resize "$VM_DIR/$VM_NAME.qcow2" "$DISK_SIZE" &>/dev/null

    echo -e "${BLUE}3. Setting root password to 'root'...${NC}"
    echo -e "${YELLOW}(This might take 30 seconds, please wait...)${NC}"
    
    # This injects the password 'root' into the disk image
    export LIBGUESTFS_BACKEND=direct
    virt-customize -a "$VM_DIR/$VM_NAME.qcow2" --root-password password:root --uninstall cloud-init

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Success! VM Created.${NC}"
        echo -e "User: ${YELLOW}root${NC}"
        echo -e "Pass: ${YELLOW}root${NC}"
    else
        echo -e "${RED}Failed to set password. You might need sudo/kvm access.${NC}"
    fi
    read -p "Press Enter..."
}

run_vm() {
    clear
    echo -e "${YELLOW}--- Run VM ---${NC}"
    ls "$VM_DIR"/*.qcow2 2>/dev/null | grep -v "isos" | xargs -n 1 basename | sed 's/.qcow2//'
    echo ""
    read -p "VM Name: " VM_NAME
    DISK_PATH="$VM_DIR/$VM_NAME.qcow2"
    
    if [ ! -f "$DISK_PATH" ]; then echo "Not found."; sleep 1; return; fi

    read -p "RAM (e.g. 2G): " RAM_SIZE
    read -p "Cores (e.g. 2): " CPU_CORES

    # We enforce -nographic because curses is broken on CentOS
    CMD="$QEMU_CMD -m $RAM_SIZE -smp $CPU_CORES -drive file=$DISK_PATH,format=qcow2"
    
    if [ -e /dev/kvm ]; then CMD="$CMD -enable-kvm -cpu host"; fi
    
    # Add nographic and serial console redirection
    CMD="$CMD -nographic"

    echo -e "${GREEN}Starting VM...${NC}"
    echo -e "-------------------------------------------------"
    echo -e "Login with User: ${YELLOW}root${NC} | Password: ${YELLOW}root${NC}"
    echo -e "To kill/exit the VM: Press ${YELLOW}Ctrl+A${NC}, release, then press ${YELLOW}X${NC}."
    echo -e "-------------------------------------------------"
    sleep 3
    
    eval $CMD
    
    read -p "VM Closed. Press Enter..."
}

check_dependencies
while true; do
    clear
    echo "1. Create VM (Auto-install Debian 11)"
    echo "2. Run VM"
    echo "3. Exit"
    read -p "Select: " OPTION
    case $OPTION in
        1) create_vm ;;
        2) run_vm ;;
        3) exit ;;
    esac
done
