# Kindle-Dash Makefile
# Creates a package ready to copy to Kindle

DIST_DIR = dist
KINDLE_DASH_DIR = $(DIST_DIR)/kindle-dash
EXTENSIONS_DIR = $(DIST_DIR)/extensions/kindle-dash

# Core files to install
DASH_FILES = dash.lua dash.sh setupkoenv.lua
FFI_FILES = $(wildcard ffi/*.lua)
LIB_FILES = $(wildcard libs/*.so)

.PHONY: all clean install-package

all: install-package

install-package: clean
	@echo "Creating Kindle installation package..."
	@mkdir -p $(KINDLE_DASH_DIR)
	@mkdir -p $(KINDLE_DASH_DIR)/ffi
	@mkdir -p $(EXTENSIONS_DIR)
	@# Main dash files
	@cp $(DASH_FILES) $(KINDLE_DASH_DIR)/
	@chmod +x $(KINDLE_DASH_DIR)/dash.sh
	@# FFI modules
	@cp $(FFI_FILES) $(KINDLE_DASH_DIR)/ffi/
	@# Native libraries
	@if [ -n "$(LIB_FILES)" ]; then mkdir -p $(KINDLE_DASH_DIR)/libs && cp $(LIB_FILES) $(KINDLE_DASH_DIR)/libs/; fi
	@# KUAL extension
	@cp kual/config.xml kual/menu.json $(EXTENSIONS_DIR)/
	@echo ""
	@echo "=== Package created in $(DIST_DIR)/ ==="
	@echo ""
	@echo "To install on Kindle:"
	@echo "  1. Connect Kindle via USB"
	@echo "  2. Copy contents of $(DIST_DIR)/ to Kindle root:"
	@echo "       cp -r $(DIST_DIR)/* /media/Kindle/"
	@echo "     Or on Mac:"
	@echo "       cp -r $(DIST_DIR)/* /Volumes/Kindle/"
	@echo "  3. Eject Kindle"
	@echo "  4. Launch from KUAL menu"
	@echo ""

clean:
	rm -rf $(DIST_DIR)
