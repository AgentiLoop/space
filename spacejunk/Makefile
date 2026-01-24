# Makefile for Space Junk - ARM64 Assembly Game for macOS
#
# Prerequisites:
#   - macOS on Apple Silicon (M1/M2/M3/M4)
#   - Xcode Command Line Tools: xcode-select --install
#
# Usage:
#   make        - Build the game
#   make run    - Build and run
#   make clean  - Remove build artifacts
#   make check  - Verify build dependencies

# Compiler settings
AS = as
LD = ld

# macOS ARM64 settings
ASFLAGS = -arch arm64
LDFLAGS = -arch arm64 -lSystem -syslibroot $(shell xcrun --show-sdk-path) -e _main

# Files
TARGET = spacejunk
SOURCE = spacejunk.s
OBJECT = spacejunk.o

.PHONY: all clean run

all: $(TARGET)

$(TARGET): $(OBJECT)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJECT)

$(OBJECT): $(SOURCE)
	$(AS) $(ASFLAGS) -o $(OBJECT) $(SOURCE)

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET) $(OBJECT)

# Debug build (with symbols)
debug: ASFLAGS += -g
debug: LDFLAGS += -g
debug: clean $(TARGET)

help:
	@echo "Space Junk - ARM64 Assembly Game for macOS"
	@echo ""
	@echo "Usage:"
	@echo "  make       - Build the game"
	@echo "  make run   - Build and run the game"
	@echo "  make clean - Remove build artifacts"
	@echo "  make debug - Build with debug symbols"
	@echo "  make check - Verify build dependencies"
	@echo ""
	@echo "Controls:"
	@echo "  Left/Right Arrow - Turn ship"
	@echo "  Up Arrow         - Reverse thrust (brake)"
	@echo "  Down Arrow       - Forward thrust"
	@echo "  Space            - Fire laser"
	@echo "  Q                - Quit game"

check:
	@echo "Checking build dependencies..."
	@which as > /dev/null 2>&1 || (echo "ERROR: Assembler (as) not found. Run: xcode-select --install" && exit 1)
	@which ld > /dev/null 2>&1 || (echo "ERROR: Linker (ld) not found. Run: xcode-select --install" && exit 1)
	@xcrun --show-sdk-path > /dev/null 2>&1 || (echo "ERROR: SDK not found. Run: xcode-select --install" && exit 1)
	@echo "All dependencies found!"
	@echo "  Assembler: $(shell which as)"
	@echo "  Linker: $(shell which ld)"
	@echo "  SDK: $(shell xcrun --show-sdk-path)"
