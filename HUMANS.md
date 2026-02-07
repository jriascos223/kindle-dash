# Terminology & Concepts

A reference for understanding the tools, techniques, and terminology involved in building software for Kindle e-readers.

## Cross-Compilation

Cross-compilation means compiling code on one architecture (your x86_64 Linux PC) to run on a different architecture (the Kindle's ARM processor). You can't just `gcc main.c` — that produces an x86 binary. You need a cross-compiler that outputs ARM instructions.

### The Target

Kindle e-readers are ARM Cortex-A processors running a stripped-down Linux with glibc:

| Parameter | Value |
|-----------|-------|
| Architecture | ARM 32-bit (`arm`) |
| ABI | hard-float (`gnueabihf`) |
| Float ABI | hardware (`-mfloat-abi=hard`) |
| FPU | VFPv3 (`-mfpu=vfpv3`) on most models |
| C library | glibc (not musl, not uclibc) |
| Endianness | little-endian |
| Kernel | Linux 2.6.x–3.x depending on model |

### The Triple

`arm-none-linux-gnueabihf` is a "target triple" (really a quadruple). It encodes everything the toolchain needs to know:

```
arm          — CPU architecture (ARM 32-bit)
none         — vendor (none/generic)
linux        — operating system (Linux kernel)
gnueabihf    — ABI (GNU EABI, hard-float)
```

The "hf" at the end is critical — it means floating-point arguments are passed in hardware FPU registers. A binary built without hard-float will segfault on the Kindle (or vice versa). You'll see this triple everywhere: compiler binary names, `--host` flags, library paths.

### Toolchain

A toolchain is the set of cross-compilation tools: compiler (`gcc`), linker (`ld`), archiver (`ar`), etc. — all prefixed with the target triple. For example:

```
arm-none-linux-gnueabihf-gcc      # C compiler
arm-none-linux-gnueabihf-g++      # C++ compiler
arm-none-linux-gnueabihf-ar       # static library archiver
arm-none-linux-gnueabihf-strip    # strip debug symbols
arm-none-linux-gnueabihf-readelf  # inspect ELF binaries
```

We use the ARM GNU Toolchain 12.2 from ARM's website. It ships its own glibc and standard headers so basic programs compile without needing anything from the Kindle itself.

### Sysroot

A sysroot is a directory that mirrors the target device's filesystem — specifically its headers (`/usr/include`) and libraries (`/usr/lib`). The cross-compiler uses `--sysroot=/path/to/sysroot` to find the target's system headers and libraries instead of your host machine's.

**When you need it:** When building code that links against libraries or uses kernel headers specific to the Kindle (beyond what the toolchain bundles).

**When you don't:** For self-contained projects or anything that only uses standard libc/libm/pthreads — the toolchain's built-in headers are sufficient.

### Configure Scripts (`./configure`)

Many C projects use GNU autoconf. The key flags for cross-compilation:

- **`--build`** — the machine compiling the code (your PC, auto-detected)
- **`--host`** — the machine that will **run** the binary (the Kindle)
- **`--target`** — only for building compilers themselves (ignore this)

Setting `--host=arm-none-linux-gnueabihf` tells the build system to look for cross-tools and not try to run any compiled test programs (since ARM binaries can't execute on x86).

### Compiler Flags

```
-mfloat-abi=hard    Use hardware floating point (the "hf" in armhf)
-mfpu=vfpv3         Target the VFPv3 floating-point unit
-march=armv7-a      Target ARMv7-A instruction set (all modern Kindles)
-O2                 Standard optimization
-Os                 Optimize for size (good for limited storage/RAM)
--sysroot=PATH      Use target headers/libs from this directory
-static             Link everything statically (no .so dependencies)
```

### Static vs. Dynamic Linking

**Dynamic** (default): Binary is smaller but needs `.so` shared libraries present on the Kindle at runtime. The Kindle has glibc and a few standard libs, but its userspace is minimal.

**Static** (`-static`): Everything is baked into the binary. Larger file, but zero runtime dependencies. Useful for standalone tools.

### Verifying a Build

```bash
# Confirm it's the right architecture
file ./my-binary
# Expected: ELF 32-bit LSB executable, ARM, EABI5, hard-float

# Check shared library dependencies
arm-none-linux-gnueabihf-readelf -d ./my-binary | grep NEEDED
# Should only list libs present on the Kindle (libc.so.6, libm, etc.)
```

## Kindle Environment

### `/mnt/us/`

The user-accessible storage partition on the Kindle. This is what shows up when you connect via USB. It's a vfat (FAT32) filesystem mounted through FUSE, which causes issues: modifying a running script on vfat can corrupt it mid-execution. That's why `dash.sh` copies itself to `/var/tmp/` (a tmpfs ramdisk) before running.

### Init System

The Kindle runs either **sysv init** (older models) or **upstart** (newer models). This determines how system services are started/stopped:

- **sysv**: Services in `/etc/init.d/`, managed with `/etc/init.d/framework start|stop`
- **upstart**: Services in `/etc/upstart/`, managed with `start|stop` commands (e.g., `stop lab126_gui`)

### Framework

The "framework" is Amazon's Java-based UI — the home screen, book reader, store, etc. It owns the framebuffer. To draw to the e-ink screen from custom code, you must stop the framework first. `dash.sh` handles this and restores it on exit.

### Pillow

Kindle's UI overlay system (status bar, popups, notifications). Runs as a separate component from the main framework on upstart-based Kindles. Controlled via LIPC.

### LIPC

Kindle's inter-process communication system (`lipc-set-prop`, `lipc-get-prop`). Used to control system components:

```bash
lipc-set-prop com.lab126.pillow disableEnablePillow disable
lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
```

### Framebuffer

The Linux framebuffer device (`/dev/fb0`) provides direct pixel-level access to the display. On Kindle, this goes through an e-ink display controller (typically i.MX EPDC) that handles the electrophoretic update process. FBInk abstracts this.

### Waveform Modes

E-ink displays don't just "set pixels" — they apply electrical waveforms to move charged particles. Different waveform modes trade speed vs. quality:

- **DU** (Direct Update) — fast, binary black/white only, ghosting
- **GC16** (Grayscale Clear 16) — full 16-level grayscale, slow, clean
- **A2** — very fast, binary, heavy ghosting (good for animations)
- **GL16** — like GC16 but with less flashing
- **REAGL** — reduces ghosting artifacts

FBInk lets you select these per-refresh via `FBInkConfig.wfm_mode`.

## KUAL

**Kindle Unified Application Launcher.** A menu system for jailbroken Kindles that runs custom extensions. It scans `/mnt/us/extensions/` for folders containing a `config.xml` and `menu.json`. Each menu entry maps to a shell command. This is how kindle-dash gets launched — the user taps its entry in KUAL, which runs `bash /mnt/us/kindle-dash/dash.sh`.

## LuaJIT FFI

LuaJIT's Foreign Function Interface lets Lua code call C functions and use C data structures directly, without writing C wrapper/binding code. You declare the C API in Lua:

```lua
ffi.cdef[[
  int fbink_print(int, const char *, const FBInkConfig *);
]]
local FBInk = ffi.load("fbink")  -- loads libfbink.so
FBInk.fbink_print(fd, "hello", cfg)  -- calls C directly
```

This is how kindle-dash uses FBInk — `ffi/fbink_h.lua` contains the C declarations, and `dash.lua` calls them through the loaded library handle. No compilation step needed for the Lua side.

## FBInk

**FrameBuffer eInker.** A C library and CLI tool for rendering to e-ink framebuffers. Handles the complexity of e-ink display controllers across Kindle, Kobo, reMarkable, and other devices. Provides text rendering (31 built-in bitmap fonts), image display, progress bars, screen clearing, and refresh control with waveform mode selection.

Produces two artifacts when built:
- `fbink` — CLI binary (used from shell scripts)
- `libfbink.so` — shared library (used from Lua via FFI)

## KOReader

An open-source document viewer for e-ink devices, written almost entirely in Lua on top of LuaJIT. Its [koreader-base](https://github.com/koreader/koreader-base) submodule provides pre-built native binaries (LuaJIT, FBInk, etc.) for various e-ink platforms. kindle-dash can reuse KOReader's binaries as a fallback when they're installed on the device at `/mnt/us/koreader/`.
