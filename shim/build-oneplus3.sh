#!/bin/bash
# Build the OnePlus 3T shim: start.S + oneplus3.c + pstore.c + console.c, wrapped in
# a stock-style v0 boot.img by tools/mkboot-v0.sh.
# A PAYLOAD (tools/mkpayload.py, or tools/mkstub-payload.py with
# out/oneplus3/stub.bin) is appended to the Image at _end (see oneplus3.c).
# Usage: [WDT_SECS=120] shim/build-oneplus3.sh STOCK_BOOT.img [PAYLOAD]   -> shim/out/oneplus3-boot.img
# WDT_SECS: APSS watchdog bite after the jump (0 = off; see oneplus3.c).
set -euo pipefail
stock=$(realpath "$1")
payload=${2:+$(realpath "$2")}
cd "$(dirname "$0")"
X=aarch64-linux-gnu-
command -v ${X}gcc >/dev/null || X=aarch64-elf-	# macOS Homebrew
CFLAGS="-O2 -ffreestanding -nostdlib -fno-pic -mgeneral-regs-only -mstrict-align -fno-stack-protector -Wall -Wextra -DPIXEL1 -DONEPLUS3 ${EXTRA_CFLAGS:-} -DWDT_SECS=${WDT_SECS:-120}"
mkdir -p out/oneplus3
for f in start.S oneplus3.c pstore.c console.c fdt.c loader.c; do
	${X}gcc $CFLAGS -c $f -o out/oneplus3/${f%.*}.o
done
# No relocation pass at runtime: only start.o's image_size may be absolute.
abs=$(${X}readelf -r out/oneplus3/oneplus3.o out/oneplus3/pstore.o out/oneplus3/console.o out/oneplus3/fdt.o out/oneplus3/loader.o | grep -c ABS64 || true)
[ "$abs" = 0 ] || { echo "error: $abs absolute relocations in C objects" >&2; exit 1; }
${X}gcc $CFLAGS -static -T shim.ld -Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N \
	out/oneplus3/start.o out/oneplus3/oneplus3.o out/oneplus3/pstore.o out/oneplus3/console.o out/oneplus3/fdt.o out/oneplus3/loader.o -o out/oneplus3/shim.elf
${X}objcopy -O binary out/oneplus3/shim.elf out/oneplus3/Image
size=$(${X}nm out/oneplus3/shim.elf | awk '$3=="_end"{print $1}')
truncate -s $((16#$size)) out/oneplus3/Image
[ -z "$payload" ] || cat "$payload" >> out/oneplus3/Image
../tools/mkboot-v0.sh "$stock" out/oneplus3/Image out/oneplus3-boot.img
# Loader test "kernel" (shim/stub.c), same link rules.
${X}gcc $CFLAGS -c stub.c -o out/oneplus3/stub.o
${X}gcc $CFLAGS -static -T shim.ld -Wl,--build-id=none -Wl,--no-warn-rwx-segments -Wl,-N \
	out/oneplus3/stub.o out/oneplus3/pstore.o out/oneplus3/console.o -o out/oneplus3/stub.elf
${X}objcopy -O binary out/oneplus3/stub.elf out/oneplus3/stub.bin
size=$(${X}nm out/oneplus3/stub.elf | awk '$3=="_end"{print $1}')
truncate -s $((16#$size)) out/oneplus3/stub.bin
