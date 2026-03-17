#!/bin/bash
set -euo pipefail

# End-to-end boot test for Floppinux
# Boots the floppy image with QEMU, interacts over serial to confirm
# we can get a shell (askfirst) and execute 'ls'.

TIMEOUT=30
OUTPUT_DIR="${1:-$(pwd)/output}"
TMPDIR=$(mktemp -d)
SERIAL_LOG="$TMPDIR/serial.log"
SERIAL_IN="$TMPDIR/serial.in"
FLOPPY="$OUTPUT_DIR/floppinux.img"

cleanup() {
    exec 3>&- 2>/dev/null || true
    [ -n "${TAIL_PID:-}" ] && kill "$TAIL_PID" 2>/dev/null || true
    [ -n "${QEMU_PID:-}" ] && kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

die() {
    echo "FAIL: $1" >&2
    exit 1
}

# Wait until a fixed string appears in the serial log
wait_for() {
    local pattern="$1"
    local timeout="$2"
    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        if grep -qF "$pattern" "$SERIAL_LOG" 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
        if ! kill -0 "$QEMU_PID" 2>/dev/null; then
            die "QEMU exited unexpectedly while waiting for: $pattern"
        fi
    done
    return 1
}

# Named pipe for sending input to QEMU's serial console
mkfifo "$SERIAL_IN"

# Boot QEMU with serial on stdio, piped through our FIFO / log
qemu-system-i386 \
    -drive file="$FLOPPY",format=raw,if=floppy,readonly=on \
    -boot menu=on \
    -net none \
    -m 32 \
    -display none \
    -serial stdio \
    -no-reboot \
    < "$SERIAL_IN" > "$SERIAL_LOG" 2>&1 &
QEMU_PID=$!

# Hold the write end open so QEMU doesn't see EOF on stdin
exec 3>"$SERIAL_IN"

# Stream the full boot log to stdout in real time
tail -f "$SERIAL_LOG" 2>/dev/null &
TAIL_PID=$!

echo "Waiting for boot (up to ${TIMEOUT}s)..."

# BusyBox askfirst prints "Please press Enter to activate this console."
wait_for "Please press Enter to activate this console" "$TIMEOUT" \
    || die "Timed out waiting for askfirst prompt"
echo "Got askfirst prompt, sending Enter..."

printf '\n' >&3
sleep 1

# After Enter, BusyBox ash shows "/ # " (or similar prompt with #)
wait_for "# " 10 || die "Timed out waiting for shell prompt"
echo "Got shell, running 'ls'..."

printf 'ls\n' >&3
sleep 2

# The root initramfs should contain standard directories
if grep -qF "bin" "$SERIAL_LOG" && grep -qF "etc" "$SERIAL_LOG"; then
    echo ""
    echo "PASS: Booted to shell and executed ls successfully"
    exit 0
else
    die "'ls' output did not contain expected directories (bin, etc)"
fi
