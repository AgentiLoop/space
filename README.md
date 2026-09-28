# Space - Asteroids Game Collection

A collection of three classic Asteroids-style space shooter games, each implemented using different technologies. All projects in this repo target **macOS on Apple Silicon** (M1/M2/M3/M4/M5) and were developed with Claude Code.

For a complete HD Asteroids remake written in Swift using SpriteKit for macOS (Intel and ARM64), see [AsteroidZ](https://github.com/superbox64/AsteroidZ).



## Projects

### 1. spacejunk - Terminal-Based ARM64 Assembly

A minimalist space game running entirely in the terminal using ASCII graphics.

- **Language:** ARM64 Assembly (1,927 lines)
- **Graphics:** Terminal output (80x24 character grid)
- **Dependencies:** Xcode Command Line Tools only

### 2. spaces - ARM64 Assembly with SDL2

A full-featured Asteroids game written in pure ARM64 assembly with hardware-accelerated 2D graphics.

- **Language:** ARM64 Assembly (2,163 lines)
- **Graphics:** SDL2 + SDL2_gfx (800x480 resolution)
- **Dependencies:** Xcode Command Line Tools, Homebrew, SDL2, SDL2_gfx

### 3. spacevg - C with NanoVG Vector Graphics

A polished implementation using C and NanoVG for smooth, antialiased vector graphics via OpenGL.

- **Language:** C (740 lines)
- **Graphics:** SDL2 + NanoVG + OpenGL 3.2 Core Profile (800x480 resolution)
- **Dependencies:** Xcode Command Line Tools, Homebrew, SDL2

## Comparison

| Feature | spacejunk | spaces | spacevg |
|---------|-----------|--------|---------|
| Language | ARM64 Assembly | ARM64 Assembly | C |
| Graphics | Terminal ASCII | SDL2 + SDL2_gfx | SDL2 + NanoVG |
| Rendering | Text-based | Software 2D | OpenGL 3.2 |
| Graphics Quality | Basic | Block graphics | Smooth vectors |

## Common Features

All three games share core gameplay mechanics:

- 8-directional ship movement and rotation
- Laser firing to destroy asteroids
- Lives system (start with 3)
- Scoring with level completion bonuses
- Progressive difficulty (more asteroids per level)

## Controls

| Key | Action |
|-----|--------|
| Arrow Keys | Rotate / Thrust |
| Space | Fire laser |
| Q | Quit game |

## Building

Each project includes a Makefile. Navigate to the project directory and run:

```bash
make
```

To run the game:

```bash
./spacejunk   # Terminal version
./space       # SDL2 versions (spaces and spacevg)
```

## Requirements

- macOS on Apple Silicon (M1/M2/M3/M4/M5)
- Xcode Command Line Tools
- Homebrew (for SDL2 projects)
- SDL2 and SDL2_gfx (for spaces project)
- SDL2 (for spacevg project)

## Purpose

This collection demonstrates different approaches to game development:

- **spacejunk:** Pure low-level assembly programming with terminal I/O
- **spaces:** Assembly programming with external graphics libraries
- **spacevg:** Modern C with vector graphics and OpenGL

All three implement the same game, showcasing how the same logic can be expressed across different abstraction levels.

---

*Built with Claude Code*

---

**AgentiLoop:** [agentiloop.ai](https://agentiloop.ai/)

Copyright © 2026 AgentiLoop.ai, a Logos InkPen LLC company. All rights reserved.
