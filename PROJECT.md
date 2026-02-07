# kindle-dash — Project Reference

A Lua application for jailbroken Kindle e-readers that turns the device into a low-power dashboard. Launched via KUAL (Kindle Unified Application Launcher), it uses LuaJIT and FBInk to render content directly to the e-ink framebuffer.

## Goals

- Simple API for integrating "subscriptions" (data sources)
- Configurable sizing and refresh rates for "tiles"
- A tiling layout system for the e-ink display

## Architecture Overview

```
Host (x86_64 Linux)                    Kindle (armhf)
┌─────────────────────┐                ┌──────────────────────────────┐
│ Cross-compile C libs │ ──deploy──▶   │ /mnt/us/kindle-dash/         │
│ (armhf sysroot)      │               │   dash.sh        (launcher)  │
└─────────────────────┘                │   dash.lua       (main app)  │
                                       │   setupkoenv.lua (paths)     │
                                       │   ffi/fbink_h.lua (bindings) │
                                       │   libs/*.so      (native)    │
                                       │                              │
                                       │ /mnt/us/extensions/          │
                                       │   kindle-dash/               │
                                       │     config.xml  (KUAL meta)  │
                                       │     menu.json   (KUAL entry) │
                                       └──────────────────────────────┘
```

### Execution Flow

1. User taps "kindle-dash" in the KUAL menu
2. KUAL runs `bash /mnt/us/kindle-dash/dash.sh`
3. `dash.sh` copies itself to `/var/tmp/` (workaround for vfat+fuse issues on Kindle)
4. `dash.sh` detects the init system (upstart vs sysv), stops the Kindle UI framework, pillow, and background services to free RAM
5. `dash.sh` locates a LuaJIT binary (local, KOReader's, or system)
6. LuaJIT executes `dash.lua`, which loads `libfbink.so` via FFI and renders to the e-ink display
7. On exit, `dash.sh`'s trap handler restores all stopped services and the Kindle UI

## Technology Stack

### Lua / LuaJIT

All application logic is written in Lua, executed by LuaJIT. The project does **not** bundle its own LuaJIT binary — it discovers one at runtime, preferring a local copy, then falling back to KOReader's (`/mnt/us/koreader/luajit`), then the system path. The same strategy applies to shared libraries via `LD_LIBRARY_PATH`.

LuaJIT's FFI is used to call C libraries directly from Lua without writing C wrapper code. See `ffi/fbink_h.lua` for the FBInk bindings.

### FBInk

[FBInk](https://github.com/NiLuJe/FBInk) ("FrameBuffer eInker") is the primary display library. It abstracts e-ink display controllers (i.MX EPDC, MTK, sunxi) and provides framebuffer rendering optimized for e-ink (waveform mode selection, hardware dithering, partial/full refresh). Licensed GPLv3+.

Building FBInk produces two artifacts:
- **`fbink`** — standalone CLI binary for shell-level screen operations
- **`libfbink.so`** — shared C library consumed via FFI from Lua

#### FBInk is a runtime dependency, not vendored

FBInk source is **not** checked into this repo. There is no git submodule, no build step in the Makefile, and no pre-built binaries committed. The project discovers FBInk at runtime through fallback search paths, or you cross-compile and bundle it yourself.

#### Two components, two search strategies

**1. `fbink` CLI binary** — used by `dash.sh` for status messages during startup (before LuaJIT is running):

```
dash.sh:find_fbink() search order:
  /var/tmp/fbink                ← runtime copy on tmpfs (made at startup)
  /mnt/us/kindle-dash/fbink     ← bundled with the app
  /mnt/us/koreader/fbink        ← from KOReader installation
  /mnt/us/libkh/bin/fbink       ← from libkh helper package
  /usr/bin/fbink                ← system install
```

If a local copy exists at `${DASH_DIR}/fbink`, `dash.sh` copies it to `/var/tmp/fbink` at startup to avoid vfat+fuse filesystem issues.

**2. `libfbink.so` shared library** — loaded by `dash.lua` via LuaJIT FFI in two stages:

```
Stage 1 — dynamic linker (relies on LD_LIBRARY_PATH set by dash.sh):
  ffi.load("fbink")
  LD_LIBRARY_PATH = /mnt/us/kindle-dash/libs:/mnt/us/koreader/libs:...

Stage 2 — explicit path fallback (if Stage 1 fails):
  /mnt/us/koreader/libs/libfbink.so
  /mnt/us/libfbink.so
  /usr/lib/libfbink.so
  → fatal error if none found
```

#### FFI bindings (`ffi/fbink_h.lua`)

This file is copied from [lua-fbink](https://github.com/NiLuJe/lua-fbink). It is a manual transcription of FBInk's C header (`fbink.h`) into LuaJIT `ffi.cdef` declarations — no higher-level wrapping. Lua code calls the C API directly.

It declares:
- **Structs**: `FBInkConfig` (rendering options), `FBInkState` (device info), `FBInkOTConfig` (OpenType fonts), `FBInkRect`, `FBInkDump`, `FBInkOTFit`
- **Enums**: fonts (31 bitmap fonts), waveform modes, foreground/background grayscale colors, alignment, padding, dithering algorithms
- **29 function signatures**: `fbink_open/close/init`, `fbink_print` (bitmap text), `fbink_print_ot` (OpenType text), `fbink_print_image/raw_data`, `fbink_cls` (clear), `fbink_refresh`, `fbink_wait_for_complete`, `fbink_dump/restore`, `fbink_print_progress_bar`, device state queries, and more

If FBInk is upgraded to a version with API changes, update this file from the lua-fbink repo.

#### Where FBInk files live on the Kindle

```
/mnt/us/kindle-dash/
├── fbink              ← CLI binary (optional, you provide this)
├── libs/
│   └── libfbink.so    ← shared library (optional, you provide this)
├── ffi/
│   └── fbink_h.lua    ← FFI declarations (checked into this repo)
└── ...

/mnt/us/koreader/      ← fallback (if KOReader is installed)
├── fbink
└── libs/libfbink.so
```

#### Cross-compiling FBInk for Kindle

To bundle FBInk for standalone deployment (without relying on KOReader):

```bash
git clone https://github.com/NiLuJe/FBInk
cd FBInk
make KINDLE=1 CC=arm-none-linux-gnueabihf-gcc
```

This produces `fbink` (CLI) and `libfbink.so`. Copy them to your deployment:
- `fbink` → project root (or `dist/kindle-dash/`)
- `libfbink.so` → `libs/` (or `dist/kindle-dash/libs/`)

For older Kindle Firmware 2.x devices, add `LEGACY=1` to the make command.

> **Note**: The Makefile does not currently copy a `libs/` directory or `fbink` binary into `dist/`. If you bundle these, you'll need to update the Makefile accordingly.

### KOReader Runtime Reuse

This project piggybacks on a KOReader installation when possible. KOReader is a document viewer (97% Lua) built on the [koreader-base](https://github.com/koreader/koreader-base) framework. koreader-base provides:

- Pre-built LuaJIT binary for armhf Kindle targets
- `libfbink.so` and other native libraries
- Lua modules for device interaction

If KOReader is installed on the Kindle at `/mnt/us/koreader/`, kindle-dash can use its LuaJIT and libs as fallbacks. For standalone deployment, you must cross-compile and bundle these binaries yourself.

**KOReader repos:**
- Main project: https://github.com/koreader/koreader
- BASE submodule (low-level C/Lua plumbing, e-ink drivers, FBInk integration): https://github.com/koreader/koreader-base

## KUAL Integration

[KUAL](https://github.com/coplate/KUAL_Booklet) scans `/mnt/us/extensions/` for extension folders. Each extension needs:

**`config.xml`** — Extension metadata (name, id, version, author, menu type):
```xml
<extension>
    <information>
        <name>kindle-dash</name>
        <id>kindle-dash</id>
        <version>1.1</version>
        <author>Jorsc</author>
    </information>
    <menus>
        <menu type="json" dynamic="true">menu.json</menu>
    </menus>
</extension>
```

**`menu.json`** — Menu entries that map to shell commands:
```json
{
    "items": [
        {"name": "kindle-dash", "action": "bash /mnt/us/kindle-dash/dash.sh"}
    ]
}
```

KUAL requires a jailbroken Kindle with the MobileRead Kindlet Kit installed. See the [KUAL Booklet repo](https://github.com/coplate/KUAL_Booklet) for device-specific installation (azw2 sideload for older models, MRPI for newer).

## Cross-Compilation

### Target Architecture

**armhf** (ARM hard-float, `arm-none-linux-gnueabihf`). Kindle e-readers use ARM Cortex-A processors running a custom embedded Linux. Treat it like any embedded Linux armhf target — the Kindle's userspace is minimal and idiosyncratic but standard enough for cross-compiled ELF binaries.

### Toolchain Setup

Download the ARM GNU toolchain and extract it:

```bash
cd ~/workspace
wget https://developer.arm.com/-/media/Files/downloads/gnu/12.2.rel1/binrel/arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
tar -xf arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-linux-gnueabihf.tar.xz
```

The compiler lives at:
```
~/workspace/tools/arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-gcc
```

### Kindle Sysroot

A sysroot provides the Kindle's kernel headers and system libraries so the cross-compiler can link against the correct targets. This is **required** for building C code (LuaJIT, FBInk, or any native library) that will run on the Kindle.

**Obtaining a sysroot:**
- Thread with sysroot solution: https://www.mobileread.com/forums/showthread.php?t=277236&page=5
- Download Kindle firmware source from [Amazon's GPL page](https://www.amazon.com/gp/help/customer/display.html?nodeId=200203720) (e.g. Paperwhite 5.8.1 source), then extract the `build_linaro-gcc_4.8.3.tar.gz` toolchain archive
- Alternatively, extract headers from the firmware directly

**Installing the sysroot:**
```bash
# Extract cross-compiler
tar -C $HOME/kindle/opt -xzf cross-arm-linux-gnueabi-gcc-linaro-4.8-2014.04.tar.gz
# Extract kernel headers into the sysroot
tar -C $HOME/kindle/opt/cross-gcc-linaro/arm-linux-gnueabi -xzf khdrs.tar.gz
```

### Configure Pattern for Cross-Compiling C Projects

```bash
TOOLCHAIN_PATH=~/workspace/tools/arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-linux-gnueabihf/bin

./configure --host=arm-none-linux-gnueabihf \
  CC="$TOOLCHAIN_PATH/arm-none-linux-gnueabihf-gcc" \
  --disable-openssl \
  --disable-xxhash \
  --disable-zstd \
  --disable-lz4
```

Or with sysroot:
```bash
arm-linux-gnu-gcc -mfloat-abi=hard -mfpu=vfpv3 \
  --sysroot=$HOME/kindle-sysroot main.c -o output
```

See `notes.md` for additional cross-compilation command examples and variations.

## Building & Deploying

### Build the distribution package

```bash
make              # or: make install-package
```

This creates `dist/` with the correct directory layout:
- `dist/kindle-dash/` — application files (Lua sources, shell launcher)
- `dist/extensions/kindle-dash/` — KUAL extension files (config.xml, menu.json)

### Deploy to Kindle

1. Connect Kindle via USB
2. Copy the contents of `dist/` to the Kindle root:
   ```bash
   cp -r dist/* /media/Kindle/       # Linux
   cp -r dist/* /Volumes/Kindle/     # macOS
   ```
3. Eject the Kindle
4. Open KUAL and tap "kindle-dash"

### File Locations on Kindle

| Path | Purpose |
|------|---------|
| `/mnt/us/kindle-dash/` | Application directory (dash.lua, dash.sh, libs/) |
| `/mnt/us/extensions/kindle-dash/` | KUAL extension registration |
| `/mnt/us/koreader/` | KOReader install (optional, used as fallback for LuaJIT/libs) |
| `/var/tmp/` | Runtime copies of dash.sh and fbink (tmpfs, avoids vfat issues) |

## Key Files

| File | Purpose |
|------|---------|
| `dash.sh` | Shell launcher — handles init system detection, stops Kindle services, finds LuaJIT, runs dash.lua, restores services on exit |
| `dash.lua` | Main Lua entry point — loads FBInk via FFI, renders content to the e-ink screen |
| `setupkoenv.lua` | Configures Lua `package.path` and `package.cpath` for the project and KOReader fallback paths |
| `ffi/fbink_h.lua` | LuaJIT FFI C declarations for FBInk (structs, enums, function signatures). Sourced from [lua-fbink](https://github.com/NiLuJe/lua-fbink) |
| `kual/config.xml` | KUAL extension metadata |
| `kual/menu.json` | KUAL menu entry definition |
| `Makefile` | Builds the `dist/` deployment package |
| `notes.md` | Developer notes with cross-compilation commands and toolchain setup steps |

## Kindle Environment Notes

- **Filesystem**: Kindle's `/mnt/us/` is vfat+fuse — scripts can break if modified while running. That's why `dash.sh` copies itself to `/var/tmp/` (tmpfs) before execution.
- **Init systems**: Older Kindles use sysv init (`/etc/rc.d/`), newer ones use upstart (`/etc/upstart/`). `dash.sh` handles both.
- **UI framework**: The Kindle's Java-based UI framework must be stopped to get exclusive framebuffer access. `dash.sh` stops `lab126_gui` (upstart) or the framework service (sysv), plus pillow (the UI overlay), volumd, awesome/cvm, and various background services.
- **Input devices**: `/proc/keypad` and `/proc/fiveway` may need unlocking for button input.
- **LIPC**: Kindle's inter-process communication (`lipc-set-prop`) is used to control system components like pillow.
- **Library path**: Native `.so` files are loaded via `LD_LIBRARY_PATH` — the project sets this to include its own `libs/` dir and KOReader's.

## External Resources

| Resource | Link |
|----------|------|
| Kindle/ereader tools & downloads (NiLuJe) | https://www.mobileread.com/forums/showthread.php?t=225030 |
| KUAL Booklet (launcher) | https://github.com/coplate/KUAL_Booklet |
| KOReader | https://github.com/koreader/koreader |
| KOReader BASE (low-level libs, e-ink, FBInk) | https://github.com/koreader/koreader-base |
| FBInk (framebuffer library) | https://github.com/NiLuJe/FBInk |
| lua-fbink (FFI bindings source) | https://github.com/NiLuJe/lua-fbink |
| Kindle sysroot thread | https://www.mobileread.com/forums/showthread.php?t=277236&page=5 |
| Amazon GPL source downloads | https://www.amazon.com/gp/help/customer/display.html?nodeId=200203720 |
| ARM GNU Toolchain downloads | https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads |
