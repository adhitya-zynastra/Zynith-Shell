#!/usr/bin/env bash
# iso/test-vm.sh — boot the Zynith ISO, or a system installed from it, in a disposable QEMU/KVM virtual machine.
#
#   iso/test-vm.sh live [--bios | --secure-boot] [--iso PATH]   boot the ISO through its own boot loader
#   iso/test-vm.sh console [--iso PATH]                         boot the ISO's kernel directly, with a serial console
#                                                               (for scripted checks; same kernel, initrd and image)
#   iso/test-vm.sh install [--iso PATH]                         like console, with a blank 40 GB virtual disk attached
#   iso/test-vm.sh installed [--bios]                           boot that virtual disk
#   iso/test-vm.sh stop                                         power the VM off
#
# The VM runs in the background, headless. Drive it with iso/vmctl.py:
#   iso/vmctl.py screendump build/release/vm/qmp.sock shot.png
#   iso/vmctl.py run build/release/vm/serial.sock 'systemctl is-system-running'
# The serial console is also logged to build/release/vm/serial.log.
#
# Everything lives in build/release/vm/: the virtual disk, the firmware variables, the sockets. The VM sees only its
# own virtual disk and the ISO; it has user-mode networking (no access to the host's network services) and a
# virtio GPU with OpenGL through the host's render node (--no-gl for a plain framebuffer).
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
RUN="${ZYNITH_VM_DIR:-$ROOT/build/release/vm}"
OVMF=/usr/share/edk2/ovmf
mode="${1:-}"; shift || true
fw=uefi iso="" gl=1 mem="${ZYNITH_VM_MEM:-4096}" cpus="${ZYNITH_VM_CPUS:-4}" res="${ZYNITH_VM_RES:-1920x1080}"
while (($#)); do
    case "$1" in
    --bios) fw=bios; shift ;;
    --secure-boot) fw=secure; shift ;;
    --iso) iso="$2"; shift 2 ;;
    --no-gl) gl=0; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
die() { echo "test-vm: $*" >&2; exit 1; }
mkdir -p "$RUN"

running() { [[ -f "$RUN/qemu.pid" ]] && kill -0 "$(cat "$RUN/qemu.pid")" 2>/dev/null; }
if [[ "$mode" == stop ]]; then
    running || { echo "not running"; exit 0; }
    # a desktop session may hold the power key for itself; shut down from the console when a shell is there
    timeout 20 python3 "$ROOT/iso/vmctl.py" run "$RUN/serial.sock" "sudo systemctl poweroff" >/dev/null 2>&1 \
        || python3 "$ROOT/iso/vmctl.py" powerdown "$RUN/qmp.sock" || true
    for _ in $(seq 1 60); do running || { echo "stopped"; exit 0; }; sleep 1; done
    pid="$(cat "$RUN/qemu.pid")"; kill "$pid"
    while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
    rm -f "$RUN/qemu.pid"; echo "killed (it did not power off within 60 s)"; exit 0
fi
[[ "$mode" =~ ^(live|console|install|installed)$ ]] || { sed -n '2,16p' "$0"; exit 2; }
running && die "a test VM is already running (iso/test-vm.sh stop)"

if [[ "$mode" != installed ]]; then
    [[ -n "$iso" ]] || iso="$(ls -t "$ROOT"/build/release/iso/zynith-*.iso 2>/dev/null | head -1)"
    [[ -f "$iso" ]] || die "no ISO (build one with iso/build-iso.sh, or pass --iso)"
fi

args=(-enable-kvm -cpu host -smp "$cpus" -m "$mem" -name zynith-test
      -nic "user,model=virtio-net-pci"
      -audiodev "none,id=snd" -device intel-hda -device "hda-duplex,audiodev=snd"
      -device qemu-xhci -device usb-tablet
      -qmp "unix:$RUN/qmp.sock,server=on,wait=off"
      -chardev "socket,id=ser0,path=$RUN/serial.sock,server=on,wait=off,logfile=$RUN/serial.log"
      -serial chardev:ser0 -monitor none -daemonize -pidfile "$RUN/qemu.pid")
# the display's resolution (the guest picks it as the preferred mode)
vga="xres=${res%x*},yres=${res#*x}"
if ((gl)); then
    args+=(-device "virtio-vga-gl,$vga" -display "egl-headless,rendernode=/dev/dri/renderD128")
else
    # no virgl: the guest renders in software; QEMU's screendump works on this framebuffer
    args+=(-device "virtio-vga,$vga" -display none)
fi

case "$fw" in
uefi)
    args+=(-machine q35)
    [[ -f "$RUN/vars.fd" && "$mode" == installed ]] || cp "$OVMF/OVMF_VARS.fd" "$RUN/vars.fd"
    args+=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF/OVMF_CODE.fd" -drive "if=pflash,format=raw,file=$RUN/vars.fd") ;;
secure)
    # Fedora's OVMF with the Microsoft and distribution keys enrolled: the shim → GRUB → kernel chain must verify
    args+=(-machine "q35,smm=on" -global "driver=cfi.pflash01,property=secure,value=on")
    [[ -f "$RUN/vars-sb.fd" && "$mode" == installed ]] || cp "$OVMF/OVMF_VARS.secboot.fd" "$RUN/vars-sb.fd"
    args+=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF/OVMF_CODE.secboot.fd" -drive "if=pflash,format=raw,file=$RUN/vars-sb.fd") ;;
bios)
    args+=(-machine q35) ;;
esac

case "$mode" in
live)
    args+=(-cdrom "$iso" -boot d) ;;
console | install)
    label="$(isoinfo -d -i "$iso" | sed -n 's/^Volume id: //p')"
    [[ -n "$label" ]] || die "cannot read the ISO's volume label"
    rm -rf "${RUN:?}/boot" && mkdir -p "$RUN/boot"
    7z e -y -o"$RUN/boot" "$iso" images/pxeboot/vmlinuz images/pxeboot/initrd.img >/dev/null \
        || die "the ISO has no images/pxeboot/{vmlinuz,initrd.img}"
    args+=(-cdrom "$iso" -kernel "$RUN/boot/vmlinuz" -initrd "$RUN/boot/initrd.img"
           -append "root=live:CDLABEL=$label rd.live.image console=tty0 console=ttyS0,115200")
    if [[ "$mode" == install ]]; then
        rm -f "$RUN/disk.qcow2"
        qemu-img create -q -f qcow2 "$RUN/disk.qcow2" 40G
        args+=(-drive "file=$RUN/disk.qcow2,if=virtio,format=qcow2")
    fi ;;
installed)
    [[ -f "$RUN/disk.qcow2" ]] || die "no installed disk (iso/test-vm.sh install first)"
    args+=(-drive "file=$RUN/disk.qcow2,if=virtio,format=qcow2") ;;
esac

rm -f "$RUN/serial.log"
nice -n 10 qemu-system-x86_64 "${args[@]}"
echo "VM running ($mode, $fw$( ((gl)) && echo ', virgl')): $RUN (qmp.sock, serial.sock, serial.log)"
