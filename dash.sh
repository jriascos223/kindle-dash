#!/bin/sh
#
# Kindle-Dash launcher script
# Based on KOReader's launch techniques
#

export LC_ALL="en_US.UTF-8"

# Working directory
DASH_DIR="/mnt/us/kindle-dash"
LOGFILE="${DASH_DIR}/dash.log"

# NOTE: Stupid workaround to make sure the script we end up running is a *copy*,
# living in a magical land that doesn't suffer from gross filesystem deficiencies.
# Otherwise, the vfat+fuse mess means an OTA update will break the script on exit,
# and potentially leave the user in a broken state, with the WM still paused...
# Additionally, this is used by kindle-dash? to detect if the original script has
# changed after an update (requiring a complete restart from the parent
# launcher).
# TLDR: moves execution to /var/tmp in case there's issues
if [ "$(dirname "${0}")" != "/var/tmp" ]; then
	cp -pf "${0}" /var/tmp/dash.sh
	chmod 777 /var/tmp/dash.sh
	exec /var/tmp/dash.sh "$@"
fi

# Detect init system
if [ -d /etc/upstart ]; then
	INIT_TYPE="upstart"
	# Source upstart logging functions
	[ -f /etc/upstart/functions ] && . /etc/upstart/functions
else
	INIT_TYPE="sysv"
	[ -f /etc/rc.d/functions ] && . /etc/rc.d/functions
fi

# State tracking
STOP_FRAMEWORK="no"
PILLOW_DISABLED="no"
AWESOME_STOPPED="no"
CVM_STOPPED="no"
VOLUMD_STOPPED="no"

# Services to stop for RAM
TOGGLED_SERVICES="stored webreader kfxreader kfxview todo tmd rcm archive scanner otav3 otaupd"

log() {
	msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
	echo "${msg}" >>"${LOGFILE}"
	echo "${msg}"
}

# Find FBInk binary
find_fbink() {
	for path in \
		/var/tmp/fbink \
		"${DASH_DIR}/fbink" \
		/mnt/us/koreader/fbink \
		/mnt/us/libkh/bin/fbink \
		/usr/bin/fbink; do
		if [ -x "${path}" ]; then
			echo "${path}"
			return 0
		fi
	done
	return 1
}

# Print message at bottom of screen
eips_print_bottom() {
	msg="${1}"
	y_shift="${2:-0}"

	FBINK_BIN=$(find_fbink)
	if [ -n "${FBINK_BIN}" ]; then
		usleep 150000
		${FBINK_BIN} -qpm -y $((-4 - y_shift)) "${msg}"
	fi
}

# Find LuaJIT binary
find_luajit() {
	for path in \
		"${DASH_DIR}/luajit" \
		/mnt/us/koreader/luajit \
		/usr/bin/luajit; do
		if [ -x "${path}" ]; then
			echo "${path}"
			return 0
		fi
	done
	return 1
}

stop_pillow() {
	if [ "${INIT_TYPE}" != "upstart" ]; then
		return
	fi

	log "Disabling pillow..."
	lipc-set-prop com.lab126.pillow disableEnablePillow disable 2>/dev/null
	PILLOW_DISABLED="yes"
}

start_pillow() {
	if [ "${PILLOW_DISABLED}" = "yes" ]; then
		log "Enabling pillow..."
		lipc-set-prop com.lab126.pillow disableEnablePillow enable 2>/dev/null
		lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home 2>/dev/null
	fi
}

stop_framework() {
	log "Stopping framework..."
	STOP_FRAMEWORK="yes"

	if [ "${INIT_TYPE}" = "sysv" ]; then
		/etc/init.d/framework stop
	else
		# Trap SIGTERM so we don't get killed
		trap "" TERM
		stop lab126_gui 2>/dev/null
		usleep 1250000
		trap - TERM
	fi
}

start_framework() {
	if [ "${STOP_FRAMEWORK}" = "yes" ]; then
		log "Starting framework..."
		if [ "${INIT_TYPE}" = "sysv" ]; then
			/etc/init.d/framework start
		else
			start lab126_gui 2>/dev/null
		fi
	fi
}

stop_services() {
	# Stop background services to free RAM
	if [ "${INIT_TYPE}" = "upstart" ]; then
		for job in ${TOGGLED_SERVICES}; do
			stop "${job}" 2>/dev/null
		done
	fi

	# SIGSTOP volumd to prevent USBMS interference
	if command -v volumd >/dev/null 2>&1 || [ -e /etc/init.d/volumd ] || [ -e /etc/upstart/volumd.conf ]; then
		log "Stopping volumd..."
		killall -STOP volumd 2>/dev/null
		VOLUMD_STOPPED="yes"
	fi

	# SIGSTOP cvm on sysv
	if [ "${INIT_TYPE}" = "sysv" ]; then
		log "Stopping cvm..."
		killall -STOP cvm 2>/dev/null
		CVM_STOPPED="yes"
	fi

	# SIGSTOP awesome on upstart
	if [ "${INIT_TYPE}" = "upstart" ]; then
		log "Stopping awesome..."
		killall -STOP awesome 2>/dev/null
		AWESOME_STOPPED="yes"
	fi
}

resume_services() {
	if [ "${AWESOME_STOPPED}" = "yes" ]; then
		log "Resuming awesome..."
		killall -CONT awesome 2>/dev/null
	fi

	if [ "${CVM_STOPPED}" = "yes" ]; then
		log "Resuming cvm..."
		killall -CONT cvm 2>/dev/null
	fi

	if [ "${VOLUMD_STOPPED}" = "yes" ]; then
		log "Resuming volumd..."
		killall -CONT volumd 2>/dev/null
	fi

	# Restart toggled services
	if [ "${INIT_TYPE}" = "upstart" ]; then
		for job in ${TOGGLED_SERVICES}; do
			start "${job}" 2>/dev/null
		done
	fi
}

cleanup() {
	log "Cleaning up..."
	resume_services
	start_pillow
	start_framework
	log "=== Kindle-Dash finished ==="
	exit 0
}

# Trap signals
trap cleanup EXIT INT TERM HUP

# === Main ===

log "=== Kindle-Dash starting ==="
log "Init type: ${INIT_TYPE}"

# Copy FBInk to tmpfs if available
if [ -x "${DASH_DIR}/fbink" ]; then
	cp -pf "${DASH_DIR}/fbink" /var/tmp/fbink
	chmod 777 /var/tmp/fbink
fi

# Find LuaJIT
LUAJIT=$(find_luajit)
if [ -z "${LUAJIT}" ]; then
	log "Error: LuaJIT not found"
	eips_print_bottom "Error: LuaJIT not found" 0
	exit 1
fi
log "Using LuaJIT: ${LUAJIT}"

# Set up library path
export LD_LIBRARY_PATH="${DASH_DIR}/libs:/mnt/us/koreader/libs:${LD_LIBRARY_PATH}"

# Unlock input devices
[ -e /proc/keypad ] && echo unlock >/proc/keypad
[ -e /proc/fiveway ] && echo unlock >/proc/fiveway

# Stop UI components
stop_pillow
stop_services

eips_print_bottom "Starting Kindle-Dash..." 0

# Run the dash
cd "${DASH_DIR}" || exit 1
log "Running dash.lua..."
"${LUAJIT}" dash.lua >>"${LOGFILE}" 2>&1
RETURN_VALUE=$?
log "dash.lua exited with code ${RETURN_VALUE}"

# cleanup runs via EXIT trap
