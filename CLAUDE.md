# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Lua application for jailbroken Kindle e-readers that turns the device into a low-power dashboard. Launched via KUAL (Kindle Unified Application Launcher), it uses LuaJIT and FBInk to render content directly to the e-ink framebuffer.

## Build & Deploy

```bash
make                # Creates dist/ with correct Kindle directory layout
make clean          # Removes dist/
```

The build produces `dist/kindle-dash/` (app files) and `dist/extensions/kindle-dash/` (KUAL integration). Deploy by copying `dist/*` to the Kindle root over USB.

There are no tests or linting configured.

## Cross-Compilation

Target: **armhf** (`arm-none-linux-gnueabihf`). Toolchain: ARM GNU Toolchain 12.2 at `~/workspace/tools/arm-gnu-toolchain-12.2.rel1-x86_64-arm-none-linux-gnueabihf/`.

FBInk cross-compilation:
```bash
git clone https://github.com/NiLuJe/FBInk && cd FBInk
make KINDLE=1 CC=arm-none-linux-gnueabihf-gcc
```
Copy resulting `fbink` to project root and `libfbink.so` to `libs/`.

## Architecture

```
dash.sh (shell launcher)
  → stops Kindle UI framework, pillow, background services
  → finds LuaJIT binary (local → KOReader → system)
  → sets LD_LIBRARY_PATH for native libs
  → executes dash.lua via LuaJIT
  → EXIT trap restores all services on exit

dash.lua (main Lua app)
  → loads libfbink.so via LuaJIT FFI
  → renders to e-ink framebuffer using FBInk C API
```

### Key Files

| File | Role |
|------|------|
| `dash.sh` | Shell launcher: init system detection (upstart vs sysv), service management, LuaJIT/FBInk discovery, cleanup on exit |
| `dash.lua` | Main app: loads FBInk via FFI, renders to e-ink display |
| `setupkoenv.lua` | Configures Lua `package.path`/`package.cpath` (currently not required by dash.lua, which sets its own paths) |
| `ffi/fbink_h.lua` | LuaJIT FFI C declarations for FBInk — copied from [lua-fbink](https://github.com/NiLuJe/lua-fbink), update from there if FBInk API changes |
| `kual/config.xml`, `kual/menu.json` | KUAL extension registration |
| `libs/libfbink.so` | Cross-compiled FBInk shared library (not checked into git, you provide this) |

### Runtime Dependency Resolution

The project does **not** bundle LuaJIT or require a specific install location. Both `dash.sh` and `dash.lua` implement fallback search chains:

- **LuaJIT**: local `${DASH_DIR}/luajit` → KOReader's `/mnt/us/koreader/luajit` → system `luajit`
- **libfbink.so**: `LD_LIBRARY_PATH` (includes `libs/` and KOReader's `libs/`) → explicit paths → fatal error
- **fbink CLI**: `/var/tmp/fbink` → local → KOReader → libkh → system

KOReader at `/mnt/us/koreader/` serves as the primary fallback for all native binaries.

## Kindle Environment Constraints

- `/mnt/us/` is vfat+fuse — modifying a running script corrupts it. That's why `dash.sh` copies itself to `/var/tmp/` (tmpfs) before execution.
- The Kindle's Java UI framework must be stopped for exclusive framebuffer access. `dash.sh` handles stop/restore.
- Init system varies by Kindle model: older = sysv (`/etc/init.d/`), newer = upstart (`/etc/upstart/`). `dash.sh` detects and handles both.
- All application code is Lua — C libraries are called via LuaJIT FFI, no C wrapper code.
