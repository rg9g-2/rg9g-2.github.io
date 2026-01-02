#!/bin/bash

VM_NAME="Debian11_Final"
RAM="15G"
CORES="6"
DISK_NAME="debian11-76G.qcow2"

# --- 1. FIX THE MISSING TOOL (CENTOS 9 SPECIFIC) ---
if ! command -v virt-customize &> /dev/null; then
    echo "-------------------------------------------------------"
    echo "DETECTED CENTOS 9. INSTALLING CORRECT TOOLS..."
    echo "-------------------------------------------------------"
    # In CentOS 9, we must install 'guestfs-tools' specifically
    sudo dnf install guestfs-tools -y
    
    if [ $? -ne 0 ]; then
        echo "Error installing tools. We will try to boot anyway,"
        echo "but you might need to do the manual password hack."
        sleep 3
    fi
fi

# --- 2. HACK PASSWORD ---
if command -v virt-customize &> /dev/null; then
    echo "-------------------------------------------------------"
    echo "RESETTING PASSWORD TO 'root'..."
    echo "-------------------------------------------------------"
    
    # Reset password and fix SSH config
    virt-customize -a "$DISK_NAME" \
        --root-password password:root \
        --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
        --run-command 'sed -i "s/PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config' || true
else
    echo "WARNING: virt-customize still missing. You will have to hack the GRUB menu."
fi

# --- 3. RUN VM ---
echo "-------------------------------------------------------"
echo "BOOTING NOW."
echo "Login: root"
echo "Password: root"
echo "To exit VM: Press Ctrl+A, then X"
echo "-------------------------------------------------------"
sleep 2

# Check for binary
if command -v qemu-system-x86_64 &> /dev/null; then QEMU="qemu-system-x86_64"; else QEMU="qemu-kvm"; fi

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
