#!/bin/bash

# ==========================================
# CentOS 9 QEMU VM Manager (Debian 11 Focused)
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
NC='\033[0m' # No Color

# Ensure directories exist
mkdir -p "$VM_DIR"
mkdir -p "$ISO_DIR"

# 1. Dependency Check
check_dependencies() {
    echo -e "${BLUE}Checking system dependencies...${NC}"
    
    if ! command -v qemu-system-x86_64 &> /dev/null; then
        echo -e "${YELLOW}QEMU not found. Installing via DNF (requires sudo)...${NC}"
        sudo dnf install -y qemu-kvm qemu-img
    fi
    
    if ! command -v wget &> /dev/null; then
        sudo dnf install -y wget
    fi

    # Check for KVM support
    if [ -e /dev/kvm ]; then
        echo -e "${GREEN}KVM Hardware Acceleration is available.${NC}"
    else
        echo -e "${RED}WARNING: /dev/kvm not found. VM will be very slow (Software emulation).${NC}"
        echo -e "${YELLOW}Ensure Virtualization is enabled in BIOS.${NC}"
        sleep 2
    fi
}

# 2. Show Host Data
show_host_data() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}           HOST SYSTEM DATA              ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    # CPU Info
    MODEL=$(lscpu | grep "Model name" | cut -d ':' -f2 | xargs)
    CORES=$(nproc)
    echo -e "CPU Model : ${GREEN}$MODEL${NC}"
    echo -e "CPU Cores : ${GREEN}$CORES${NC}"
    
    # RAM Info
    FREE_RAM=$(free -h | awk '/^Mem:/ {print $4}')
    TOTAL_RAM=$(free -h | awk '/^Mem:/ {print $2}')
    echo -e "RAM (Free/Total) : ${GREEN}$FREE_RAM / $TOTAL_RAM${NC}"
    
    # Disk Info
    DISK_AVAIL=$(df -h $HOME | awk 'NR==2 {print $4}')
    echo -e "Disk Space (Home) : ${GREEN}$DISK_AVAIL Available${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
}

# 3. Create VM Function
create_vm() {
    echo -e "${YELLOW}--- Create New Debian 11 VM ---${NC}"
    read -p "Enter VM Name (no spaces): " VM_NAME
    
    if [ -f "$VM_DIR/$VM_NAME.qcow2" ]; then
        echo -e "${RED}Error: A VM with that name already exists.${NC}"
        read -p "Press Enter to continue..."
        return
    fi

    read -p "Enter Disk Size (e.g., 10G, 20G): " DISK_SIZE
    
    echo -e "${BLUE}Creating Disk Image...${NC}"
    qemu-img create -f qcow2 "$VM_DIR/$VM_NAME.qcow2" "$DISK_SIZE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}VM Disk created at $VM_DIR/$VM_NAME.qcow2${NC}"
    else
        echo -e "${RED}Failed to create disk.${NC}"
    fi
    
    # Check for ISO
    if [ ! -f "$DEBIAN_ISO_PATH" ]; then
        echo -e "${YELLOW}Debian 11 ISO not found. Downloading now...${NC}"
        wget -O "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_URL"
    fi

    echo -e "${GREEN}Ready to install.${NC}"
    read -p "Press Enter to return to menu..."
}

# 4. Run VM Function
run_vm() {
    echo -e "${YELLOW}--- Run Virtual Machine ---${NC}"
    
    # List available VMs
    echo "Available VMs:"
    ls "$VM_DIR"/*.qcow2 2>/dev/null | xargs -n 1 basename | sed 's/.qcow2//'
    echo ""
    
    read -p "Enter VM Name to run: " VM_NAME
    DISK_PATH="$VM_DIR/$VM_NAME.qcow2"
    
    if [ ! -f "$DISK_PATH" ]; then
        echo -e "${RED}VM not found!${NC}"
        read -p "Press Enter..."
        return
    fi

    # Configuration prompts
    read -p "RAM Size (e.g. 2G, 4G): " RAM_SIZE
    read -p "CPU Cores (e.g. 2): " CPU_CORES
    read -p "Enable GUI window? (yes/no) [default: no]: " USE_GUI
    read -p "Is this a new installation (Boot from ISO)? (yes/no): " IS_INSTALL

    # Build Command
    CMD="qemu-system-x86_64"
    CMD="$CMD -enable-kvm -cpu host"
    CMD="$CMD -m $RAM_SIZE -smp $CPU_CORES"
    CMD="$CMD -drive file=$DISK_PATH,format=qcow2"
    
    # Check if installing
    if [[ "$IS_INSTALL" == "yes" || "$IS_INSTALL" == "y" ]]; then
        # Ensure ISO exists
         if [ ! -f "$DEBIAN_ISO_PATH" ]; then
            echo -e "${YELLOW}Downloading Debian 11 ISO...${NC}"
            wget -O "$DEBIAN_ISO_PATH" "$DEBIAN_ISO_URL"
        fi
        CMD="$CMD -cdrom $DEBIAN_ISO_PATH -boot d"
    fi

    # Display Logic
    if [[ "$USE_GUI" == "yes" || "$USE_GUI" == "y" ]]; then
        echo -e "${BLUE}Starting in GUI mode...${NC}"
        # Standard VGA
        CMD="$CMD -vga std"
    else
        echo -e "${BLUE}Starting in Terminal mode (Curses)...${NC}"
        echo -e "${YELLOW}NOTE: If installing Debian in terminal mode, select 'Install' (Not Graphical Install) in the boot menu.${NC}"
        # -curses renders the VGA output to text in the terminal
        CMD="$CMD -curses"
    fi

    # Execute
    echo -e "${GREEN}Running command:${NC} $CMD"
    sleep 2
    eval $CMD
}

# Main Loop
check_dependencies

while true; do
    show_host_data
    echo "1. Create New Debian 11 VM"
    echo "2. Run/Install VM"
    echo "3. Exit"
    echo ""
    read -p "Select an option [1-3]: " OPTION

    case $OPTION in
        1)
            create_vm
            ;;
        2)
            run_vm
            ;;
        3)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
done
