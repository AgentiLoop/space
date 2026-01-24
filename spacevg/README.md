# SPACE

A classic Asteroids-style space shooter written in **C** for Apple Silicon Macs, using SDL2 for windowing and NanoVG for smooth antialiased vector graphics.

## Requirements

- Apple Silicon Mac (M1/M2/M3/M4)
- macOS with Xcode Command Line Tools
- Homebrew package manager
- SDL2 library

## Dependencies

| Dependency | Description | Installation |
|------------|-------------|--------------|
| **Xcode CLI Tools** | Apple's compiler and development tools | `xcode-select --install` |
| **Homebrew** | macOS package manager | See installation below |
| **SDL2** | Graphics and input library | `brew install sdl2` |
| **NanoVG** | Vector graphics library | Included in project |

## Installation

### 1. Install Homebrew (if not already installed)

Homebrew is the package manager for macOS. Open Terminal and run:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installation, follow the instructions to add Homebrew to your PATH. Typically:

```bash
echo >> ~/.zprofile
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Verify installation:

```bash
brew --version
```

### 2. Install Xcode Command Line Tools

```bash
xcode-select --install
```

### 3. Install SDL2

```bash
brew install sdl2
```

## Compiling

### Build the game

```bash
make
```

### Build and run

```bash
make run
```

### Clean build artifacts

```bash
make clean
```

### Full rebuild

```bash
make clean && make
```

### Show build help

```bash
make help
```

## Playing

### Start the game

```bash
./space
```

### Controls

| Key | Action |
|-----|--------|
| **Left Arrow** | Rotate ship counter-clockwise |
| **Right Arrow** | Rotate ship clockwise |
| **Up Arrow** | Forward thrust |
| **Down Arrow** | Reverse thrust (braking) |
| **Space** | Fire bullet |
| **Q** | Quit game |

### Game Screens

1. **Start Screen** - Press SPACE to begin
2. **Playing** - Destroy asteroids, survive, score points
3. **Game Over** - Press SPACE to restart

## Game Mechanics

### Ship Movement
- The ship has 8 directional orientations (N, NE, E, SE, S, SW, W, NW)
- **Forward thrust** accelerates the ship in the direction it's facing
- **Reverse thrust** decelerates or moves backward
- **Friction** gradually slows the ship when no thrust is applied
- The ship wraps around screen edges

### Combat
- Bullets travel in the direction the ship is facing when fired
- Each destroyed asteroid awards **5 points**
- Bullets have limited lifetime

### Levels
- Start at **Level 1** with 3 asteroids
- Destroying all asteroids advances to the next level
- Each level spawns `level + 2` asteroids
- **5000 bonus points** for completing a level

### Lives & Scoring
- Start with **3 lives**
- Colliding with an asteroid costs 1 life
- Ship becomes temporarily invincible (flashing) after respawning
- Game over when all lives are lost

## Technical Details

### Architecture
- Written in **C** for performance and simplicity
- Uses **SDL2** for window management, OpenGL context, and input
- Uses **NanoVG** for smooth antialiased vector graphics
- **OpenGL 3.2 Core Profile** rendering

### Graphics
- **VSync-enabled** rendering for smooth 60fps animation
- Antialiased vector lines via NanoVG
- Retro-style vector digit rendering for HUD

### Project Structure

```
spacevg/
├── space.c         # Main game source code
├── nanovg/         # NanoVG library (included)
│   └── src/
│       ├── nanovg.c
│       ├── nanovg.h
│       └── nanovg_gl.h
├── Makefile        # Build configuration
├── space           # Executable (generated)
└── README.md       # This file
```

## Troubleshooting

### "Library not found for -lSDL2"

Make sure SDL2 is installed via Homebrew:

```bash
brew install sdl2
```

### "Command not found: brew"

Install Homebrew first (see Installation section above).

### "xcrun: error: invalid active developer path"

Install Xcode Command Line Tools:

```bash
xcode-select --install
```

### Game window doesn't appear

Ensure your Mac supports OpenGL 3.2. All Apple Silicon Macs support this.

## License

This project is provided as-is for educational purposes.
