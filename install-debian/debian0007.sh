#!/bin/bash

VM_NAME="Debian11_Fixed"
RAM="15G"
CORES="6"
DISK_NAME="debian11-76G.qcow2"

# --- 1. INSTALL TOOLS ---
if ! command -v virt-customize &> /dev/null; then
    echo "Installing libguestfs-tools (required to hack the password)..."
    sudo yum install libguestfs-tools -y
fi

# --- 2. FORCE PASSWORD RESET ---
echo "-------------------------------------------------------"
echo "HACKING DISK IMAGE TO RESET PASSWORD..."
echo "-------------------------------------------------------"

# This command does 3 things:
# 1. Sets root password to 'root'
# 2. Creates a file that KILLS cloud-init (so it stops messing with settings)
# 3. Enables Password Authentication for SSH
virt-customize -a "$DISK_NAME" \
    --root-password password:root \
    --touch /etc/cloud/cloud-init.disabled \
    --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
    --run-command 'sed -i "s/PermitRootLogin.*/PermitRootLogin yes/g" /etc/ssh/sshd_config'

if [ $? -ne 0 ]; then
    echo "ERROR: Could not modify disk. Make sure the VM is NOT running!"
    exit 1
fi

echo "-------------------------------------------------------"
echo "SUCCESS. Default login:"
echo "User: root"
echo "Pass: root"
echo "-------------------------------------------------------"
echo "Booting in 3 seconds..."
sleep 3

# --- 3. RUN VM ---
# We use -nographic to see it in the terminal
# We explicitly set console to ttyS0 to ensure you see the prompt

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
