# Makefile for SPACE - ARM64 Assembly Game with SDL2
# A classic Asteroids-style game written in pure ARM64 assembly

# Tools
AS = as
LD = ld

# Paths (Homebrew on Apple Silicon)
SDL_PATH = /opt/homebrew/lib
SDL_INCLUDE = /opt/homebrew/include

# Flags
ASFLAGS = -arch arm64
LDFLAGS = -arch arm64 -lSystem \
          -L$(SDL_PATH) -lSDL2 -lSDL2_gfx \
          -syslibroot $(shell xcrun --show-sdk-path) \
          -e _main

# Target and sources
TARGET = space
SOURCE = space.s
OBJECT = space.o

# Default target
.PHONY: all clean run

all: $(TARGET)

# Link executable
$(TARGET): $(OBJECT)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJECT)

# Assemble source
$(OBJECT): $(SOURCE)
	$(AS) $(ASFLAGS) -o $(OBJECT) $(SOURCE)

# Build and run
run: $(TARGET)
	./$(TARGET)

# Clean build artifacts
clean:
	rm -f $(TARGET) $(OBJECT)
