#!/usr/bin/env bash
set -euo pipefail

# ... (rest of the script header is the same) ...
# --- CONFIG, OS_NAMES, OS_URLS, cecho, install_dependencies are unchanged ---
VMS_BASE_DIR="vms"
IMAGES_BASE_DIR="images"
OS_NAMES=( "Debian 11 (Bullseye)" "Ubuntu 22.04 (Jammy Jellyfish)" )
declare -A OS_URLS=(
    ["Debian 11 (Bullseye)"]="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"
    ["Ubuntu 22.04 (Jammy Jellyfish)"]="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
)
cecho() {
    local text="$1"; local color_name="$2"; local color_code
    case "$color_name" in green) color_code="\033[0;32m";; red) color_code="\033[0;31m";; blue) color_code="\033[0;34m";; yellow) color_code="\033[1;33m";; *) color_code="\033[0m";; esac
    local nocolor="\033[0m"; echo -e "${color_code}${text}${nocolor}"
}
install_dependencies() {
    if ! command -v qemu-img >/dev/null 2>&1 || ! command -v qemu-system-x86_64 >/dev/null 2>&1 || ! command -v mkisofs >/dev/null 2>&1; then
        cecho "Installing dependencies (qemu, genisoimage)..." "yellow"
        if command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y qemu-system-x86 qemu-utils genisoimage;
        elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y qemu-system-x86 qemu-img genisoimage;
        elif command -v pacman >/dev/null 2>&1; then sudo pacman -Syu --noconfirm qemu-full genisoimage;
        else cecho "Could not determine package manager. Please install 'qemu' and 'genisoimage' manually." "red"; exit 1; fi
        cecho "Dependencies installed." "green"
    fi
}
# --- End of unchanged section ---

download_base_image() {
    local os_name="$1"
    local image_url="${OS_URLS[$os_name]}"
    local image_filename
    image_filename=$(basename "$image_url")
    local local_image_path="$IMAGES_BASE_DIR/$image_filename"

    if [ ! -f "$local_image_path" ]; then
        cecho "Downloading base image for $os_name..." "blue" >&2
        wget --quiet --show-progress -O "$local_image_path" "$image_url"
    else
        cecho "Base image for $os_name already exists." "green" >&2
    fi
    echo "$local_image_path"
}

create_new_vm() {
    cecho "--- Create a New Virtual Machine ---" "blue"

    # 1. Get VM Name
    read -rp "Enter a name for the new VM (no spaces): " VM_NAME
    if [[ -z "$VM_NAME" || "$VM_NAME" =~ \ |/ ]]; then
        cecho "Invalid VM name." "red"
        return 1
    fi
    local VM_DIR="$VMS_BASE_DIR/$VM_NAME"
    if [ -d "$VM_DIR" ]; then
        cecho "A VM with the name '$VM_NAME' already exists." "red"
        return 1
    fi

    # 2. Select OS
    cecho "Select an operating system:" "blue"
    select os_choice in "${OS_NAMES[@]}"; do
        if [[ -n "$os_choice" ]]; then break; else cecho "Invalid selection." "red"; fi
    done

    # --- IMPROVEMENT: GATHER HOST STATS ---
    local HOST_CPUS
    HOST_CPUS=$(nproc)
    local HOST_MEM_AVAILABLE_MB
    HOST_MEM_AVAILABLE_MB=$(( $(grep MemAvailable /proc/meminfo | awk '{print $2}') / 1024 ))

    # --- IMPROVEMENT: SUGGEST SENSIBLE DEFAULTS ---
    local DEFAULT_CPUS=$(( HOST_CPUS > 1 ? HOST_CPUS / 2 : 1 ))
    local DEFAULT_RAM_MB=$(( HOST_MEM_AVAILABLE_MB > 2048 ? 2048 : HOST_MEM_AVAILABLE_MB / 2 ))

    # 3. Get VM Specs with informed prompts
    cecho "Your host has ${HOST_CPUS} CPU(s) and ${HOST_MEM_AVAILABLE_MB}MB of available RAM." "yellow"

    read -rp "Enter disk size in GB [32]: " DISK_SIZE_GB
    DISK_SIZE_GB=${DISK_SIZE_GB:-32}
    read -rp "Enter RAM in MB [${DEFAULT_RAM_MB}]: " RAM_MB
    RAM_MB=${RAM_MB:-${DEFAULT_RAM_MB}}
    read -rp "Enter number of CPU cores [${DEFAULT_CPUS}]: " CPUS
    CPUS=${CPUS:-${DEFAULT_CPUS}}
    read -rsp "Enter the root password: " ROOT_PASSWORD
    echo
    if [ -z "$ROOT_PASSWORD" ]; then
      cecho "Root password cannot be empty." "red"
      return 1
    fi

    # 4. Setup VM directory and disk
    cecho "Creating VM '$VM_NAME'..." "yellow"
    mkdir -p "$VM_DIR"
    local base_image_path
    base_image_path=$(download_base_image "$os_choice")
    local QCOW2_LOCAL="$VM_DIR/$VM_NAME.qcow2"
    cecho "Copying base image..." "yellow"
    cp "$base_image_path" "$QCOW2_LOCAL"
    cecho "Resizing disk to ${DISK_SIZE_GB}GB..." "yellow"
    qemu-img resize "$QCOW2_LOCAL" "${DISK_SIZE_GB}G"

    # 5. Create cloud-init config
    local CLOUD_INIT_DIR="$VM_DIR/cloud-init"
    mkdir -p "$CLOUD_INIT_DIR"
    cat > "$CLOUD_INIT_DIR/user-data" <<EOF
#cloud-config
ssh_pwauth: true
disable_root: false
chpasswd:
  list: |
    root:${ROOT_PASSWORD}
  expire: false
EOF
    cat > "$CLOUD_INIT_DIR/meta-data" <<EOF
instance-id: ${VM_NAME}-$(date +%s)
local-hostname: ${VM_NAME}
EOF
    mkisofs -o "$VM_DIR/seed.iso" -V cidata -r -J "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data" >/dev/null 2>&1

    # 6. Save VM config
    cat > "$VM_DIR/config.sh" <<EOF
# VM Configuration for ${VM_NAME}
VM_NAME="${VM_NAME}"
QCOW2_LOCAL="${QCOW2_LOCAL}"
CLOUD_INIT_ISO="${VM_DIR}/seed.iso"
RAM_MB=${RAM_MB}
CPUS=${CPUS}
ROOT_PASSWORD="${ROOT_PASSWORD}"
EOF
    cecho "VM '$VM_NAME' created successfully!" "green"
    cecho "You can now start it from the main menu." "green"
}


# ... (start_existing_vm and the main menu loop are unchanged) ...
start_existing_vm() {
    cecho "--- Start an Existing Virtual Machine ---" "blue"
    local vms=()
    while IFS= read -r -d $'\0'; do vms+=("$(basename "$REPLY")"); done < <(find "$VMS_BASE_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
    if [ ${#vms[@]} -eq 0 ]; then cecho "No existing VMs found. Please create one first." "red"; return 1; fi
    cecho "Select a VM to start:" "blue"
    select vm_to_start in "${vms[@]}"; do if [[ -n "$vm_to_start" ]]; then break; else cecho "Invalid selection." "red"; fi; done
    local VM_DIR="$VMS_BASE_DIR/$vm_to_start"; local config_file="$VM_DIR/config.sh"
    if [ ! -f "$config_file" ]; then cecho "Configuration file not found for '$vm_to_start'." "red"; return 1; fi
    source "$config_file"
    local SSH_PORT=2222
    while lsof -iTCP:${SSH_PORT} -sTCP:LISTEN -t >/dev/null; do SSH_PORT=$((SSH_PORT+1)); done
    cecho "Launching VM '$VM_NAME'..." "yellow"
    cecho "  - RAM: ${RAM_MB}MB, CPUs: ${CPUS}, Disk: ${QCOW2_LOCAL}" "yellow"
    cecho "  - SSH Forwarding: localhost:${SSH_PORT} -> vm:22" "yellow"
    echo "------------------------------------------------------------"
    qemu-system-x86_64 -enable-kvm -name "$VM_NAME" -m "$RAM_MB" -smp "$CPUS" -cpu host -drive file="$QCOW2_LOCAL",format=qcow2,if=virtio -drive file="$CLOUD_INIT_ISO",media=cdrom -net nic,model=virtio -net user,hostfwd=tcp::${SSH_PORT}-:22 -nographic -serial mon:stdio
    echo "------------------------------------------------------------"
    cecho "VM '$VM_NAME' has exited." "green"
    cecho "To connect to it next time, use:" "green"
    cecho "ssh root@localhost -p ${SSH_PORT} (password: ${ROOT_PASSWORD})" "green"
}
mkdir -p "$VMS_BASE_DIR" "$IMAGES_BASE_DIR"; install_dependencies
while true; do
    clear; cecho "====== QEMU/KVM VM Manager ======" "blue"; PS3="Please enter your choice: "; options=("Create New VM" "Start Existing VM" "Exit")
    select opt in "${options[@]}"; do
        case $opt in
            "Create New VM") create_new_vm; break;;
            "Start Existing VM") start_existing_vm; break;;
            "Exit") exit 0;;
            *) cecho "Invalid option $REPLY" "red";;
        esac
    done
    read -rp $'\nPress Enter to return to the menu...'
done
