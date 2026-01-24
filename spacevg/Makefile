# Makefile for SPACE - C with SDL2 + NanoVG
# A classic asteroids-style game with smooth vector graphics

CC = cc

# Homebrew paths (Apple Silicon)
SDL_PATH = /opt/homebrew/lib
SDL_INCLUDE = /opt/homebrew/include
NANOVG_PATH = nanovg/src

# Compiler and linker flags
CFLAGS = -arch arm64 -O2 -I. -I$(SDL_INCLUDE) -I$(NANOVG_PATH) -DGL_SILENCE_DEPRECATION
LDFLAGS = -arch arm64 -L$(SDL_PATH) -lSDL2 -framework OpenGL

# Target and sources
TARGET = space
SOURCES = space.c
NANOVG_SRC = $(NANOVG_PATH)/nanovg.c

.PHONY: all clean run help

# Default target
all: $(TARGET)

# Build the game
$(TARGET): $(SOURCES) $(NANOVG_SRC)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $(TARGET) $(SOURCES) $(NANOVG_SRC)

# Build and run
run: $(TARGET)
	./$(TARGET)

# Clean build artifacts
clean:
	rm -f $(TARGET) *.o

# Show help
help:
	@echo "SPACE Game - Build Commands"
	@echo "============================"
	@echo "  make        - Build the game"
	@echo "  make run    - Build and run the game"
	@echo "  make clean  - Remove build artifacts"
	@echo "  make help   - Show this help message"
	@echo ""
	@echo "Dependencies: SDL2 (install via: brew install sdl2)"
