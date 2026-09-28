# SPACE

A classic Asteroids-style space shooter written in **pure ARM64 assembly language** for Apple Silicon Macs, using SDL2 for graphics.

## Screenshots

The game features vector-style graphics reminiscent of the original Asteroids arcade game.

## Requirements

- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 11.0 or later
- Xcode Command Line Tools
- Homebrew package manager
- SDL2 and SDL2_gfx libraries

## Installation

### Step 1: Install Homebrew

Homebrew is the package manager for macOS. If you don't have it installed:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installation, follow the instructions to add Homebrew to your PATH. For Apple Silicon Macs, add this to your `~/.zprofile`:

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Then restart your terminal or run:

```bash
source ~/.zprofile
```

Verify Homebrew is installed:

```bash
brew --version
```

### Step 2: Install Xcode Command Line Tools

The assembler and linker are included with Xcode Command Line Tools:

```bash
xcode-select --install
```

A dialog will appear - click "Install" and wait for completion.

### Step 3: Install Dependencies

Install SDL2 and SDL2_gfx using Homebrew:

```bash
brew install sdl2 sdl2_gfx
```

Verify the libraries are installed:

```bash
ls /opt/homebrew/lib/libSDL2*
```

You should see `libSDL2.dylib` and `libSDL2_gfx.dylib`.

## Building

### Compile the game

```bash
make
```

### Clean build artifacts

```bash
make clean
```

### Full rebuild

```bash
make clean && make
```

## Running

### Option 1: Direct execution

```bash
./space
```

### Option 2: Build and run

```bash
make run
```

## How to Play

### Controls

| Key | Action |
|-----|--------|
| **Left Arrow** | Rotate ship counter-clockwise |
| **Right Arrow** | Rotate ship clockwise |
| **Up Arrow** | Forward thrust |
| **Down Arrow** | Reverse thrust (braking) |
| **Space** | Fire bullet |
| **Q** | Quit game |

### Objective

- Destroy all asteroids to advance to the next level
- Avoid colliding with asteroids
- Survive as long as possible and get a high score

### Game Mechanics

**Ship Movement**
- The ship has 8 directional orientations (N, NE, E, SE, S, SW, W, NW)
- Forward thrust accelerates in the direction the ship is facing
- Reverse thrust decelerates or moves backward
- Friction gradually slows the ship when no thrust is applied
- The ship wraps around screen edges (toroidal topology)

**Combat**
- Bullets travel in the direction the ship is facing when fired
- Each destroyed asteroid awards **5 points**
- Bullets have limited lifetime and disappear after traveling a set distance

**Levels**
- Start at Level 1 with 3 asteroids
- Destroying all asteroids advances to the next level
- Each level spawns `level + 2` asteroids
- **Level completion bonus**: 5000 points

**Lives & Scoring**
- Start with **3 lives**
- Colliding with an asteroid costs 1 life
- Ship becomes temporarily invincible (flashing) after respawning
- Game over when all lives are lost

## Project Structure

```
spaces/
├── space.s      # Main ARM64 assembly source code
├── space.o      # Compiled object file (generated)
├── space        # Executable binary (generated)
├── Makefile     # Build configuration
└── README.md    # This file
```

## Technical Details

### Architecture
- Pure **ARM64 assembly** (AArch64)
- No C runtime dependencies beyond system libraries
- Direct SDL2 API calls via dynamic linking

### Graphics
- **VSync-enabled** rendering for smooth 60fps animation
- Vector-style graphics using SDL2 line drawing
- Antialiased lines via SDL2_gfx library (`aalineRGBA`)

### Memory Layout
- Static data section for game state
- Stack-based register preservation following ARM64 ABI
- Callee-saved registers (x19-x28) for persistent state

### Build System
- GNU Make for build automation
- Apple's `as` assembler for ARM64
- Apple's `ld` linker with proper SDK paths

## Troubleshooting

### "Library not found for -lSDL2"

SDL2 is not installed. Install it with:

```bash
brew install sdl2
```

### "Library not found for -lSDL2_gfx"

SDL2_gfx is not installed. Install it with:

```bash
brew install sdl2_gfx
```

### "xcode-select: error: command line tools are not installed"

Install Xcode Command Line Tools:

```bash
xcode-select --install
```

### "brew: command not found"

Homebrew is not installed. See Step 1 in Installation section.

### Game window doesn't appear or crashes immediately

1. Verify SDL2 libraries are in `/opt/homebrew/lib/`:
   ```bash
   ls -la /opt/homebrew/lib/libSDL2*
   ```

2. Try reinstalling SDL2:
   ```bash
   brew reinstall sdl2 sdl2_gfx
   ```

### Linker errors about missing symbols

Verify Xcode Command Line Tools are properly installed:

```bash
xcode-select -p
```

Should output: `/Library/Developer/CommandLineTools`

If not, reinstall:

```bash
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```

## License

This project is provided as-is for educational purposes demonstrating ARM64 assembly programming with SDL2.

## Author

Created with ARM64 assembly on Apple Silicon.

---

**AgentiLoop:** [agentiloop.ai](https://agentiloop.ai/)

Copyright © 2026 AgentiLoop.ai, a Logos InkPen LLC company. All rights reserved.
