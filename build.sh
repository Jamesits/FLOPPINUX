#!/bin/bash
set -euo pipefail

# FLOPPINUX Automated Build Script
# Based on FLOPPINUX v0.3.1 by Krzysztof Krystian Jankowski
# Headless build - no interactive menuconfig, uses scripted config

KERNEL_VERSION="6.14.11"
KERNEL_MAJOR="6"
BUSYBOX_TAG="1_36_1"
MUSL_CROSS_VERSION="20250929"
MUSL_CROSS_TARGET="i686-unknown-linux-musl"

BASE="$(pwd)/build"
OUTPUT="$(pwd)/output"

error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

info() {
    echo "==> $1"
}

cleanup() {
    if mountpoint -q /tmp/floppinux-mnt 2>/dev/null; then
        sudo umount /tmp/floppinux-mnt 2>/dev/null || true
    fi
}
trap cleanup EXIT

rm -rf "$BASE" "$OUTPUT"
mkdir -p "$BASE" "$OUTPUT"

###############################################################################
# Cross Compiler
###############################################################################
info "Downloading i686 musl cross compiler..."
cd "$BASE"
wget -q "https://github.com/cross-tools/musl-cross/releases/download/${MUSL_CROSS_VERSION}/${MUSL_CROSS_TARGET}.tar.xz" \
    || error_exit "Failed to download cross compiler"
tar xf "${MUSL_CROSS_TARGET}.tar.xz"
rm "${MUSL_CROSS_TARGET}.tar.xz"

CROSS_PREFIX="$BASE/${MUSL_CROSS_TARGET}/bin/${MUSL_CROSS_TARGET}-"
"${CROSS_PREFIX}gcc" --version > /dev/null 2>&1 || error_exit "Cross compiler not functional"
info "Cross compiler ready"

###############################################################################
# Linux Kernel
###############################################################################
info "Downloading Linux kernel v${KERNEL_VERSION}..."
cd "$BASE"
wget -q "https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/linux-${KERNEL_VERSION}.tar.xz" \
    || error_exit "Failed to download kernel"
tar xf "linux-${KERNEL_VERSION}.tar.xz"
rm "linux-${KERNEL_VERSION}.tar.xz"
cd "linux-${KERNEL_VERSION}"

info "Configuring kernel (headless)..."
make ARCH=x86 tinyconfig || error_exit "tinyconfig failed"

KC="./scripts/config --file .config"

# General Setup -> Configure standard kernel features -> printk
$KC --enable EXPERT
$KC --enable PRINTK

# General Setup -> Initial RAM filesystem (XZ only)
$KC --enable BLK_DEV_INITRD
$KC --enable RD_XZ
$KC --disable RD_GZIP
$KC --disable RD_BZIP2
$KC --disable RD_LZMA
$KC --disable RD_LZO
$KC --disable RD_LZ4
$KC --disable RD_ZSTD

# Processor type and features -> 486DX
$KC --enable M486

# Enable the block layer
$KC --enable BLOCK

# Executable file formats
$KC --enable BINFMT_ELF
$KC --enable BINFMT_SCRIPT

# Device Drivers -> Block devices
$KC --enable BLK_DEV_FD
$KC --enable BLK_DEV_RAM
$KC --set-val BLK_DEV_RAM_COUNT 1
$KC --set-val BLK_DEV_RAM_SIZE 4096

# Device Drivers -> Character devices -> TTY
$KC --enable TTY
$KC --enable VT
$KC --enable VT_CONSOLE
$KC --enable UNIX98_PTYS

# File systems -> DOS/FAT -> MSDOS
$KC --enable FAT_FS
$KC --enable MSDOS_FS

# File systems -> Pseudo filesystems
$KC --enable PROC_FS
$KC --enable SYSFS

# File systems -> Native language support
$KC --enable NLS
$KC --enable NLS_CODEPAGE_437

# Library routines -> XZ decompression (disable all BCJ sub-filters)
$KC --enable XZ_DEC
$KC --disable XZ_DEC_X86
$KC --disable XZ_DEC_POWERPC
$KC --disable XZ_DEC_IA64
$KC --disable XZ_DEC_ARM
$KC --disable XZ_DEC_ARMTHUMB
$KC --disable XZ_DEC_SPARC

# Resolve all dependencies
make ARCH=x86 olddefconfig || error_exit "olddefconfig failed"

info "Compiling kernel (this may take a while)..."
make ARCH=x86 bzImage -j"$(nproc)" 2>&1 | tail -5 || error_exit "Kernel compilation failed"

KERNEL_PATH="arch/x86/boot/bzImage"
[ -f "$KERNEL_PATH" ] || error_exit "bzImage not found after compilation"
cp "$KERNEL_PATH" "$BASE/bzImage"
info "Kernel compiled: $(du -h "$BASE/bzImage" | cut -f1)"

###############################################################################
# BusyBox
###############################################################################
info "Downloading BusyBox..."
cd "$BASE"
wget -q "https://github.com/mirror/busybox/archive/refs/tags/${BUSYBOX_TAG}.tar.gz" \
    || error_exit "Failed to download BusyBox"
tar xzf "${BUSYBOX_TAG}.tar.gz"
rm "${BUSYBOX_TAG}.tar.gz"
cd "busybox-${BUSYBOX_TAG}"

info "Configuring BusyBox (headless)..."
make ARCH=x86 allnoconfig || error_exit "allnoconfig failed"

# Arch Linux lxdialog fix (harmless on other distros)
sed -i 's/main() {}/int main() {}/' scripts/kconfig/lxdialog/check-lxdialog.sh 2>/dev/null || true

# Cross compiler paths
sed -i "s|.*CONFIG_CROSS_COMPILER_PREFIX.*|CONFIG_CROSS_COMPILER_PREFIX=\"${CROSS_PREFIX}\"|" .config
sed -i "s|.*CONFIG_SYSROOT.*|CONFIG_SYSROOT=\"${BASE}/${MUSL_CROSS_TARGET}/${MUSL_CROSS_TARGET}/sysroot\"|" .config
sed -i "s|.*CONFIG_EXTRA_CFLAGS.*|CONFIG_EXTRA_CFLAGS=\"-march=i486 -mtune=i486\"|" .config
sed -i "s|.*CONFIG_EXTRA_LDFLAGS.*|CONFIG_EXTRA_LDFLAGS=\"\"|" .config

# Settings: static binary, large file support
cat >> .config << 'BUSYBOX_OPTS'
CONFIG_LFS=y
CONFIG_STATIC=y
CONFIG_CAT=y
CONFIG_CP=y
CONFIG_DF=y
CONFIG_ECHO=y
CONFIG_LS=y
CONFIG_MKDIR=y
CONFIG_MV=y
CONFIG_RM=y
CONFIG_SYNC=y
CONFIG_TEST=y
CONFIG_TEST1=y
CONFIG_TEST2=y
CONFIG_CLEAR=y
CONFIG_VI=y
CONFIG_INIT=y
CONFIG_MDEV=y
CONFIG_MOUNT=y
CONFIG_FEATURE_MOUNT_FLAGS=y
CONFIG_UMOUNT=y
CONFIG_ASH=y
CONFIG_ASH_OPTIMIZE_FOR_SIZE=y
CONFIG_ASH_ALIAS=y
BUSYBOX_OPTS

make ARCH=x86 silentoldconfig || error_exit "BusyBox silentoldconfig failed"

info "Compiling BusyBox..."
make ARCH=x86 -j"$(nproc)" 2>&1 | tail -5 || error_exit "BusyBox compilation failed"
make ARCH=x86 install || error_exit "BusyBox install failed"

mv _install "$BASE/filesystem"
info "BusyBox compiled successfully"

###############################################################################
# Filesystem
###############################################################################
info "Building root filesystem..."
cd "$BASE/filesystem"

mkdir -pv dev proc etc/init.d sys tmp home

# Welcome message
cat > welcome << 'WELCOME_EOF'

                _________________
               /_/ FLOPPINUX  /_/;
              / ' boot disk  ' //
             / '------------' //
            /   .--------.   //
           /   /         /  //
          .___/_________/__//   1440KiB
          '===\_________\=='   3.5"

_______FLOPPINUX_V_0.3.1 __________________________________
_______AN_EMBEDDED_SINGLE_FLOPPY_LINUX_DISTRIBUTION _______
_______BY_KRZYSZTOF_KRYSTIAN_JANKOWSKI ____________________
_______2025.12 ____________________________________________
WELCOME_EOF

# Inittab
cat > etc/inittab << 'EOF'
::sysinit:/etc/init.d/rc
::askfirst:/bin/sh
::restart:/sbin/init
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
EOF

# Init script
cat > etc/init.d/rc << 'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mdev -s
ln -s /proc/mounts /etc/mtab
mkdir -p /mnt /home
mount -t msdos -o rw /dev/fd0 /mnt
mkdir -p /mnt/data
mount --bind /mnt/data /home
clear
cat welcome
cd /home
/bin/sh
EOF

chmod +x etc/init.d/rc

# Create initramfs with fakeroot (handles device nodes + root ownership without sudo)
info "Creating initramfs (rootfs.cpio.xz)..."
fakeroot sh -c '
    mknod dev/console c 5 1
    mknod dev/null c 1 3
    chown -R root:root .
    find . | cpio -H newc -o 2>/dev/null | xz --check=crc32 --lzma2=dict=512KiB -e > ../rootfs.cpio.xz
' || error_exit "Failed to create initramfs"

info "Initramfs created: $(du -h "$BASE/rootfs.cpio.xz" | cut -f1)"

###############################################################################
# Boot Image
###############################################################################
info "Assembling floppy boot image..."
cd "$BASE"

# Syslinux bootloader config
cat > syslinux.cfg << 'EOF'
DEFAULT floppinux
LABEL floppinux
SAY [ BOOTING FLOPPINUX VERSION 0.3.1 ]
KERNEL bzImage
INITRD rootfs.cpio.xz
APPEND root=/dev/ram rdinit=/etc/init.d/rc console=tty0 tsc=unstable
EOF

# Sample user file
cat > hello.txt << 'EOF'
Hello, FLOPPINUX user!
EOF

# Create 1.44MB floppy image
dd if=/dev/zero of=floppinux.img bs=1k count=1440 2>/dev/null || error_exit "dd failed"

# Format as FAT12 and install syslinux bootloader
mkdosfs -n FLOPPINUX floppinux.img || error_exit "mkdosfs failed"
syslinux --install floppinux.img || error_exit "syslinux install failed"

# Copy files onto FAT image using mtools (no sudo/mount needed)
mcopy -i floppinux.img bzImage ::bzImage || error_exit "Failed to copy kernel"
mcopy -i floppinux.img rootfs.cpio.xz ::rootfs.cpio.xz || error_exit "Failed to copy rootfs"
mcopy -i floppinux.img syslinux.cfg ::syslinux.cfg || error_exit "Failed to copy syslinux.cfg"
mmd -i floppinux.img ::data || error_exit "Failed to create data dir"
mcopy -i floppinux.img hello.txt ::data/hello.txt || error_exit "Failed to copy hello.txt"

# Verify floppy size constraint
FLOPPY_SIZE=$(stat -c%s floppinux.img)
MAX_SIZE=1474560
if [ "$FLOPPY_SIZE" -gt "$MAX_SIZE" ]; then
    error_exit "Floppy image exceeds 1.44MB: ${FLOPPY_SIZE} > ${MAX_SIZE}"
fi

# Show free space on image
info "Floppy image contents:"
mdir -i floppinux.img :: 2>/dev/null || true

###############################################################################
# Output
###############################################################################
cp "$BASE/bzImage" "$OUTPUT/"
cp "$BASE/rootfs.cpio.xz" "$OUTPUT/"
cp "$BASE/floppinux.img" "$OUTPUT/"

info "Build complete!"
echo ""
echo "FLOPPINUX v0.3.1 Build Summary"
echo "==============================="
echo "Kernel:    $(du -h "$OUTPUT/bzImage" | cut -f1) (bzImage)"
echo "Rootfs:    $(du -h "$OUTPUT/rootfs.cpio.xz" | cut -f1) (rootfs.cpio.xz)"
echo "Image:     $(du -h "$OUTPUT/floppinux.img" | cut -f1) (floppinux.img)"
echo ""
ls -lh "$OUTPUT/"
