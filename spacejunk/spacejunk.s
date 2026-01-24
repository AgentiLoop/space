//==============================================================================
// SPACE JUNK - A Vector Space Game in ARM64 Assembly for macOS
// Navigate through space, avoid obstacles, and survive!
//
// Controls:
//   Left/Right Arrow - Turn ship
//   Up Arrow        - Reverse thrust
//   Down Arrow      - Forward thrust
//   Space           - Fire laser
//   Q               - Quit
//==============================================================================

.global _main
.align 4

//==============================================================================
// Constants
//==============================================================================
.equ SCREEN_WIDTH,      80
.equ SCREEN_HEIGHT,     24
.equ MAX_OBSTACLES,     40
.equ MAX_BULLETS,       10
.equ MAX_STARS,         40
.equ SHIP_CHAR,         0x41        // 'A' shape for ship
.equ BULLET_CHAR,       0x2A        // '*'
.equ OBSTACLE_CHARS,    6           // Number of obstacle types

// System calls
.equ SYS_EXIT,          1
.equ SYS_READ,          3
.equ SYS_WRITE,         4
.equ SYS_FCNTL,         92
.equ SYS_SELECT,        93
.equ SYS_IOCTL,         54
.equ SYS_GETTIMEOFDAY,  116

// File descriptors
.equ STDIN,             0
.equ STDOUT,            1

// fcntl constants
.equ F_GETFL,           3
.equ F_SETFL,           4
.equ O_NONBLOCK,        0x0004

// termios ioctl
.equ TIOCGETA,          0x40487413
.equ TIOCSETA,          0x80487414

//==============================================================================
// Data Section
//==============================================================================
.data

// Terminal settings storage
.align 4
old_termios:    .space 64
new_termios:    .space 64
old_flags:      .quad 0

// Screen buffer (80x24 = 1920 bytes + extra)
.align 4
screen_buffer:  .space 2048

// Game state
.align 4
ship_x:         .quad 40            // Ship X position (fixed point 8.8)
ship_y:         .quad 12            // Ship Y position (fixed point 8.8)
ship_vx:        .quad 0             // Ship velocity X
ship_vy:        .quad 0             // Ship velocity Y
ship_angle:     .quad 0             // Ship angle (0-7, 8 directions)
ship_alive:     .quad 1             // Ship alive flag
score:          .quad 0             // Player score
level:          .quad 1             // Current level
lives:          .quad 3             // Lives remaining
game_running:   .quad 1             // Game loop flag
frame_count:    .quad 0             // Frame counter
fire_cooldown:  .quad 0             // Cooldown timer for firing
turn_cooldown:  .quad 0             // Cooldown timer for turning
space_this_frame: .quad 0           // Was space pressed this frame

// Obstacles array: x, y, vx, vy, type, active (6 quads each)
.align 4
obstacles:      .space 1920         // 40 obstacles * 48 bytes

// Bullets array: x, y, vx, vy, active (5 quads each)
.align 4
bullets:        .space 400          // 10 bullets * 40 bytes

// Stars array: x, y (2 quads each)
.align 4
stars:          .space 640          // 40 stars * 16 bytes

// Random seed
random_seed:    .quad 0x12345678

// Direction vectors (8 directions, cos/sin approximations)
.align 4
dir_x:          .quad 0, 1, 1, 1, 0, -1, -1, -1      // dx for each direction
dir_y:          .quad -1, -1, 0, 1, 1, 1, 0, -1     // dy for each direction

// Ship graphics for each direction (8 directions)
ship_chars:     .byte '^', '/', '>', '\\', 'v', '/', '<', '\\'
                .align 4

// Obstacle characters
obstacle_types: .byte 'O', 'o', '@', '*', '#', '.'    // Rock, small rock, planet, star, debris, dust
                .align 4

// Obstacle names for display
obs_name_0:     .asciz "ASTEROID"
obs_name_1:     .asciz "SPACE ROCK"
obs_name_2:     .asciz "PLANET"
obs_name_3:     .asciz "SUN"
obs_name_4:     .asciz "DEBRIS"
obs_name_5:     .asciz "DUST"

// ANSI escape sequences
.align 4
esc_clear:      .asciz "\033[2J"
esc_home:       .asciz "\033[H"
esc_hide_cur:   .asciz "\033[?25l"
esc_show_cur:   .asciz "\033[?25h"
esc_bold:       .asciz "\033[1m"
esc_reset:      .asciz "\033[0m"
esc_red:        .asciz "\033[31m"
esc_green:      .asciz "\033[32m"
esc_yellow:     .asciz "\033[33m"
esc_blue:       .asciz "\033[34m"
esc_magenta:    .asciz "\033[35m"
esc_cyan:       .asciz "\033[36m"
esc_white:      .asciz "\033[37m"

// Position cursor escape (template)
esc_pos:        .asciz "\033[00;00H"
pos_buffer:     .space 16

// Game messages
.align 4
title_msg:      .asciz "=== SPACE JUNK ==="
score_msg:      .asciz "SCORE:"
lives_msg:      .asciz "LIVES:"
level_msg:      .asciz "LEVEL:"
controls_msg:   .asciz "[Arrows:Move] [SPACE:Fire] [Q:Quit]"
gameover_msg:   .asciz ">>> GAME OVER <<<"
restart_msg:    .asciz "Press R to restart, Q to quit"
paused_msg:     .asciz "=== PAUSED ==="

// Number to string buffer
num_buffer:     .space 16

// Input buffer
input_buffer:   .space 8
input_seq:      .space 8

// Timeval structure for usleep
.align 4
timeval:        .quad 0, 0

// Newline
newline:        .asciz "\n"

//==============================================================================
// Text Section
//==============================================================================
.text

//------------------------------------------------------------------------------
// Main entry point
//------------------------------------------------------------------------------
_main:
    // Save frame pointer
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Initialize terminal (raw mode, non-blocking)
    bl      _init_terminal

    // Initialize game
    bl      _init_game

    // Main game loop
_game_loop:
    // Check if game should continue
    adrp    x0, game_running@PAGE
    ldr     x0, [x0, #:lo12:game_running@PAGEOFF]
    cbz     x0, _game_exit

    // Process input
    bl      _process_input

    // Check if game should continue after input
    adrp    x0, game_running@PAGE
    ldr     x0, [x0, #:lo12:game_running@PAGEOFF]
    cbz     x0, _game_exit

    // Update game state
    bl      _update_game

    // Render frame
    bl      _render_frame

    // Delay (roughly 60fps = ~16ms)
    mov     x0, #16000          // 16ms in microseconds
    bl      _usleep

    // Increment frame counter
    adrp    x8, frame_count@PAGE
    add     x8, x8, #:lo12:frame_count@PAGEOFF
    ldr     x0, [x8]
    add     x0, x0, #1
    str     x0, [x8]

    b       _game_loop

_game_exit:
    // Restore terminal
    bl      _restore_terminal

    // Exit with code 0
    mov     x0, #0
    mov     x16, #SYS_EXIT
    svc     #0x80

//------------------------------------------------------------------------------
// Initialize terminal for raw input
//------------------------------------------------------------------------------
_init_terminal:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Hide cursor
    adrp    x0, esc_hide_cur@PAGE
    add     x0, x0, #:lo12:esc_hide_cur@PAGEOFF
    bl      _print_string

    // Clear screen
    adrp    x0, esc_clear@PAGE
    add     x0, x0, #:lo12:esc_clear@PAGEOFF
    bl      _print_string

    // Get current terminal settings
    mov     x0, #STDIN
    movz    x1, #0x7413
    movk    x1, #0x4048, lsl #16    // TIOCGETA = 0x40487413
    adrp    x2, old_termios@PAGE
    add     x2, x2, #:lo12:old_termios@PAGEOFF
    mov     x16, #SYS_IOCTL
    svc     #0x80

    // Copy to new_termios
    adrp    x0, old_termios@PAGE
    add     x0, x0, #:lo12:old_termios@PAGEOFF
    adrp    x1, new_termios@PAGE
    add     x1, x1, #:lo12:new_termios@PAGEOFF
    mov     x2, #64
_copy_termios:
    ldrb    w3, [x0], #1
    strb    w3, [x1], #1
    subs    x2, x2, #1
    bne     _copy_termios

    // Modify for raw mode (disable ICANON and ECHO in lflag at offset 24 on 64-bit)
    adrp    x1, new_termios@PAGE
    add     x1, x1, #:lo12:new_termios@PAGEOFF
    ldr     x0, [x1, #24]           // c_lflag (64-bit on macOS)
    mov     x2, #0x0008             // ECHO
    orr     x2, x2, #0x0100         // ICANON
    orr     x2, x2, #0x0002         // IEXTEN
    bic     x0, x0, x2              // Clear ECHO, ICANON, IEXTEN
    str     x0, [x1, #24]

    // Set VMIN=0, VTIME=0 for non-blocking (c_cc array at offset 32)
    // VMIN is index 16, VTIME is index 17
    strb    wzr, [x1, #48]          // VMIN = 0 (offset 32 + 16)
    strb    wzr, [x1, #49]          // VTIME = 0 (offset 32 + 17)

    // Apply new settings
    mov     x0, #STDIN
    movz    x1, #0x7414
    movk    x1, #0x8048, lsl #16    // TIOCSETA = 0x80487414
    adrp    x2, new_termios@PAGE
    add     x2, x2, #:lo12:new_termios@PAGEOFF
    mov     x16, #SYS_IOCTL
    svc     #0x80

    // Set stdin to non-blocking
    mov     x0, #STDIN
    mov     x1, #F_GETFL
    mov     x2, #0
    mov     x16, #SYS_FCNTL
    svc     #0x80

    // Save old flags
    adrp    x1, old_flags@PAGE
    str     x0, [x1, #:lo12:old_flags@PAGEOFF]

    // Set non-blocking
    orr     x2, x0, #O_NONBLOCK
    mov     x0, #STDIN
    mov     x1, #F_SETFL
    mov     x16, #SYS_FCNTL
    svc     #0x80

    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Restore terminal settings
//------------------------------------------------------------------------------
_restore_terminal:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Restore terminal settings
    mov     x0, #STDIN
    movz    x1, #0x7414
    movk    x1, #0x8048, lsl #16    // TIOCSETA = 0x80487414
    adrp    x2, old_termios@PAGE
    add     x2, x2, #:lo12:old_termios@PAGEOFF
    mov     x16, #SYS_IOCTL
    svc     #0x80

    // Restore blocking mode
    mov     x0, #STDIN
    mov     x1, #F_SETFL
    adrp    x2, old_flags@PAGE
    ldr     x2, [x2, #:lo12:old_flags@PAGEOFF]
    mov     x16, #SYS_FCNTL
    svc     #0x80

    // Show cursor
    adrp    x0, esc_show_cur@PAGE
    add     x0, x0, #:lo12:esc_show_cur@PAGEOFF
    bl      _print_string

    // Clear screen
    adrp    x0, esc_clear@PAGE
    add     x0, x0, #:lo12:esc_clear@PAGEOFF
    bl      _print_string

    // Home cursor
    adrp    x0, esc_home@PAGE
    add     x0, x0, #:lo12:esc_home@PAGEOFF
    bl      _print_string

    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Initialize game state
//------------------------------------------------------------------------------
_init_game:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Reset ship position to center
    adrp    x8, ship_x@PAGE
    add     x8, x8, #:lo12:ship_x@PAGEOFF
    mov     x0, #40
    lsl     x0, x0, #8              // Fixed point 8.8
    str     x0, [x8]

    adrp    x8, ship_y@PAGE
    add     x8, x8, #:lo12:ship_y@PAGEOFF
    mov     x0, #12
    lsl     x0, x0, #8
    str     x0, [x8]

    // Reset velocities
    adrp    x8, ship_vx@PAGE
    str     xzr, [x8, #:lo12:ship_vx@PAGEOFF]
    adrp    x8, ship_vy@PAGE
    str     xzr, [x8, #:lo12:ship_vy@PAGEOFF]

    // Reset angle (pointing up)
    adrp    x8, ship_angle@PAGE
    str     xzr, [x8, #:lo12:ship_angle@PAGEOFF]

    // Ship is alive
    adrp    x8, ship_alive@PAGE
    mov     x0, #1
    str     x0, [x8, #:lo12:ship_alive@PAGEOFF]

    // Initialize random seed with a value
    adrp    x8, random_seed@PAGE
    add     x8, x8, #:lo12:random_seed@PAGEOFF
    mov     x0, #0x5678
    movk    x0, #0x1234, lsl #16
    str     x0, [x8]

    // Initialize stars
    bl      _init_stars

    // Initialize obstacles
    bl      _init_obstacles

    // Clear bullets
    bl      _clear_bullets

    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Initialize background stars
//------------------------------------------------------------------------------
_init_stars:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!

    adrp    x19, stars@PAGE
    add     x19, x19, #:lo12:stars@PAGEOFF
    mov     x20, #MAX_STARS

_init_stars_loop:
    // Random X position
    bl      _random
    mov     x1, #SCREEN_WIDTH
    udiv    x2, x0, x1
    msub    x0, x2, x1, x0          // x0 = x0 % SCREEN_WIDTH
    str     x0, [x19], #8

    // Random Y position
    bl      _random
    mov     x1, #SCREEN_HEIGHT
    udiv    x2, x0, x1
    msub    x0, x2, x1, x0          // x0 = x0 % SCREEN_HEIGHT
    str     x0, [x19], #8

    subs    x20, x20, #1
    bne     _init_stars_loop

    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Initialize obstacles
//------------------------------------------------------------------------------
_init_obstacles:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!

    adrp    x19, obstacles@PAGE
    add     x19, x19, #:lo12:obstacles@PAGEOFF

    // Get current level for obstacle count
    adrp    x8, level@PAGE
    ldr     x21, [x8, #:lo12:level@PAGEOFF]

    // Number of obstacles = 12 + level*2 (max 30)
    lsl     x20, x21, #1            // level * 2
    add     x20, x20, #12           // + 12
    mov     x1, #30
    cmp     x20, x1
    csel    x20, x1, x20, gt        // min(count, 30)
    mov     x22, x20                // Save active count

    mov     x21, #MAX_OBSTACLES

_init_obs_loop:
    cbz     x21, _init_obs_done

    // Check if this obstacle should be active
    cmp     x22, #0
    beq     _init_obs_inactive
    sub     x22, x22, #1

    // Random X position (avoid center - ship starts at 40,12)
    bl      _random
    mov     x1, #SCREEN_WIDTH
    udiv    x2, x0, x1
    msub    x0, x2, x1, x0
    // If within 15 units of center (40), push to edges
    cmp     x0, #25
    blt     _obs_x_ok
    cmp     x0, #55
    bgt     _obs_x_ok
    // Push to edge
    cmp     x0, #40
    blt     _obs_x_low
    add     x0, x0, #25             // Push right
    cmp     x0, #SCREEN_WIDTH
    blt     _obs_x_ok
    sub     x0, x0, #SCREEN_WIDTH
    b       _obs_x_ok
_obs_x_low:
    sub     x0, x0, #15             // Push left
    cmp     x0, #0
    bge     _obs_x_ok
    add     x0, x0, #SCREEN_WIDTH
_obs_x_ok:
    lsl     x0, x0, #8              // Fixed point
    str     x0, [x19], #8           // Store X

    // Random Y position (avoid center - ship at Y=12)
    bl      _random
    mov     x1, #SCREEN_HEIGHT
    udiv    x2, x0, x1
    msub    x0, x2, x1, x0
    cmp     x0, #7
    blt     _obs_y_ok
    cmp     x0, #17
    bgt     _obs_y_ok
    // Push away from center
    cmp     x0, #12
    blt     _obs_y_low
    add     x0, x0, #8
    cmp     x0, #SCREEN_HEIGHT
    blt     _obs_y_ok
    sub     x0, x0, #SCREEN_HEIGHT
    b       _obs_y_ok
_obs_y_low:
    sub     x0, x0, #5
    cmp     x0, #0
    bge     _obs_y_ok
    add     x0, x0, #SCREEN_HEIGHT
_obs_y_ok:
    lsl     x0, x0, #8
    str     x0, [x19], #8           // Store Y

    // Random velocity X (-2 to 2)
    bl      _random
    and     x0, x0, #0x7
    sub     x0, x0, #3
    str     x0, [x19], #8           // Store VX

    // Random velocity Y (-2 to 2)
    bl      _random
    and     x0, x0, #0x7
    sub     x0, x0, #3
    str     x0, [x19], #8           // Store VY

    // Random type (0-5)
    bl      _random
    and     x0, x0, #0x7
    cmp     x0, #6
    blt     _obs_type_ok
    sub     x0, x0, #6
_obs_type_ok:
    str     x0, [x19], #8           // Store type

    // Active = 1
    mov     x0, #1
    str     x0, [x19], #8           // Store active

    sub     x21, x21, #1
    b       _init_obs_loop

_init_obs_inactive:
    // Clear this obstacle
    str     xzr, [x19], #8          // X
    str     xzr, [x19], #8          // Y
    str     xzr, [x19], #8          // VX
    str     xzr, [x19], #8          // VY
    str     xzr, [x19], #8          // Type
    str     xzr, [x19], #8          // Active = 0

    sub     x21, x21, #1
    b       _init_obs_loop

_init_obs_done:
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Clear all bullets
//------------------------------------------------------------------------------
_clear_bullets:
    adrp    x0, bullets@PAGE
    add     x0, x0, #:lo12:bullets@PAGEOFF
    mov     x1, #MAX_BULLETS

_clear_bullets_loop:
    str     xzr, [x0], #8           // X
    str     xzr, [x0], #8           // Y
    str     xzr, [x0], #8           // VX
    str     xzr, [x0], #8           // VY
    str     xzr, [x0], #8           // Active
    subs    x1, x1, #1
    bne     _clear_bullets_loop
    ret

//------------------------------------------------------------------------------
// Simple pseudo-random number generator (LCG)
//------------------------------------------------------------------------------
_random:
    adrp    x8, random_seed@PAGE
    add     x8, x8, #:lo12:random_seed@PAGEOFF
    ldr     x0, [x8]

    // LCG: seed = seed * 1103515245 + 12345
    mov     x1, #0x5245
    movk    x1, #0x1051, lsl #16
    movk    x1, #0x4, lsl #32
    mul     x0, x0, x1
    mov     x2, #12345
    add     x0, x0, x2

    str     x0, [x8]
    lsr     x0, x0, #16             // Return upper bits for better randomness
    ret

//------------------------------------------------------------------------------
// Process keyboard input
//------------------------------------------------------------------------------
_process_input:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Clear space flag for this frame
    adrp    x8, space_this_frame@PAGE
    str     xzr, [x8, #:lo12:space_this_frame@PAGEOFF]

    // Try to read a character
    mov     x0, #STDIN
    adrp    x1, input_buffer@PAGE
    add     x1, x1, #:lo12:input_buffer@PAGEOFF
    mov     x2, #1
    mov     x16, #SYS_READ
    svc     #0x80

    // Check if we got input
    cmp     x0, #1
    blt     _input_check_fire

    // Get the character
    adrp    x1, input_buffer@PAGE
    ldrb    w0, [x1, #:lo12:input_buffer@PAGEOFF]

    // Check for escape sequence (arrow keys)
    cmp     w0, #27                 // ESC
    beq     _handle_escape

    // Check for 'q' or 'Q' to quit
    cmp     w0, #'q'
    beq     _handle_quit
    cmp     w0, #'Q'
    beq     _handle_quit

    // Check for space - mark it for this frame
    cmp     w0, #' '
    bne     _input_check_fire

    // Mark that space was pressed this frame
    adrp    x8, space_this_frame@PAGE
    mov     x1, #1
    str     x1, [x8, #:lo12:space_this_frame@PAGEOFF]

_input_check_fire:
    // Check if space was pressed this frame
    adrp    x8, space_this_frame@PAGE
    ldr     x0, [x8, #:lo12:space_this_frame@PAGEOFF]
    cbz     x0, _input_done         // Space not pressed, don't fire

    // Check cooldown
    adrp    x8, fire_cooldown@PAGE
    add     x8, x8, #:lo12:fire_cooldown@PAGEOFF
    ldr     x0, [x8]
    cbnz    x0, _input_done         // Still on cooldown

    // Set cooldown (15 frames)
    mov     x0, #15
    str     x0, [x8]

    bl      _fire_bullet
    b       _input_done

_handle_escape:
    // Read next character (should be '[')
    mov     x0, #STDIN
    adrp    x1, input_buffer@PAGE
    add     x1, x1, #:lo12:input_buffer@PAGEOFF
    mov     x2, #1
    mov     x16, #SYS_READ
    svc     #0x80
    cmp     x0, #1
    blt     _input_check_fire

    // Read direction character
    mov     x0, #STDIN
    adrp    x1, input_buffer@PAGE
    add     x1, x1, #:lo12:input_buffer@PAGEOFF
    mov     x2, #1
    mov     x16, #SYS_READ
    svc     #0x80
    cmp     x0, #1
    blt     _input_check_fire

    adrp    x1, input_buffer@PAGE
    ldrb    w0, [x1, #:lo12:input_buffer@PAGEOFF]

    // 'A' = Up (reverse thrust)
    cmp     w0, #'A'
    beq     _handle_thrust_reverse

    // 'B' = Down (forward thrust)
    cmp     w0, #'B'
    beq     _handle_thrust_forward

    // 'C' = Right (turn right)
    cmp     w0, #'C'
    beq     _handle_turn_right

    // 'D' = Left (turn left)
    cmp     w0, #'D'
    beq     _handle_turn_left

    b       _input_check_fire

_handle_turn_left:
    // Check turn cooldown
    adrp    x9, turn_cooldown@PAGE
    add     x9, x9, #:lo12:turn_cooldown@PAGEOFF
    ldr     x1, [x9]
    cbnz    x1, _input_check_fire   // Still on cooldown

    // Set cooldown (8 frames)
    mov     x1, #8
    str     x1, [x9]

    adrp    x8, ship_angle@PAGE
    add     x8, x8, #:lo12:ship_angle@PAGEOFF
    ldr     x0, [x8]
    sub     x0, x0, #1
    and     x0, x0, #7              // Wrap 0-7
    str     x0, [x8]
    b       _input_check_fire

_handle_turn_right:
    // Check turn cooldown
    adrp    x9, turn_cooldown@PAGE
    add     x9, x9, #:lo12:turn_cooldown@PAGEOFF
    ldr     x1, [x9]
    cbnz    x1, _input_check_fire   // Still on cooldown

    // Set cooldown (8 frames)
    mov     x1, #8
    str     x1, [x9]

    adrp    x8, ship_angle@PAGE
    add     x8, x8, #:lo12:ship_angle@PAGEOFF
    ldr     x0, [x8]
    add     x0, x0, #1
    and     x0, x0, #7              // Wrap 0-7
    str     x0, [x8]
    b       _input_check_fire

_handle_thrust_forward:
    // Add velocity in ship's direction
    adrp    x8, ship_angle@PAGE
    ldr     x0, [x8, #:lo12:ship_angle@PAGEOFF]

    // Get direction vector
    adrp    x9, dir_x@PAGE
    add     x9, x9, #:lo12:dir_x@PAGEOFF
    ldr     x1, [x9, x0, lsl #3]    // dx

    adrp    x9, dir_y@PAGE
    add     x9, x9, #:lo12:dir_y@PAGEOFF
    ldr     x2, [x9, x0, lsl #3]    // dy

    // Apply thrust (scale by 32 for fixed point - moderate thrust)
    lsl     x1, x1, #5
    lsl     x2, x2, #5

    // Update velocity
    adrp    x8, ship_vx@PAGE
    add     x8, x8, #:lo12:ship_vx@PAGEOFF
    ldr     x0, [x8]
    add     x0, x0, x1
    // Clamp velocity
    mov     x3, #128
    cmp     x0, x3
    csel    x0, x3, x0, gt
    neg     x3, x3
    cmp     x0, x3
    csel    x0, x3, x0, lt
    str     x0, [x8]

    adrp    x8, ship_vy@PAGE
    add     x8, x8, #:lo12:ship_vy@PAGEOFF
    ldr     x0, [x8]
    add     x0, x0, x2
    mov     x3, #128
    cmp     x0, x3
    csel    x0, x3, x0, gt
    neg     x3, x3
    cmp     x0, x3
    csel    x0, x3, x0, lt
    str     x0, [x8]

    b       _input_check_fire

_handle_thrust_reverse:
    // Subtract velocity (reverse thrust)
    adrp    x8, ship_angle@PAGE
    ldr     x0, [x8, #:lo12:ship_angle@PAGEOFF]

    adrp    x9, dir_x@PAGE
    add     x9, x9, #:lo12:dir_x@PAGEOFF
    ldr     x1, [x9, x0, lsl #3]

    adrp    x9, dir_y@PAGE
    add     x9, x9, #:lo12:dir_y@PAGEOFF
    ldr     x2, [x9, x0, lsl #3]

    lsl     x1, x1, #5
    lsl     x2, x2, #5

    adrp    x8, ship_vx@PAGE
    add     x8, x8, #:lo12:ship_vx@PAGEOFF
    ldr     x0, [x8]
    sub     x0, x0, x1
    mov     x3, #128
    cmp     x0, x3
    csel    x0, x3, x0, gt
    neg     x3, x3
    cmp     x0, x3
    csel    x0, x3, x0, lt
    str     x0, [x8]

    adrp    x8, ship_vy@PAGE
    add     x8, x8, #:lo12:ship_vy@PAGEOFF
    ldr     x0, [x8]
    sub     x0, x0, x2
    mov     x3, #128
    cmp     x0, x3
    csel    x0, x3, x0, gt
    neg     x3, x3
    cmp     x0, x3
    csel    x0, x3, x0, lt
    str     x0, [x8]

    b       _input_check_fire

_handle_quit:
    adrp    x8, game_running@PAGE
    str     xzr, [x8, #:lo12:game_running@PAGEOFF]
    b       _input_done

_input_done:
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Fire a bullet
//------------------------------------------------------------------------------
_fire_bullet:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!

    // Find inactive bullet slot
    adrp    x19, bullets@PAGE
    add     x19, x19, #:lo12:bullets@PAGEOFF
    mov     x20, #MAX_BULLETS

_find_bullet_slot:
    ldr     x0, [x19, #32]          // Check active flag
    cbz     x0, _use_bullet_slot
    add     x19, x19, #40           // Next bullet (5 quads)
    subs    x20, x20, #1
    bne     _find_bullet_slot
    b       _fire_done              // No free slots

_use_bullet_slot:
    // Set bullet position to ship position
    adrp    x8, ship_x@PAGE
    ldr     x0, [x8, #:lo12:ship_x@PAGEOFF]
    str     x0, [x19, #0]           // X

    adrp    x8, ship_y@PAGE
    ldr     x0, [x8, #:lo12:ship_y@PAGEOFF]
    str     x0, [x19, #8]           // Y

    // Set bullet velocity based on ship angle
    adrp    x8, ship_angle@PAGE
    ldr     x0, [x8, #:lo12:ship_angle@PAGEOFF]

    adrp    x9, dir_x@PAGE
    add     x9, x9, #:lo12:dir_x@PAGEOFF
    ldr     x1, [x9, x0, lsl #3]
    lsl     x1, x1, #7              // Bullet speed
    str     x1, [x19, #16]          // VX

    adrp    x9, dir_y@PAGE
    add     x9, x9, #:lo12:dir_y@PAGEOFF
    ldr     x2, [x9, x0, lsl #3]
    lsl     x2, x2, #7
    str     x2, [x19, #24]          // VY

    // Activate bullet
    mov     x0, #1
    str     x0, [x19, #32]

_fire_done:
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Update game state
//------------------------------------------------------------------------------
_update_game:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Check if ship is alive
    adrp    x8, ship_alive@PAGE
    ldr     x0, [x8, #:lo12:ship_alive@PAGEOFF]
    cbz     x0, _update_done

    // Update ship position
    bl      _update_ship

    // Update bullets
    bl      _update_bullets

    // Update obstacles
    bl      _update_obstacles

    // Check collisions
    bl      _check_collisions

_update_done:
    // Decrement fire cooldown
    adrp    x8, fire_cooldown@PAGE
    add     x8, x8, #:lo12:fire_cooldown@PAGEOFF
    ldr     x0, [x8]
    cbz     x0, _fire_cooldown_done
    sub     x0, x0, #1
    str     x0, [x8]
_fire_cooldown_done:

    // Decrement turn cooldown
    adrp    x8, turn_cooldown@PAGE
    add     x8, x8, #:lo12:turn_cooldown@PAGEOFF
    ldr     x0, [x8]
    cbz     x0, _turn_cooldown_done
    sub     x0, x0, #1
    str     x0, [x8]
_turn_cooldown_done:
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Update ship position
//------------------------------------------------------------------------------
_update_ship:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Apply velocity to position
    adrp    x8, ship_x@PAGE
    add     x8, x8, #:lo12:ship_x@PAGEOFF
    ldr     x0, [x8]
    adrp    x9, ship_vx@PAGE
    ldr     x1, [x9, #:lo12:ship_vx@PAGEOFF]
    add     x0, x0, x1

    // Wrap X position
    mov     x2, #SCREEN_WIDTH
    lsl     x2, x2, #8              // To fixed point
    cmp     x0, x2
    blt     _ship_x_not_high
    sub     x0, x0, x2
_ship_x_not_high:
    cmp     x0, #0
    bge     _ship_x_not_low
    add     x0, x0, x2
_ship_x_not_low:
    str     x0, [x8]

    // Apply velocity to Y
    adrp    x8, ship_y@PAGE
    add     x8, x8, #:lo12:ship_y@PAGEOFF
    ldr     x0, [x8]
    adrp    x9, ship_vy@PAGE
    ldr     x1, [x9, #:lo12:ship_vy@PAGEOFF]
    add     x0, x0, x1

    // Wrap Y position
    mov     x2, #SCREEN_HEIGHT
    lsl     x2, x2, #8
    cmp     x0, x2
    blt     _ship_y_not_high
    sub     x0, x0, x2
_ship_y_not_high:
    cmp     x0, #0
    bge     _ship_y_not_low
    add     x0, x0, x2
_ship_y_not_low:
    str     x0, [x8]

    // Apply friction (very slight - space has little drag)
    adrp    x8, ship_vx@PAGE
    add     x8, x8, #:lo12:ship_vx@PAGEOFF
    ldr     x0, [x8]
    // Reduce by 1/128 (very light friction)
    asr     x1, x0, #7
    sub     x0, x0, x1
    str     x0, [x8]

    adrp    x8, ship_vy@PAGE
    add     x8, x8, #:lo12:ship_vy@PAGEOFF
    ldr     x0, [x8]
    asr     x1, x0, #7
    sub     x0, x0, x1
    str     x0, [x8]

    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Update bullets
//------------------------------------------------------------------------------
_update_bullets:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!

    adrp    x19, bullets@PAGE
    add     x19, x19, #:lo12:bullets@PAGEOFF
    mov     x20, #MAX_BULLETS

_update_bullets_loop:
    // Check if active
    ldr     x0, [x19, #32]
    cbz     x0, _next_bullet

    // Update X position
    ldr     x0, [x19, #0]           // X
    ldr     x1, [x19, #16]          // VX
    add     x0, x0, x1

    // Check bounds - deactivate if off screen
    mov     x2, #SCREEN_WIDTH
    lsl     x2, x2, #8
    cmp     x0, x2
    bge     _deactivate_bullet
    cmp     x0, #0
    blt     _deactivate_bullet
    str     x0, [x19, #0]

    // Update Y position
    ldr     x0, [x19, #8]           // Y
    ldr     x1, [x19, #24]          // VY
    add     x0, x0, x1

    mov     x2, #SCREEN_HEIGHT
    lsl     x2, x2, #8
    cmp     x0, x2
    bge     _deactivate_bullet
    cmp     x0, #0
    blt     _deactivate_bullet
    str     x0, [x19, #8]
    b       _next_bullet

_deactivate_bullet:
    str     xzr, [x19, #32]         // Active = 0

_next_bullet:
    add     x19, x19, #40
    subs    x20, x20, #1
    bne     _update_bullets_loop

    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Update obstacles
//------------------------------------------------------------------------------
_update_obstacles:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!

    adrp    x19, obstacles@PAGE
    add     x19, x19, #:lo12:obstacles@PAGEOFF
    mov     x20, #MAX_OBSTACLES

_update_obs_loop:
    // Check if active
    ldr     x0, [x19, #40]          // Active flag
    cbz     x0, _next_obs

    // Update X
    ldr     x0, [x19, #0]           // X
    ldr     x1, [x19, #16]          // VX
    add     x0, x0, x1

    // Wrap X
    mov     x2, #SCREEN_WIDTH
    lsl     x2, x2, #8
    cmp     x0, x2
    blt     _obs_x_wrap_done
    sub     x0, x0, x2
_obs_x_wrap_done:
    cmp     x0, #0
    bge     _obs_x_wrap_done2
    add     x0, x0, x2
_obs_x_wrap_done2:
    str     x0, [x19, #0]

    // Update Y
    ldr     x0, [x19, #8]           // Y
    ldr     x1, [x19, #24]          // VY
    add     x0, x0, x1

    // Wrap Y
    mov     x2, #SCREEN_HEIGHT
    lsl     x2, x2, #8
    cmp     x0, x2
    blt     _obs_y_wrap_done
    sub     x0, x0, x2
_obs_y_wrap_done:
    cmp     x0, #0
    bge     _obs_y_wrap_done2
    add     x0, x0, x2
_obs_y_wrap_done2:
    str     x0, [x19, #8]

_next_obs:
    add     x19, x19, #48           // 6 quads per obstacle
    subs    x20, x20, #1
    bne     _update_obs_loop

    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Check collisions
//------------------------------------------------------------------------------
_check_collisions:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!

    // Get ship position
    adrp    x8, ship_x@PAGE
    ldr     x21, [x8, #:lo12:ship_x@PAGEOFF]
    lsr     x21, x21, #8            // Convert to integer

    adrp    x8, ship_y@PAGE
    ldr     x22, [x8, #:lo12:ship_y@PAGEOFF]
    lsr     x22, x22, #8

    // Check each obstacle
    adrp    x19, obstacles@PAGE
    add     x19, x19, #:lo12:obstacles@PAGEOFF
    mov     x20, #MAX_OBSTACLES

_check_obs_loop:
    ldr     x0, [x19, #40]          // Active
    cbz     x0, _check_next_obs

    // Get obstacle position
    ldr     x23, [x19, #0]          // X
    lsr     x23, x23, #8
    ldr     x24, [x19, #8]          // Y
    lsr     x24, x24, #8

    // Check collision with ship (exact position match only)
    // |ship_x - obs_x| < 1 && |ship_y - obs_y| < 1
    sub     x0, x21, x23
    cmp     x0, #0
    cneg    x0, x0, lt              // abs
    cmp     x0, #1
    bgt     _check_bullets_vs_obs

    sub     x0, x22, x24
    cmp     x0, #0
    cneg    x0, x0, lt
    cmp     x0, #1
    bgt     _check_bullets_vs_obs

    // Collision! Lose a life
    adrp    x8, lives@PAGE
    add     x8, x8, #:lo12:lives@PAGEOFF
    ldr     x0, [x8]
    subs    x0, x0, #1
    str     x0, [x8]

    cbz     x0, _game_over

    // Reset ship position
    adrp    x8, ship_x@PAGE
    mov     x0, #40
    lsl     x0, x0, #8
    str     x0, [x8, #:lo12:ship_x@PAGEOFF]

    adrp    x8, ship_y@PAGE
    mov     x0, #12
    lsl     x0, x0, #8
    str     x0, [x8, #:lo12:ship_y@PAGEOFF]

    adrp    x8, ship_vx@PAGE
    str     xzr, [x8, #:lo12:ship_vx@PAGEOFF]
    adrp    x8, ship_vy@PAGE
    str     xzr, [x8, #:lo12:ship_vy@PAGEOFF]

    b       _check_next_obs

_check_bullets_vs_obs:
    // Check bullets against this obstacle
    adrp    x9, bullets@PAGE
    add     x9, x9, #:lo12:bullets@PAGEOFF
    mov     x10, #MAX_BULLETS

_check_bullet_loop:
    ldr     x0, [x9, #32]           // Bullet active
    cbz     x0, _next_bullet_check

    // Get bullet position
    ldr     x11, [x9, #0]           // Bullet X
    lsr     x11, x11, #8
    ldr     x12, [x9, #8]           // Bullet Y
    lsr     x12, x12, #8

    // Check collision
    sub     x0, x11, x23
    cmp     x0, #0
    cneg    x0, x0, lt
    cmp     x0, #2
    bgt     _next_bullet_check

    sub     x0, x12, x24
    cmp     x0, #0
    cneg    x0, x0, lt
    cmp     x0, #2
    bgt     _next_bullet_check

    // Hit! Deactivate both
    str     xzr, [x9, #32]          // Bullet inactive
    str     xzr, [x19, #40]         // Obstacle inactive

    // Add score
    adrp    x8, score@PAGE
    add     x8, x8, #:lo12:score@PAGEOFF
    ldr     x0, [x8]
    add     x0, x0, #10
    str     x0, [x8]

    b       _check_next_obs

_next_bullet_check:
    add     x9, x9, #40
    subs    x10, x10, #1
    bne     _check_bullet_loop

_check_next_obs:
    add     x19, x19, #48
    subs    x20, x20, #1
    bne     _check_obs_loop

    // Check if all obstacles destroyed - level up!
    bl      _count_active_obstacles
    cbnz    x0, _collisions_done

    // Level up
    adrp    x8, level@PAGE
    add     x8, x8, #:lo12:level@PAGEOFF
    ldr     x0, [x8]
    add     x0, x0, #1
    str     x0, [x8]

    // Bonus points
    adrp    x8, score@PAGE
    add     x8, x8, #:lo12:score@PAGEOFF
    ldr     x0, [x8]
    add     x0, x0, #100
    str     x0, [x8]

    // Respawn obstacles
    bl      _init_obstacles

    b       _collisions_done

_game_over:
    adrp    x8, ship_alive@PAGE
    str     xzr, [x8, #:lo12:ship_alive@PAGEOFF]

_collisions_done:
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Count active obstacles
//------------------------------------------------------------------------------
_count_active_obstacles:
    adrp    x1, obstacles@PAGE
    add     x1, x1, #:lo12:obstacles@PAGEOFF
    mov     x2, #MAX_OBSTACLES
    mov     x0, #0

_count_obs_loop:
    ldr     x3, [x1, #40]
    add     x0, x0, x3
    add     x1, x1, #48
    subs    x2, x2, #1
    bne     _count_obs_loop
    ret

//------------------------------------------------------------------------------
// Render a frame
//------------------------------------------------------------------------------
_render_frame:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Clear screen and home cursor
    adrp    x0, esc_clear@PAGE
    add     x0, x0, #:lo12:esc_clear@PAGEOFF
    bl      _print_string

    adrp    x0, esc_home@PAGE
    add     x0, x0, #:lo12:esc_home@PAGEOFF
    bl      _print_string

    // Draw border and title
    bl      _draw_ui

    // Draw stars
    bl      _draw_stars

    // Draw obstacles
    bl      _draw_obstacles

    // Draw bullets
    bl      _draw_bullets

    // Draw ship
    bl      _draw_ship

    // Draw HUD
    bl      _draw_hud

    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Draw UI border
//------------------------------------------------------------------------------
_draw_ui:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!

    // Top border
    adrp    x0, esc_cyan@PAGE
    add     x0, x0, #:lo12:esc_cyan@PAGEOFF
    bl      _print_string

    mov     x19, #SCREEN_WIDTH
_top_border:
    mov     w0, #'='
    bl      _print_char
    subs    x19, x19, #1
    bne     _top_border

    mov     w0, #'\n'
    bl      _print_char

    adrp    x0, esc_reset@PAGE
    add     x0, x0, #:lo12:esc_reset@PAGEOFF
    bl      _print_string

    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Draw background stars
//------------------------------------------------------------------------------
_draw_stars:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!

    adrp    x0, esc_blue@PAGE
    add     x0, x0, #:lo12:esc_blue@PAGEOFF
    bl      _print_string

    adrp    x19, stars@PAGE
    add     x19, x19, #:lo12:stars@PAGEOFF
    mov     x20, #MAX_STARS

_draw_stars_loop:
    ldr     x21, [x19], #8          // X
    ldr     x22, [x19], #8          // Y

    // Position cursor
    add     x0, x22, #2             // Row (offset for border)
    add     x1, x21, #1             // Col
    bl      _move_cursor

    mov     w0, #'.'
    bl      _print_char

    subs    x20, x20, #1
    bne     _draw_stars_loop

    adrp    x0, esc_reset@PAGE
    add     x0, x0, #:lo12:esc_reset@PAGEOFF
    bl      _print_string

    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Draw obstacles
//------------------------------------------------------------------------------
_draw_obstacles:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!

    adrp    x19, obstacles@PAGE
    add     x19, x19, #:lo12:obstacles@PAGEOFF
    mov     x20, #MAX_OBSTACLES

_draw_obs_loop:
    ldr     x0, [x19, #40]          // Active
    cbz     x0, _draw_next_obs

    ldr     x21, [x19, #0]          // X
    lsr     x21, x21, #8
    ldr     x22, [x19, #8]          // Y
    lsr     x22, x22, #8
    ldr     x23, [x19, #32]         // Type

    // Color based on type
    cmp     x23, #0
    beq     _obs_color_yellow       // Asteroid
    cmp     x23, #1
    beq     _obs_color_white        // Space rock
    cmp     x23, #2
    beq     _obs_color_green        // Planet
    cmp     x23, #3
    beq     _obs_color_red          // Sun
    cmp     x23, #4
    beq     _obs_color_magenta      // Debris
    b       _obs_color_white        // Default

_obs_color_yellow:
    adrp    x0, esc_yellow@PAGE
    add     x0, x0, #:lo12:esc_yellow@PAGEOFF
    bl      _print_string
    b       _draw_obs_char

_obs_color_red:
    adrp    x0, esc_red@PAGE
    add     x0, x0, #:lo12:esc_red@PAGEOFF
    bl      _print_string
    b       _draw_obs_char

_obs_color_green:
    adrp    x0, esc_green@PAGE
    add     x0, x0, #:lo12:esc_green@PAGEOFF
    bl      _print_string
    b       _draw_obs_char

_obs_color_magenta:
    adrp    x0, esc_magenta@PAGE
    add     x0, x0, #:lo12:esc_magenta@PAGEOFF
    bl      _print_string
    b       _draw_obs_char

_obs_color_white:
    adrp    x0, esc_white@PAGE
    add     x0, x0, #:lo12:esc_white@PAGEOFF
    bl      _print_string

_draw_obs_char:
    // Position cursor
    add     x0, x22, #2
    add     x1, x21, #1
    bl      _move_cursor

    // Get character for this type
    adrp    x8, obstacle_types@PAGE
    add     x8, x8, #:lo12:obstacle_types@PAGEOFF
    ldrb    w0, [x8, x23]
    bl      _print_char

    adrp    x0, esc_reset@PAGE
    add     x0, x0, #:lo12:esc_reset@PAGEOFF
    bl      _print_string

_draw_next_obs:
    add     x19, x19, #48
    subs    x20, x20, #1
    bne     _draw_obs_loop

    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Draw bullets
//------------------------------------------------------------------------------
_draw_bullets:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!

    adrp    x0, esc_red@PAGE
    add     x0, x0, #:lo12:esc_red@PAGEOFF
    bl      _print_string

    adrp    x0, esc_bold@PAGE
    add     x0, x0, #:lo12:esc_bold@PAGEOFF
    bl      _print_string

    adrp    x19, bullets@PAGE
    add     x19, x19, #:lo12:bullets@PAGEOFF
    mov     x20, #MAX_BULLETS

_draw_bullets_loop:
    ldr     x0, [x19, #32]          // Active
    cbz     x0, _draw_next_bullet

    ldr     x21, [x19, #0]          // X
    lsr     x21, x21, #8
    ldr     x22, [x19, #8]          // Y
    lsr     x22, x22, #8

    add     x0, x22, #2
    add     x1, x21, #1
    bl      _move_cursor

    mov     w0, #'*'
    bl      _print_char

_draw_next_bullet:
    add     x19, x19, #40
    subs    x20, x20, #1
    bne     _draw_bullets_loop

    adrp    x0, esc_reset@PAGE
    add     x0, x0, #:lo12:esc_reset@PAGEOFF
    bl      _print_string

    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Draw ship
//------------------------------------------------------------------------------
_draw_ship:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Check if alive
    adrp    x8, ship_alive@PAGE
    ldr     x0, [x8, #:lo12:ship_alive@PAGEOFF]
    cbz     x0, _ship_not_drawn

    // Set color
    adrp    x0, esc_green@PAGE
    add     x0, x0, #:lo12:esc_green@PAGEOFF
    bl      _print_string

    adrp    x0, esc_bold@PAGE
    add     x0, x0, #:lo12:esc_bold@PAGEOFF
    bl      _print_string

    // Get position
    adrp    x8, ship_x@PAGE
    ldr     x0, [x8, #:lo12:ship_x@PAGEOFF]
    lsr     x1, x0, #8              // Integer X

    adrp    x8, ship_y@PAGE
    ldr     x0, [x8, #:lo12:ship_y@PAGEOFF]
    lsr     x0, x0, #8              // Integer Y

    // Position cursor
    add     x0, x0, #2              // Row
    add     x1, x1, #1              // Col
    bl      _move_cursor

    // Get ship character based on angle
    adrp    x8, ship_angle@PAGE
    ldr     x0, [x8, #:lo12:ship_angle@PAGEOFF]
    adrp    x8, ship_chars@PAGE
    add     x8, x8, #:lo12:ship_chars@PAGEOFF
    ldrb    w0, [x8, x0]
    bl      _print_char

    adrp    x0, esc_reset@PAGE
    add     x0, x0, #:lo12:esc_reset@PAGEOFF
    bl      _print_string

_ship_not_drawn:
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Draw HUD (score, lives, level)
//------------------------------------------------------------------------------
_draw_hud:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Move to bottom of screen
    mov     x0, #SCREEN_HEIGHT
    add     x0, x0, #2
    mov     x1, #1
    bl      _move_cursor

    // Draw bottom border
    adrp    x0, esc_cyan@PAGE
    add     x0, x0, #:lo12:esc_cyan@PAGEOFF
    bl      _print_string

    stp     x19, x20, [sp, #-16]!
    mov     x19, #SCREEN_WIDTH
_bottom_border:
    mov     w0, #'='
    bl      _print_char
    subs    x19, x19, #1
    bne     _bottom_border
    ldp     x19, x20, [sp], #16

    // Move to status line
    mov     x0, #SCREEN_HEIGHT
    add     x0, x0, #3
    mov     x1, #1
    bl      _move_cursor

    adrp    x0, esc_white@PAGE
    add     x0, x0, #:lo12:esc_white@PAGEOFF
    bl      _print_string

    // Score
    adrp    x0, score_msg@PAGE
    add     x0, x0, #:lo12:score_msg@PAGEOFF
    bl      _print_string

    adrp    x8, score@PAGE
    ldr     x0, [x8, #:lo12:score@PAGEOFF]
    bl      _print_number

    // Spacing
    mov     w0, #' '
    bl      _print_char
    mov     w0, #' '
    bl      _print_char

    // Lives
    adrp    x0, lives_msg@PAGE
    add     x0, x0, #:lo12:lives_msg@PAGEOFF
    bl      _print_string

    adrp    x8, lives@PAGE
    ldr     x0, [x8, #:lo12:lives@PAGEOFF]
    bl      _print_number

    // Spacing
    mov     w0, #' '
    bl      _print_char
    mov     w0, #' '
    bl      _print_char

    // Level
    adrp    x0, level_msg@PAGE
    add     x0, x0, #:lo12:level_msg@PAGEOFF
    bl      _print_string

    adrp    x8, level@PAGE
    ldr     x0, [x8, #:lo12:level@PAGEOFF]
    bl      _print_number

    // Spacing
    mov     w0, #' '
    bl      _print_char
    mov     w0, #' '
    bl      _print_char

    // Controls
    adrp    x0, esc_yellow@PAGE
    add     x0, x0, #:lo12:esc_yellow@PAGEOFF
    bl      _print_string

    adrp    x0, controls_msg@PAGE
    add     x0, x0, #:lo12:controls_msg@PAGEOFF
    bl      _print_string

    // Check if game over
    adrp    x8, ship_alive@PAGE
    ldr     x0, [x8, #:lo12:ship_alive@PAGEOFF]
    cbnz    x0, _hud_done

    // Game over message
    mov     x0, #12
    mov     x1, #30
    bl      _move_cursor

    adrp    x0, esc_red@PAGE
    add     x0, x0, #:lo12:esc_red@PAGEOFF
    bl      _print_string

    adrp    x0, esc_bold@PAGE
    add     x0, x0, #:lo12:esc_bold@PAGEOFF
    bl      _print_string

    adrp    x0, gameover_msg@PAGE
    add     x0, x0, #:lo12:gameover_msg@PAGEOFF
    bl      _print_string

_hud_done:
    adrp    x0, esc_reset@PAGE
    add     x0, x0, #:lo12:esc_reset@PAGEOFF
    bl      _print_string

    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Move cursor to row, col (1-based)
// x0 = row, x1 = col
//------------------------------------------------------------------------------
_move_cursor:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!

    mov     x19, x0                 // Save row
    mov     x20, x1                 // Save col

    // Build escape sequence: ESC [ row ; col H
    adrp    x8, pos_buffer@PAGE
    add     x8, x8, #:lo12:pos_buffer@PAGEOFF

    mov     w0, #27                 // ESC
    strb    w0, [x8], #1
    mov     w0, #'['
    strb    w0, [x8], #1

    // Row digits
    mov     x0, x19
    mov     x1, #10
    udiv    x2, x0, x1
    msub    x3, x2, x1, x0          // x3 = x0 % 10
    add     w2, w2, #'0'
    strb    w2, [x8], #1
    add     w3, w3, #'0'
    strb    w3, [x8], #1

    mov     w0, #';'
    strb    w0, [x8], #1

    // Col digits
    mov     x0, x20
    mov     x1, #10
    udiv    x2, x0, x1
    msub    x3, x2, x1, x0
    add     w2, w2, #'0'
    strb    w2, [x8], #1
    add     w3, w3, #'0'
    strb    w3, [x8], #1

    mov     w0, #'H'
    strb    w0, [x8], #1
    strb    wzr, [x8]               // Null terminate

    // Print it
    adrp    x0, pos_buffer@PAGE
    add     x0, x0, #:lo12:pos_buffer@PAGEOFF
    bl      _print_string

    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Print a null-terminated string
// x0 = pointer to string
//------------------------------------------------------------------------------
_print_string:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x8, x0                  // Save string pointer

    // Find string length
    mov     x1, x0
_strlen_loop:
    ldrb    w2, [x1], #1
    cbnz    w2, _strlen_loop
    sub     x2, x1, x0
    sub     x2, x2, #1              // Length without null

    // Write
    mov     x0, #STDOUT
    mov     x1, x8
    mov     x16, #SYS_WRITE
    svc     #0x80

    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Print a single character
// w0 = character
//------------------------------------------------------------------------------
_print_char:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Store char on stack
    sub     sp, sp, #16
    strb    w0, [sp]

    mov     x0, #STDOUT
    mov     x1, sp
    mov     x2, #1
    mov     x16, #SYS_WRITE
    svc     #0x80

    add     sp, sp, #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Print a number
// x0 = number to print
//------------------------------------------------------------------------------
_print_number:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!

    // Handle zero specially
    cbnz    x0, _print_nonzero
    mov     w0, #'0'
    bl      _print_char
    b       _print_num_done

_print_nonzero:
    adrp    x8, num_buffer@PAGE
    add     x8, x8, #:lo12:num_buffer@PAGEOFF
    add     x8, x8, #15             // End of buffer
    strb    wzr, [x8]               // Null terminate
    sub     x8, x8, #1

    mov     x1, #10
_print_num_loop:
    cbz     x0, _print_num_output
    udiv    x2, x0, x1
    msub    x3, x2, x1, x0          // x3 = x0 % 10
    add     w3, w3, #'0'
    strb    w3, [x8]
    sub     x8, x8, #1
    mov     x0, x2
    b       _print_num_loop

_print_num_output:
    add     x0, x8, #1
    bl      _print_string

_print_num_done:
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Microsecond delay
// x0 = microseconds
//------------------------------------------------------------------------------
_usleep:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Convert to nanoseconds for nanosleep
    // Actually we'll use select with timeout
    adrp    x8, timeval@PAGE
    add     x8, x8, #:lo12:timeval@PAGEOFF

    // seconds = usec / 1000000
    movz    x1, #0x4240
    movk    x1, #0x000F, lsl #16    // 1000000 = 0xF4240
    udiv    x2, x0, x1
    str     x2, [x8, #0]            // tv_sec

    // usec = usec % 1000000
    msub    x0, x2, x1, x0
    str     x0, [x8, #8]            // tv_usec

    // select(0, NULL, NULL, NULL, &timeval)
    mov     x0, #0
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    mov     x4, x8
    mov     x16, #SYS_SELECT
    svc     #0x80

    ldp     x29, x30, [sp], #16
    ret

.end
