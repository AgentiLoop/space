# Space Junk

An ARM64 assembly game for macOS Apple Silicon.

## Prerequisites

### Install Homebrew (optional but recommended)

Homebrew is a package manager for macOS. Install it by running:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

After installation, follow the on-screen instructions to add Homebrew to your PATH.

### Install Xcode Command Line Tools (required)

The game requires the assembler (`as`) and linker (`ld`) from Apple's developer tools:

```bash
xcode-select --install
```

This will prompt you to install the Command Line Tools. Click "Install" to proceed.

## Dependencies

- **macOS** on Apple Silicon (M1/M2/M3/M4)
- **Xcode Command Line Tools** - provides the ARM64 assembler and linker

## Building

Clone the repository and build the game:

```bash
make
```

Other build options:

```bash
make clean    # Remove build artifacts
make debug    # Build with debug symbols
make help     # Show all available commands
```

## Running

After building, run the game:

```bash
make run
```

Or run directly:

```bash
./spacejunk
```

## How to Play

### Controls

| Key | Action |
|-----|--------|
| Left Arrow | Turn ship left |
| Right Arrow | Turn ship right |
| Up Arrow | Reverse thrust (brake) |
| Down Arrow | Forward thrust |
| Space | Fire laser |
| Q | Quit game |

### Objective

Navigate your ship through space, avoid obstacles, and destroy space junk with your laser.

## Troubleshooting

### "xcrun: error: invalid active developer path"

Run `xcode-select --install` to install the Command Line Tools.

### Build fails on Intel Mac

This game is written in ARM64 assembly and only runs on Apple Silicon Macs (M1/M2/M3/M4).
