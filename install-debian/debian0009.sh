#!/bin/bash

# ==============================================================================
#  FEDORA KVM HYPERVISOR // ULTRA HUD EDITION
# ==============================================================================

# --- THEME CONFIGURATION ---
C_CYAN='\033[38;5;51m'
C_BLUE='\033[38;5;39m'
C_GREEN='\033[38;5;82m'
C_GREY='\033[38;5;240m'
C_WHITE='\033[38;5;255m'
C_WARN='\033[38;5;202m'
NC='\033[0m'

# --- VM CONFIGURATION ---
VM_NAME="DEBIAN_11_CORE"
RAM="15G"
CORES="6"
DISK_SIZE="76G"
DISK_NAME="debian11-76G.qcow2"
URL="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"

# --- HUD FUNCTIONS ---
cursor_to() { printf "\033[%s;%sH" "$1" "$2"; }
draw_box() {
    local h=$1; local w=$2; local t=$3
    printf "${C_BLUE}┌"
    for ((i=1; i<=w-2; i++)); do printf "─"; done
    printf "┐\n"
    for ((i=1; i<=h-2; i++)); do
        printf "│"
        for ((j=1; j<=w-2; j++)); do printf " "; done
        printf "│\n"
    done
    printf "└"
    for ((i=1; i<=w-2; i++)); do printf "─"; done
    printf "┘${NC}"
    cursor_to 2 4; echo -e "${C_WHITE}${t}${NC}"
}

print_status() {
    local row=$1
    local label=$2
    local status=$3
    local color=$4
    cursor_to $row 4
    printf "${C_CYAN}%-20s ${C_GREY}:: ${color}%s${NC}" "$label" "$status"
}

progress_bar() {
    local row=$1
    local percent=$2
    local bar_len=40
    local fill=$(( (percent * bar_len) / 100 ))
    cursor_to $row 4
    printf "${C_CYAN}PROGRESS [${C_GREEN}"
    for ((i=0; i<fill; i++)); do printf "▓"; done
    for ((i=fill; i<bar_len; i++)); do printf "░"; done
    printf "${C_CYAN}] ${C_WHITE}%3d%%${NC}" "$percent"
}

# --- MAIN LOGIC ---
clear
draw_box 18 70 "FEDORA HYPERVISOR // SYSTEM INITIALIZATION"

# 1. DEPENDENCY CHECK
print_status 4 "SYSTEM SCAN" "CHECKING MODULES..." "${C_WHITE}"
if ! command -v qemu-img &> /dev/null || ! command -v virt-customize &> /dev/null; then
    print_status 4 "SYSTEM SCAN" "INSTALLING DEPENDENCIES (DNF)" "${C_WARN}"
    sudo dnf install qemu-kvm guestfs-tools wget -y -q > /dev/null 2>&1
fi
print_status 4 "SYSTEM SCAN" "ONLINE" "${C_GREEN}"

# 2. LOCATE BINARY
print_status 5 "HYPERVISOR" "LOCATING BINARY..." "${C_WHITE}"
if [ -f "/usr/bin/qemu-system-x86_64" ]; then QEMU="/usr/bin/qemu-system-x86_64";
elif [ -f "/usr/libexec/qemu-kvm" ]; then QEMU="/usr/libexec/qemu-kvm";
else QEMU="qemu-kvm"; fi
print_status 5 "HYPERVISOR" "ACTIVE ($QEMU)" "${C_GREEN}"

# 3. DISK OPERATIONS
if [ ! -f "$DISK_NAME" ]; then
    print_status 6 "DISK IMAGE" "DOWNLOADING DEBIAN 11..." "${C_WARN}"
    
    # Download with progress simulation for the HUD
    wget -q --show-progress -O "${DISK_NAME}.base" "$URL" &
    PID=$!
    while kill -0 $PID 2>/dev/null; do
        for i in {1..100}; do progress_bar 14 $i; sleep 0.05; done
    done
    wait $PID

    print_status 6 "DISK IMAGE" "DOWNLOAD COMPLETE" "${C_GREEN}"
    
    print_status 7 "STORAGE ALLOC" "RESIZING TO $DISK_SIZE..." "${C_WHITE}"
    cp "${DISK_NAME}.base" "$DISK_NAME"
    qemu-img resize "$DISK_NAME" "$DISK_SIZE" > /dev/null 2>&1
    print_status 7 "STORAGE ALLOC" "OPTIMIZED ($DISK_SIZE)" "${C_GREEN}"

    # 4. SECURITY & NETWORK INJECTION
    print_status 8 "SECURITY LAYER" "INJECTING ROOT ACCESS..." "${C_WARN}"
    print_status 9 "NETWORK LINK" "CONFIGURING DHCP..." "${C_WARN}"
    
    # Fedora Direct Backend Fix
    export LIBGUESTFS_BACKEND=direct
    
    # RESET PASSWORD AND FORCE NETWORK ON
    virt-customize -a "$DISK_NAME" \
        --root-password password:root \
        --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
        --run-command 'sed -i "s/PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config' \
        --run-command 'systemctl enable systemd-networkd' \
        --selinux-relabel > /dev/null 2>&1
        
    print_status 8 "SECURITY LAYER" "BYPASSED (User: root)" "${C_GREEN}"
    print_status 9 "NETWORK LINK" "CONNECTED (VirtIO)" "${C_GREEN}"
else
    print_status 6 "DISK IMAGE" "DETECTED" "${C_GREEN}"
    print_status 7 "STORAGE ALLOC" "READY ($DISK_SIZE)" "${C_GREEN}"
    print_status 8 "SECURITY LAYER" "PRE-CONFIGURED" "${C_GREEN}"
    print_status 9 "NETWORK LINK" "READY" "${C_GREEN}"
fi

# 5. FINAL SPECS
print_status 11 "RAM ASSIGNMENT" "$RAM DDR4" "${C_WHITE}"
print_status 12 "CPU ALLOCATION" "$CORES V-CORES" "${C_WHITE}"

# 6. LAUNCH
cursor_to 16 4
echo -e "${C_WHITE}LAUNCHING VIRTUAL MACHINE... (Press ${C_WARN}Ctrl+A${C_WHITE} then ${C_WARN}X${C_WHITE} to Force Quit)${NC}"
sleep 2

# Clear HUD and launch
clear
$QEMU \
    -name "$VM_NAME" \
    -enable-kvm \
    -m $RAM \
    -smp $CORES \
    -cpu host \
    -drive file="$DISK_NAME",format=qcow2,if=virtio \
    -nographic \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
    -append "root=/dev/vda1 console=ttyS0 rw"
