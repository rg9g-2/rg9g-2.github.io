#!/bin/bash

# ==========================================
# CentOS 9 QEMU VM Manager (Debian 12 Bookworm)
# ==========================================

# --- Configuration ---
VM_DIR="$HOME/qemu_vms"
IMG_DIR="$VM_DIR/images"

# USING DEBIAN 12 (BOOKWORM) STABLE - Best for Pterodactyl
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

# --- Setup Directories ---
mkdir -p "$VM_DIR"
mkdir -p "$IMG_DIR"

function pause() {
    echo ""
    read -p "Press Enter to continue..."
}

# --- 1. Dependency Check ---
function check_dependencies() {
    clear
    echo -e "${BLUE}Checking Dependencies...${NC}"
    
    # Check Wget
    if ! command -v wget &> /dev/null; then
        echo -e "${YELLOW}Installing wget...${NC}"
        sudo dnf install -y wget
    fi

    # Check QEMU
    if [ "$QEMU_CMD" == "NONE" ]; then
        echo -e "${YELLOW}Installing QEMU (Virtualization)...${NC}"
        sudo dnf install -y qemu-kvm qemu-img
        if [ -f "/usr/libexec/qemu-kvm" ]; then QEMU_CMD="/usr/libexec/qemu-kvm"; fi
    fi

    # Check virt-customize (Required for password setting)
    if ! command -v virt-customize &> /dev/null; then
        echo -e "${YELLOW}Installing libguestfs-tools (Needed to set root password)...${NC}"
        sudo dnf install -y guestfs-tools
    fi
    
    # Check KVM Support
    if [ ! -e /dev/kvm ]; then
        echo -e "${RED}WARNING: Hardware Virtualization (KVM) not enabled.${NC}"
        echo -e "${YELLOW}The VM will be very slow. Enable Virtualization in BIOS if possible.${NC}"
        sleep 2
    fi
}

# --- 2. Create VM ---
function create_vm() {
    clear
    echo -e "${YELLOW}--- Create New Debian 12 VM (For Pterodactyl) ---${NC}"
    
    read -p "Enter VM Name (no spaces): " VM_NAME
    if [ -z "$VM_NAME" ]; then echo -e "${RED}Name cannot be empty.${NC}"; pause; return; fi
    if [ -f "$VM_DIR/$VM_NAME.qcow2" ]; then echo -e "${RED}VM already exists.${NC}"; pause; return; fi

    read -p "Disk Size (e.g. 20G, 50G): " DISK_SIZE

    # === DOWNLOAD LOGIC ===
    echo -e "${BLUE}Checking for Debian 12 Base Image...${NC}"
    
    if [ ! -s "$BASE_IMG_PATH" ]; then
        echo -e "${YELLOW}Base image not found. Downloading Debian 12 Bookworm...${NC}"
        echo -e "${CYAN}URL: $DEBIAN_URL${NC}"
        
        wget --no-check-certificate -O "$BASE_IMG_PATH" "$DEBIAN_URL"
        
        if [ $? -ne 0 ] || [ ! -s "$BASE_IMG_PATH" ]; then
            echo -e "${RED}Download failed! Check internet.${NC}"
            rm -f "$BASE_IMG_PATH"
            pause; return
        fi
        echo -e "${GREEN}Download Complete.${NC}"
    else
        echo -e "${GREEN}Base image exists. Using cached copy.${NC}"
    fi

    echo -e "${BLUE}1. Cloning image...${NC}"
    cp "$BASE_IMG_PATH" "$VM_DIR/$VM_NAME.qcow2"

    echo -e "${BLUE}2. Resizing disk to $DISK_SIZE...${NC}"
    qemu-img resize "$VM_DIR/$VM_NAME.qcow2" "$DISK_SIZE" &>/dev/null

    echo -e "${BLUE}3. Configuring VM (Password & Network)...${NC}"
    echo -e "${YELLOW}Running virt-customize (Wait 30-60s)...${NC}"

    export LIBGUESTFS_BACKEND=direct
    virt-customize -a "$VM_DIR/$VM_NAME.qcow2" \
        --root-password password:root \
        --uninstall cloud-init \
        --run-command 'echo "auto lo" > /etc/network/interfaces' \
        --run-command 'echo "iface lo inet loopback" >> /etc/network/interfaces' \
        --run-command 'echo "allow-hotplug ens3" >> /etc/network/interfaces' \
        --run-command 'echo "iface ens3 inet dhcp" >> /etc/network/interfaces' \
        --run-command 'apt-get clean'

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}VM Created Successfully!${NC}"
        echo -e "Login User: ${YELLOW}root${NC}"
        echo -e "Login Pass: ${YELLOW}root${NC}"
    else
        echo -e "${RED}Error configuring VM. Try running this script with sudo.${NC}"
    fi
    pause
}

# --- 3. Run VM ---
function run_vm() {
    clear
    echo -e "${YELLOW}--- Run VM ---${NC}"
    
    # List VMs
    count=$(ls "$VM_DIR"/*.qcow2 2>/dev/null | grep -v "images" | wc -l)
    if [ "$count" -eq 0 ]; then echo "No VMs found."; pause; return; fi
    
    ls "$VM_DIR"/*.qcow2 2>/dev/null | grep -v "images" | xargs -n 1 basename | sed 's/.qcow2//'
    echo ""
    
    read -p "VM Name: " VM_NAME
    DISK_PATH="$VM_DIR/$VM_NAME.qcow2"
    if [ ! -f "$DISK_PATH" ]; then echo "Not found."; pause; return; fi

    read -p "RAM (e.g. 4G): " RAM_SIZE
    read -p "Cores (e.g. 2): " CPU_CORES
    read -p "GUI Window? (y/n): " USE_GUI

    # Networking: virtio-net is required for high performance (Pterodactyl/Wings)
    CMD="$QEMU_CMD -m $RAM_SIZE -smp $CPU_CORES -drive file=$DISK_PATH,format=qcow2"
    CMD="$CMD -device virtio-net-pci,netdev=net0 -netdev user,id=net0"
    
    if [ -e /dev/kvm ]; then CMD="$CMD -enable-kvm -cpu host"; fi

    if [[ "$USE_GUI" == "y" ]]; then
        echo -e "${GREEN}Starting VNC on :0 (Connect via VNC Viewer to IP:5900)${NC}"
        CMD="$CMD -vnc :0 -vga qxl"
    else
        echo -e "${GREEN}Starting Console...${NC}"
        echo -e "${YELLOW}To Exit: Press Ctrl+A, release, then X.${NC}"
        CMD="$CMD -nographic"
    fi

    echo -e "Running: $CMD"
    sleep 2
    eval $CMD
    pause
}

# --- 4. Delete VM ---
function delete_vm() {
    clear
    echo -e "${RED}--- Delete VM ---${NC}"
    ls "$VM_DIR"/*.qcow2 2>/dev/null | grep -v "images" | xargs -n 1 basename | sed 's/.qcow2//'
    echo ""
    read -p "VM Name to delete: " VM_NAME
    DISK_PATH="$VM_DIR/$VM_NAME.qcow2"
    
    if [ -f "$DISK_PATH" ]; then
        read -p "Are you sure? (y/n): " CONFIRM
        if [[ "$CONFIRM" == "y" ]]; then
            rm -f "$DISK_PATH"
            echo -e "${GREEN}Deleted.${NC}"
        fi
    else
        echo "Not found."
    fi
    pause
}

# --- Main Menu ---
check_dependencies
while true; do
    clear
    echo -e "${CYAN}=== CentOS 9 QEMU Manager (Debian 12) ===${NC}"
    echo "1. Create VM (Auto-install Debian 12)"
    echo "2. Run VM"
    echo "3. Delete VM"
    echo "4. Exit"
    echo ""
    read -p "Select: " OPTION
    case $OPTION in
        1) create_vm ;;
        2) run_vm ;;
        3) delete_vm ;;
        4) exit 0 ;;
    esac
done
