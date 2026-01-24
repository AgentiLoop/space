//==============================================================================
// SPACE - Block Graphics Game in ARM64 Assembly with SDL2
// With lives, score, game states
//==============================================================================

.global _main
.align 4

//==============================================================================
// Constants
//==============================================================================
.equ SCREEN_W,          800
.equ SCREEN_H,          480
.equ MAX_OBSTACLES,     20
.equ MAX_BULLETS,       10

// SDL constants
.equ SDL_INIT_VIDEO,    0x00000020
.equ SDL_WINDOW_SHOWN,  0x00000004
.equ SDL_QUIT,          0x100
.equ SDL_KEYDOWN,       0x300
.equ SDL_KEYUP,         0x301

// Scancodes
.equ KEY_UP,            82
.equ KEY_DOWN,          81
.equ KEY_LEFT,          80
.equ KEY_RIGHT,         79
.equ KEY_SPACE,         44
.equ KEY_Q,             20

// Game states
.equ STATE_START,       0
.equ STATE_PLAYING,     1
.equ STATE_GAMEOVER,    2

//==============================================================================
// Data Section
//==============================================================================
.data
.align 4

window:         .quad 0
renderer:       .quad 0
game_running:   .quad 1
game_state:     .quad STATE_START

// Ship state
ship_x:         .quad 400
ship_y:         .quad 240
ship_vx:        .quad 0
ship_vy:        .quad 0
ship_dir:       .quad 0
ship_alive:     .quad 1
ship_flash:     .quad 0             // invincibility frames after respawn

// Game stats
lives:          .quad 3
score:          .quad 0
level:          .quad 1
rocks_left:     .quad 0
spawn_count:    .quad 0

// Input flags
key_up:         .quad 0
key_down:       .quad 0
key_left:       .quad 0
key_right:      .quad 0
key_space:      .quad 0
key_space_prev: .quad 0             // for detecting new press
fire_cooldown:  .quad 0
turn_cooldown:  .quad 0
thrust_cooldown: .quad 0
friction_counter: .quad 0

// Direction vectors (scaled by 2)
dir_dx:         .quad 0, 2, 2, 2, 0, -2, -2, -2
dir_dy:         .quad -2, -2, 0, 2, 2, 2, 0, -2

// Triangle vertices - mathematically correct rotations
ship_tri:
    .quad 0, -10, -7, 7, 7, 7           // Dir 0: up
    .quad 7, -7, -10, 0, 0, 10          // Dir 1: up-right
    .quad 10, 0, -7, -7, -7, 7          // Dir 2: right
    .quad 7, 7, 0, -10, -10, 0          // Dir 3: down-right
    .quad 0, 10, 7, -7, -7, -7          // Dir 4: down
    .quad -7, 7, 10, 0, 0, -10          // Dir 5: down-left
    .quad -10, 0, 7, 7, 7, -7           // Dir 6: left
    .quad -7, -7, 0, 10, 10, 0          // Dir 7: up-left

// Digit bitmaps (5 wide x 7 tall, stored as 7 bytes per digit, bits = pixels)
// Each byte is one row, bit 4=leftmost, bit 0=rightmost
digits:
    .byte 0x1F, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1F  // 0
    .byte 0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E  // 1
    .byte 0x1F, 0x01, 0x01, 0x1F, 0x10, 0x10, 0x1F  // 2
    .byte 0x1F, 0x01, 0x01, 0x1F, 0x01, 0x01, 0x1F  // 3
    .byte 0x11, 0x11, 0x11, 0x1F, 0x01, 0x01, 0x01  // 4
    .byte 0x1F, 0x10, 0x10, 0x1F, 0x01, 0x01, 0x1F  // 5
    .byte 0x1F, 0x10, 0x10, 0x1F, 0x11, 0x11, 0x1F  // 6
    .byte 0x1F, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01  // 7
    .byte 0x1F, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x1F  // 8
    .byte 0x1F, 0x11, 0x11, 0x1F, 0x01, 0x01, 0x1F  // 9

// Obstacles and bullets
obstacles:      .space 800          // 20 * 40 bytes
bullets:        .space 400          // 10 * 40 bytes

.align 3
random_seed:    .quad 12345678

.align 4
sdl_event:      .space 64
draw_rect:      .space 16

window_title:   .asciz "SPACE - Arrow Keys, Space to Fire, Q to Quit"

// SDL hints for Metal renderer and HiDPI
hint_render_driver: .asciz "SDL_RENDER_DRIVER"
hint_metal:         .asciz "metal"
hint_scale_quality: .asciz "SDL_RENDER_SCALE_QUALITY"
hint_linear:        .asciz "linear"

//==============================================================================
// Text Section
//==============================================================================
.text

//------------------------------------------------------------------------------
// Main entry point
//------------------------------------------------------------------------------
_main:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Set Metal renderer hint BEFORE SDL_Init
    adrp    x0, hint_render_driver@PAGE
    add     x0, x0, hint_render_driver@PAGEOFF
    adrp    x1, hint_metal@PAGE
    add     x1, x1, hint_metal@PAGEOFF
    bl      _SDL_SetHint

    // Set render scale quality to linear for smoother scaling
    adrp    x0, hint_scale_quality@PAGE
    add     x0, x0, hint_scale_quality@PAGEOFF
    adrp    x1, hint_linear@PAGE
    add     x1, x1, hint_linear@PAGEOFF
    bl      _SDL_SetHint

    // Initialize SDL
    mov     w0, #SDL_INIT_VIDEO
    bl      _SDL_Init
    cbnz    w0, exit_fail

    // Set OpenGL multisampling for antialiasing (MUST be before window creation)
    // SDL_GL_MULTISAMPLEBUFFERS = 13, value = 1
    mov     w0, #13
    mov     w1, #1
    bl      _SDL_GL_SetAttribute
    // SDL_GL_MULTISAMPLESAMPLES = 14, value = 4 (4x MSAA)
    mov     w0, #14
    mov     w1, #4
    bl      _SDL_GL_SetAttribute

    // Create window WITHOUT HiDPI - AA works better at logical resolution
    // SDL_WINDOW_SHOWN = 0x04
    adrp    x0, window_title@PAGE
    add     x0, x0, window_title@PAGEOFF
    mov     w1, #0x1FFF
    movk    w1, #0x1FFF, lsl #16
    mov     w2, w1
    mov     w3, #SCREEN_W
    mov     w4, #SCREEN_H
    mov     w5, #4
    bl      _SDL_CreateWindow
    cbz     x0, exit_fail
    adrp    x1, window@PAGE
    str     x0, [x1, window@PAGEOFF]

    // Create renderer with VSync (SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC = 6)
    mov     w1, #-1
    mov     w2, #6
    bl      _SDL_CreateRenderer
    cbz     x0, exit_fail
    adrp    x1, renderer@PAGE
    str     x0, [x1, renderer@PAGEOFF]

    // Enable BLEND mode for antialiased lines (SDL_BLENDMODE_BLEND = 1)
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #1
    bl      _SDL_SetRenderDrawBlendMode

    // Initialize game
    bl      init_game

game_loop:
    adrp    x0, game_running@PAGE
    ldr     x0, [x0, game_running@PAGEOFF]
    cbz     x0, game_exit

    bl      process_events

    // Check game state
    adrp    x0, game_state@PAGE
    ldr     x0, [x0, game_state@PAGEOFF]

    cmp     x0, #STATE_START
    beq     do_start_screen

    cmp     x0, #STATE_PLAYING
    beq     do_playing

    // STATE_GAMEOVER
    bl      render_gameover
    b       game_delay

do_start_screen:
    bl      render_start
    b       game_delay

do_playing:
    bl      update_game
    bl      render_game
    b       game_delay

game_delay:
    // VSync handles timing - no SDL_Delay needed
    b       game_loop

game_exit:
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    bl      _SDL_DestroyRenderer

    adrp    x0, window@PAGE
    ldr     x0, [x0, window@PAGEOFF]
    bl      _SDL_DestroyWindow

    bl      _SDL_Quit

    mov     w0, #0
    ldp     x29, x30, [sp], #16
    ret

exit_fail:
    mov     w0, #1
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Initialize game state
//------------------------------------------------------------------------------
init_game:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!

    // Reset ship
    adrp    x8, ship_x@PAGE
    mov     x0, #400
    str     x0, [x8, ship_x@PAGEOFF]
    adrp    x8, ship_y@PAGE
    mov     x0, #240
    str     x0, [x8, ship_y@PAGEOFF]
    adrp    x8, ship_vx@PAGE
    str     xzr, [x8, ship_vx@PAGEOFF]
    adrp    x8, ship_vy@PAGE
    str     xzr, [x8, ship_vy@PAGEOFF]
    adrp    x8, ship_dir@PAGE
    str     xzr, [x8, ship_dir@PAGEOFF]
    adrp    x8, ship_alive@PAGE
    mov     x0, #1
    str     x0, [x8, ship_alive@PAGEOFF]
    adrp    x8, ship_flash@PAGE
    str     xzr, [x8, ship_flash@PAGEOFF]

    // Reset stats
    adrp    x8, lives@PAGE
    mov     x0, #3
    str     x0, [x8, lives@PAGEOFF]
    adrp    x8, score@PAGE
    str     xzr, [x8, score@PAGEOFF]
    adrp    x8, level@PAGE
    mov     x0, #1
    str     x0, [x8, level@PAGEOFF]

    // Initialize obstacles using spawn_level_obstacles
    bl      spawn_level_obstacles
    // Clear bullets
    adrp    x19, bullets@PAGE
    add     x19, x19, bullets@PAGEOFF
    mov     w20, #MAX_BULLETS
clr_bul_loop:
    str     xzr, [x19, #0]
    str     xzr, [x19, #8]
    str     xzr, [x19, #16]
    str     xzr, [x19, #24]
    str     xzr, [x19, #32]
    add     x19, x19, #40
    subs    w20, w20, #1
    bne     clr_bul_loop

    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Spawn obstacles for current level
//------------------------------------------------------------------------------
spawn_level_obstacles:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!

    // Reset spawn_count for debugging
    adrp    x8, spawn_count@PAGE
    str     xzr, [x8, spawn_count@PAGEOFF]

    // Get level to determine count and speed
    adrp    x8, level@PAGE
    add     x8, x8, level@PAGEOFF
    ldr     x21, [x8]

    // Number of obstacles = level + 2
    add     w22, w21, #2

    // First, clear ALL obstacle slots to inactive
    adrp    x19, obstacles@PAGE
    add     x19, x19, obstacles@PAGEOFF
    mov     w20, #MAX_OBSTACLES
clear_all_obs:
    cbz     w20, start_spawning
    str     xzr, [x19, #32]                 // Set active = 0
    add     x19, x19, #40
    sub     w20, w20, #1
    b       clear_all_obs

start_spawning:
    // Reset pointer and counter
    adrp    x19, obstacles@PAGE
    add     x19, x19, obstacles@PAGEOFF

    // Store rocks count for tracking (w22 = number to spawn)
    adrp    x8, rocks_left@PAGE
    str     x22, [x8, rocks_left@PAGEOFF]

spawn_obs_loop:
    cbz     w22, spawn_obs_done             // Done when spawn count reaches 0

    // Save w22 before random calls (random_num may corrupt it)
    mov     w23, w22

    // Random X position (50-750, avoid center 350-450)
    bl      random_num
    mov     w1, #700
    udiv    w2, w0, w1
    msub    w0, w2, w1, w0                  // w0 % 700
    add     w0, w0, #50                     // 50-750
    cmp     w0, #350
    blt     store_x
    cmp     w0, #450
    bgt     store_x
    add     w0, w0, #250                    // push away from center
store_x:
    str     x0, [x19, #0]

    // Random Y position (50-430)
    bl      random_num
    mov     w1, #380
    udiv    w2, w0, w1
    msub    w0, w2, w1, w0                  // w0 % 380
    add     w0, w0, #50                     // 50-430
store_y:
    str     x0, [x19, #8]

    // Random Velocity X: -2 to +2, never zero
    bl      random_num
    and     w0, w0, #3                      // 0-3
    sub     w0, w0, #1                      // -1 to +2
    cbz     w0, vx_make_nonzero
    b       store_vx
vx_make_nonzero:
    mov     w0, #1
store_vx:
    str     w0, [x19, #16]                  // Store as 32-bit

    // Random Velocity Y: -2 to +2, never zero
    bl      random_num
    and     w0, w0, #3                      // 0-3
    sub     w0, w0, #1                      // -1 to +2
    cbz     w0, vy_make_nonzero
    b       store_vy
vy_make_nonzero:
    mov     w0, #-1
store_vy:
    str     w0, [x19, #24]                  // Store as 32-bit

    // Set active = 1
    mov     x0, #1
    str     x0, [x19, #32]

    // DEBUG: increment spawn_count
    adrp    x8, spawn_count@PAGE
    add     x8, x8, spawn_count@PAGEOFF
    ldr     x0, [x8]
    add     x0, x0, #1
    str     x0, [x8]

    // Restore w22 and move to next slot
    mov     w22, w23
    add     x19, x19, #40
    sub     w22, w22, #1
    b       spawn_obs_loop

spawn_obs_done:
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Random number generator
//------------------------------------------------------------------------------
random_num:
    adrp    x8, random_seed@PAGE
    add     x8, x8, random_seed@PAGEOFF
    ldr     x0, [x8]
    movz    x1, #0x7F2D
    movk    x1, #0x4C95, lsl #16
    movk    x1, #0xF42D, lsl #32
    movk    x1, #0x5851, lsl #48
    mul     x0, x0, x1
    add     x0, x0, #1
    str     x0, [x8]
    lsr     x0, x0, #33
    ret

//------------------------------------------------------------------------------
// Process SDL events
//------------------------------------------------------------------------------
process_events:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Save previous space state for edge detection
    adrp    x8, key_space@PAGE
    ldr     x0, [x8, key_space@PAGEOFF]
    adrp    x9, key_space_prev@PAGE
    str     x0, [x9, key_space_prev@PAGEOFF]

evt_loop:
    adrp    x0, sdl_event@PAGE
    add     x0, x0, sdl_event@PAGEOFF
    bl      _SDL_PollEvent
    cbz     w0, evt_done

    adrp    x8, sdl_event@PAGE
    add     x8, x8, sdl_event@PAGEOFF
    ldr     w0, [x8]

    cmp     w0, #SDL_QUIT
    beq     do_quit

    cmp     w0, #SDL_KEYDOWN
    beq     handle_keydown

    cmp     w0, #SDL_KEYUP
    beq     handle_keyup

    b       evt_loop

do_quit:
    adrp    x8, game_running@PAGE
    str     xzr, [x8, game_running@PAGEOFF]
    b       evt_done

handle_keydown:
    adrp    x8, sdl_event@PAGE
    add     x8, x8, sdl_event@PAGEOFF
    ldr     w0, [x8, #16]

    cmp     w0, #KEY_Q
    beq     do_quit
    cmp     w0, #KEY_UP
    beq     kd_up
    cmp     w0, #KEY_DOWN
    beq     kd_down
    cmp     w0, #KEY_LEFT
    beq     kd_left
    cmp     w0, #KEY_RIGHT
    beq     kd_right
    cmp     w0, #KEY_SPACE
    beq     kd_space
    b       evt_loop

kd_up:
    adrp    x8, key_up@PAGE
    mov     x0, #1
    str     x0, [x8, key_up@PAGEOFF]
    b       evt_loop
kd_down:
    adrp    x8, key_down@PAGE
    mov     x0, #1
    str     x0, [x8, key_down@PAGEOFF]
    b       evt_loop
kd_left:
    adrp    x8, key_left@PAGE
    mov     x0, #1
    str     x0, [x8, key_left@PAGEOFF]
    b       evt_loop
kd_right:
    adrp    x8, key_right@PAGE
    mov     x0, #1
    str     x0, [x8, key_right@PAGEOFF]
    b       evt_loop
kd_space:
    adrp    x8, key_space@PAGE
    mov     x0, #1
    str     x0, [x8, key_space@PAGEOFF]
    b       evt_loop

handle_keyup:
    adrp    x8, sdl_event@PAGE
    add     x8, x8, sdl_event@PAGEOFF
    ldr     w0, [x8, #16]

    cmp     w0, #KEY_UP
    beq     ku_up
    cmp     w0, #KEY_DOWN
    beq     ku_down
    cmp     w0, #KEY_LEFT
    beq     ku_left
    cmp     w0, #KEY_RIGHT
    beq     ku_right
    cmp     w0, #KEY_SPACE
    beq     ku_space
    b       evt_loop

ku_up:
    adrp    x8, key_up@PAGE
    str     xzr, [x8, key_up@PAGEOFF]
    b       evt_loop
ku_down:
    adrp    x8, key_down@PAGE
    str     xzr, [x8, key_down@PAGEOFF]
    b       evt_loop
ku_left:
    adrp    x8, key_left@PAGE
    str     xzr, [x8, key_left@PAGEOFF]
    b       evt_loop
ku_right:
    adrp    x8, key_right@PAGE
    str     xzr, [x8, key_right@PAGEOFF]
    b       evt_loop
ku_space:
    adrp    x8, key_space@PAGE
    str     xzr, [x8, key_space@PAGEOFF]
    b       evt_loop

evt_done:
    // Check for space press to change game state
    adrp    x8, key_space@PAGE
    ldr     x0, [x8, key_space@PAGEOFF]
    cbz     x0, evt_ret

    adrp    x8, key_space_prev@PAGE
    ldr     x1, [x8, key_space_prev@PAGEOFF]
    cbnz    x1, evt_ret                     // not a new press

    // New space press - check state
    adrp    x8, game_state@PAGE
    add     x8, x8, game_state@PAGEOFF
    ldr     x0, [x8]

    cmp     x0, #STATE_START
    beq     start_game

    cmp     x0, #STATE_GAMEOVER
    beq     restart_game

    b       evt_ret

start_game:
    mov     x0, #STATE_PLAYING
    str     x0, [x8]
    b       evt_ret

restart_game:
    // Reset everything
    stp     x29, x30, [sp, #-16]!
    bl      init_game
    ldp     x29, x30, [sp], #16

    adrp    x8, game_state@PAGE
    mov     x0, #STATE_PLAYING
    str     x0, [x8, game_state@PAGEOFF]

evt_ret:
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Update game state
//------------------------------------------------------------------------------
update_game:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!

    // Check if ship alive
    adrp    x8, ship_alive@PAGE
    ldr     x0, [x8, ship_alive@PAGEOFF]
    cbz     x0, update_done

    // Decrement flash timer if active
    adrp    x8, ship_flash@PAGE
    add     x8, x8, ship_flash@PAGEOFF
    ldr     x0, [x8]
    cbz     x0, no_flash_decr
    sub     x0, x0, #1
    str     x0, [x8]
no_flash_decr:

    // Check turn cooldown
    adrp    x8, turn_cooldown@PAGE
    add     x8, x8, turn_cooldown@PAGEOFF
    ldr     x0, [x8]
    cbnz    x0, decr_turn_cd

    // Handle turning left
    adrp    x9, key_left@PAGE
    ldr     x1, [x9, key_left@PAGEOFF]
    cbz     x1, check_right

    adrp    x9, ship_dir@PAGE
    add     x9, x9, ship_dir@PAGEOFF
    ldr     x1, [x9]
    sub     x1, x1, #1
    and     x1, x1, #7
    str     x1, [x9]
    mov     x0, #6
    str     x0, [x8]
    b       check_thrust

check_right:
    adrp    x9, key_right@PAGE
    ldr     x1, [x9, key_right@PAGEOFF]
    cbz     x1, check_thrust

    adrp    x9, ship_dir@PAGE
    add     x9, x9, ship_dir@PAGEOFF
    ldr     x1, [x9]
    add     x1, x1, #1
    and     x1, x1, #7
    str     x1, [x9]
    mov     x0, #6
    str     x0, [x8]
    b       check_thrust

decr_turn_cd:
    sub     x0, x0, #1
    str     x0, [x8]

check_thrust:
    // Check thrust cooldown first
    adrp    x8, thrust_cooldown@PAGE
    add     x8, x8, thrust_cooldown@PAGEOFF
    ldr     x0, [x8]
    cbnz    x0, decr_thrust_cd              // If cooldown active, skip thrust

    // Check if UP or DOWN is pressed
    adrp    x9, key_up@PAGE
    ldr     x1, [x9, key_up@PAGEOFF]
    adrp    x9, key_down@PAGE
    ldr     x2, [x9, key_down@PAGEOFF]
    orr     x3, x1, x2
    cbz     x3, check_fire                  // Neither pressed, skip

    // Set thrust cooldown (6 frames between thrusts = 10 thrusts/sec at 60fps)
    mov     x0, #6
    str     x0, [x8]

    // Get direction vectors
    adrp    x8, ship_dir@PAGE
    ldr     x0, [x8, ship_dir@PAGEOFF]
    and     x0, x0, #7

    adrp    x9, dir_dx@PAGE
    add     x9, x9, dir_dx@PAGEOFF
    ldr     x10, [x9, x0, lsl #3]
    asr     x10, x10, #1                    // ±2 becomes ±1

    adrp    x9, dir_dy@PAGE
    add     x9, x9, dir_dy@PAGEOFF
    ldr     x11, [x9, x0, lsl #3]
    asr     x11, x11, #1                    // ±2 becomes ±1

    // UP = forward thrust (add), DOWN = reverse (subtract)
    adrp    x9, key_up@PAGE
    ldr     x1, [x9, key_up@PAGEOFF]
    cbz     x1, do_reverse

    // Forward thrust: add direction to velocity
    adrp    x8, ship_vx@PAGE
    add     x8, x8, ship_vx@PAGEOFF
    ldr     x3, [x8]
    add     x3, x3, x10
    mov     x9, #6                          // Max velocity ±6
    cmp     x3, x9
    csel    x3, x9, x3, gt
    mov     x9, #-6
    cmp     x3, x9
    csel    x3, x9, x3, lt
    str     x3, [x8]

    adrp    x8, ship_vy@PAGE
    add     x8, x8, ship_vy@PAGEOFF
    ldr     x3, [x8]
    add     x3, x3, x11
    mov     x9, #6
    cmp     x3, x9
    csel    x3, x9, x3, gt
    mov     x9, #-6
    cmp     x3, x9
    csel    x3, x9, x3, lt
    str     x3, [x8]
    b       check_fire

do_reverse:
    // Reverse thrust: subtract = opposite direction, counteracts forward
    adrp    x8, ship_vx@PAGE
    add     x8, x8, ship_vx@PAGEOFF
    ldr     x3, [x8]
    sub     x3, x3, x10                     // Subtract to go opposite way
    mov     x9, #6
    cmp     x3, x9
    csel    x3, x9, x3, gt
    mov     x9, #-6
    cmp     x3, x9
    csel    x3, x9, x3, lt
    str     x3, [x8]

    adrp    x8, ship_vy@PAGE
    add     x8, x8, ship_vy@PAGEOFF
    ldr     x3, [x8]
    sub     x3, x3, x11                     // Subtract to go opposite way
    mov     x9, #6
    cmp     x3, x9
    csel    x3, x9, x3, gt
    mov     x9, #-6
    cmp     x3, x9
    csel    x3, x9, x3, lt
    str     x3, [x8]
    b       check_fire

decr_thrust_cd:
    sub     x0, x0, #1
    str     x0, [x8]

check_fire:
    adrp    x8, key_space@PAGE
    ldr     x0, [x8, key_space@PAGEOFF]
    cbz     x0, apply_velocity

    adrp    x8, fire_cooldown@PAGE
    add     x8, x8, fire_cooldown@PAGEOFF
    ldr     x0, [x8]
    cbnz    x0, apply_velocity

    mov     x0, #12
    str     x0, [x8]

    // Find inactive bullet
    adrp    x19, bullets@PAGE
    add     x19, x19, bullets@PAGEOFF
    mov     w20, #MAX_BULLETS

find_bullet:
    cbz     w20, apply_velocity
    ldr     x0, [x19, #32]
    cbz     x0, use_bullet
    add     x19, x19, #40
    sub     w20, w20, #1
    b       find_bullet

use_bullet:
    adrp    x8, ship_x@PAGE
    ldr     x0, [x8, ship_x@PAGEOFF]
    str     x0, [x19, #0]

    adrp    x8, ship_y@PAGE
    ldr     x0, [x8, ship_y@PAGEOFF]
    str     x0, [x19, #8]

    adrp    x8, ship_dir@PAGE
    ldr     x0, [x8, ship_dir@PAGEOFF]
    and     x0, x0, #7

    adrp    x9, dir_dx@PAGE
    add     x9, x9, dir_dx@PAGEOFF
    ldr     x1, [x9, x0, lsl #3]
    lsl     x1, x1, #2
    str     x1, [x19, #16]

    adrp    x9, dir_dy@PAGE
    add     x9, x9, dir_dy@PAGEOFF
    ldr     x1, [x9, x0, lsl #3]
    lsl     x1, x1, #2
    str     x1, [x19, #24]

    mov     x0, #60
    str     x0, [x19, #32]

apply_velocity:
    adrp    x8, ship_x@PAGE
    add     x8, x8, ship_x@PAGEOFF
    ldr     x0, [x8]
    adrp    x9, ship_vx@PAGE
    ldr     x1, [x9, ship_vx@PAGEOFF]
    add     x0, x0, x1

    cmp     x0, #SCREEN_W
    blt     1f
    sub     x0, x0, #SCREEN_W
1:  cmp     x0, #0
    bge     2f
    add     x0, x0, #SCREEN_W
2:  str     x0, [x8]

    adrp    x8, ship_y@PAGE
    add     x8, x8, ship_y@PAGEOFF
    ldr     x0, [x8]
    adrp    x9, ship_vy@PAGE
    ldr     x1, [x9, ship_vy@PAGEOFF]
    add     x0, x0, x1

    cmp     x0, #SCREEN_H
    blt     3f
    sub     x0, x0, #SCREEN_H
3:  cmp     x0, #0
    bge     4f
    add     x0, x0, #SCREEN_H
4:  str     x0, [x8]

    // Apply friction - slow ship down gradually
    adrp    x8, friction_counter@PAGE
    add     x8, x8, friction_counter@PAGEOFF
    ldr     x0, [x8]
    add     x0, x0, #1
    cmp     x0, #30                         // Apply friction every 30 frames
    blt     store_friction
    mov     x0, #0                          // Reset counter

    // Reduce vx toward zero
    adrp    x9, ship_vx@PAGE
    add     x9, x9, ship_vx@PAGEOFF
    ldr     x1, [x9]
    cbz     x1, friction_vy                 // Skip if already 0
    cmp     x1, #0
    bgt     friction_vx_pos
    add     x1, x1, #1                      // vx < 0, add 1
    b       friction_vx_store
friction_vx_pos:
    sub     x1, x1, #1                      // vx > 0, sub 1
friction_vx_store:
    str     x1, [x9]

friction_vy:
    // Reduce vy toward zero
    adrp    x9, ship_vy@PAGE
    add     x9, x9, ship_vy@PAGEOFF
    ldr     x1, [x9]
    cbz     x1, store_friction              // Skip if already 0
    cmp     x1, #0
    bgt     friction_vy_pos
    add     x1, x1, #1                      // vy < 0, add 1
    b       friction_vy_store
friction_vy_pos:
    sub     x1, x1, #1                      // vy > 0, sub 1
friction_vy_store:
    str     x1, [x9]

store_friction:
    str     x0, [x8]

    // Decrement fire cooldown
    adrp    x8, fire_cooldown@PAGE
    add     x8, x8, fire_cooldown@PAGEOFF
    ldr     x0, [x8]
    cbz     x0, update_bullets
    sub     x0, x0, #1
    str     x0, [x8]

update_bullets:
    adrp    x19, bullets@PAGE
    add     x19, x19, bullets@PAGEOFF
    mov     w20, #MAX_BULLETS

upd_bul_loop:
    cbz     w20, update_obstacles
    ldr     x0, [x19, #32]
    cbz     x0, next_bullet

    sub     x0, x0, #1
    str     x0, [x19, #32]
    cbz     x0, next_bullet

    ldr     x0, [x19, #0]
    ldr     x1, [x19, #16]
    add     x0, x0, x1

    cmp     x0, #0
    blt     deact_bullet
    cmp     x0, #SCREEN_W
    bge     deact_bullet
    str     x0, [x19, #0]

    ldr     x0, [x19, #8]
    ldr     x1, [x19, #24]
    add     x0, x0, x1

    cmp     x0, #0
    blt     deact_bullet
    cmp     x0, #SCREEN_H
    bge     deact_bullet
    str     x0, [x19, #8]
    b       next_bullet

deact_bullet:
    str     xzr, [x19, #32]

next_bullet:
    add     x19, x19, #40
    sub     w20, w20, #1
    b       upd_bul_loop

update_obstacles:
    adrp    x19, obstacles@PAGE
    add     x19, x19, obstacles@PAGEOFF
    mov     w20, #MAX_OBSTACLES

upd_obs_loop:
    cbz     w20, check_collisions
    ldr     x0, [x19, #32]
    cbz     x0, next_obstacle

    ldr     x0, [x19, #0]
    ldrsw   x1, [x19, #16]              // Sign-extend 32-bit velocity to 64-bit
    add     x0, x0, x1

    cmp     x0, #SCREEN_W
    blt     5f
    sub     x0, x0, #SCREEN_W
5:  cmp     x0, #0
    bge     6f
    add     x0, x0, #SCREEN_W
6:  str     x0, [x19, #0]

    ldr     x0, [x19, #8]
    ldrsw   x1, [x19, #24]              // Sign-extend 32-bit velocity to 64-bit
    add     x0, x0, x1

    cmp     x0, #SCREEN_H
    blt     7f
    sub     x0, x0, #SCREEN_H
7:  cmp     x0, #0
    bge     8f
    add     x0, x0, #SCREEN_H
8:  str     x0, [x19, #8]

next_obstacle:
    add     x19, x19, #40
    sub     w20, w20, #1
    b       upd_obs_loop

check_collisions:
    // Get ship position
    adrp    x8, ship_x@PAGE
    ldr     x21, [x8, ship_x@PAGEOFF]
    adrp    x8, ship_y@PAGE
    ldr     x22, [x8, ship_y@PAGEOFF]

    // Check obstacle collisions
    adrp    x19, obstacles@PAGE
    add     x19, x19, obstacles@PAGEOFF
    mov     w20, #MAX_OBSTACLES

coll_obs_loop:
    cbz     w20, coll_bul_start
    ldr     x0, [x19, #32]
    cbz     x0, next_coll_obs

    // Always check bullet collisions first
    // Skip ship collision if flashing (invincible)
    adrp    x8, ship_flash@PAGE
    ldr     x0, [x8, ship_flash@PAGEOFF]
    cbnz    x0, check_bullet_hit

    ldr     x1, [x19, #0]
    ldr     x2, [x19, #8]

    sub     x3, x21, x1
    cmp     x3, #0
    cneg    x3, x3, lt
    cmp     x3, #18
    bgt     check_bullet_hit

    sub     x3, x22, x2
    cmp     x3, #0
    cneg    x3, x3, lt
    cmp     x3, #18
    bgt     check_bullet_hit

    // Ship hit!
    adrp    x8, lives@PAGE
    add     x8, x8, lives@PAGEOFF
    ldr     x0, [x8]
    sub     x0, x0, #1
    str     x0, [x8]

    cbz     x0, game_over

    // Respawn ship at center with invincibility
    adrp    x8, ship_x@PAGE
    mov     x0, #400
    str     x0, [x8, ship_x@PAGEOFF]
    adrp    x8, ship_y@PAGE
    mov     x0, #240
    str     x0, [x8, ship_y@PAGEOFF]
    adrp    x8, ship_vx@PAGE
    str     xzr, [x8, ship_vx@PAGEOFF]
    adrp    x8, ship_vy@PAGE
    str     xzr, [x8, ship_vy@PAGEOFF]
    adrp    x8, ship_flash@PAGE
    mov     x0, #90                         // 1.5 seconds invincibility
    str     x0, [x8, ship_flash@PAGEOFF]
    b       update_done

game_over:
    adrp    x8, ship_alive@PAGE
    str     xzr, [x8, ship_alive@PAGEOFF]
    adrp    x8, game_state@PAGE
    mov     x0, #STATE_GAMEOVER
    str     x0, [x8, game_state@PAGEOFF]
    b       update_done

check_bullet_hit:
    stp     x19, x20, [sp, #-16]!

    ldr     x10, [x19, #0]
    ldr     x11, [x19, #8]

    adrp    x12, bullets@PAGE
    add     x12, x12, bullets@PAGEOFF
    mov     w13, #MAX_BULLETS

bul_hit_loop:
    cbz     w13, bul_hit_done
    ldr     x0, [x12, #32]
    cbz     x0, next_bul_hit

    ldr     x1, [x12, #0]
    ldr     x2, [x12, #8]

    sub     x3, x1, x10
    cmp     x3, #0
    cneg    x3, x3, lt
    cmp     x3, #15
    bgt     next_bul_hit

    sub     x3, x2, x11
    cmp     x3, #0
    cneg    x3, x3, lt
    cmp     x3, #15
    bgt     next_bul_hit

    // Hit! Deactivate both and add score
    str     xzr, [x12, #32]

    adrp    x8, score@PAGE
    add     x8, x8, score@PAGEOFF
    ldr     x0, [x8]
    add     x0, x0, #5                      // 5 points per rock
    str     x0, [x8]

    ldp     x19, x20, [sp], #16
    str     xzr, [x19, #32]

    // Decrement rocks_left and check for level complete
    adrp    x8, rocks_left@PAGE
    add     x8, x8, rocks_left@PAGEOFF
    ldr     x0, [x8]
    sub     x0, x0, #1
    str     x0, [x8]
    cbnz    x0, next_coll_obs           // Still rocks left

    // Level complete! Increment level
    adrp    x8, level@PAGE
    add     x8, x8, level@PAGEOFF
    ldr     x0, [x8]
    add     x0, x0, #1
    str     x0, [x8]

    // Bonus points
    adrp    x8, score@PAGE
    add     x8, x8, score@PAGEOFF
    ldr     x1, [x8]
    mov     x2, #5000
    add     x1, x1, x2
    str     x1, [x8]

    // Spawn new obstacles
    bl      spawn_level_obstacles
    b       update_done

next_bul_hit:
    add     x12, x12, #40
    sub     w13, w13, #1
    b       bul_hit_loop

bul_hit_done:
    ldp     x19, x20, [sp], #16

next_coll_obs:
    add     x19, x19, #40
    sub     w20, w20, #1
    b       coll_obs_loop

coll_bul_start:
    // Level completion is now handled in bullet hit code via rocks_left counter

update_done:
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Render start screen
//------------------------------------------------------------------------------
render_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Clear to dark blue
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #0
    mov     w2, #0
    mov     w3, #40
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    bl      _SDL_RenderClear

    // Draw "SPACE" title in green - antialiased lines
    // Letter S (centered, x=260) - antialiased green lines
    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #300
    mov     w2, #60
    mov     w3, #260
    mov     w4, #60
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #260
    mov     w2, #60
    mov     w3, #260
    mov     w4, #90
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #260
    mov     w2, #90
    mov     w3, #300
    mov     w4, #90
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #300
    mov     w2, #90
    mov     w3, #300
    mov     w4, #120
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #300
    mov     w2, #120
    mov     w3, #260
    mov     w4, #120
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    // Letter P (x=320) - antialiased green lines
    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #320
    mov     w2, #60
    mov     w3, #320
    mov     w4, #120
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #320
    mov     w2, #60
    mov     w3, #360
    mov     w4, #60
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #360
    mov     w2, #60
    mov     w3, #360
    mov     w4, #90
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #360
    mov     w2, #90
    mov     w3, #320
    mov     w4, #90
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    // Letter A (x=380) - antialiased green lines
    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #380
    mov     w2, #120
    mov     w3, #400
    mov     w4, #60
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #400
    mov     w2, #60
    mov     w3, #420
    mov     w4, #120
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #388
    mov     w2, #95
    mov     w3, #412
    mov     w4, #95
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    // Letter C (x=440) - antialiased green lines
    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #480
    mov     w2, #60
    mov     w3, #440
    mov     w4, #60
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #440
    mov     w2, #60
    mov     w3, #440
    mov     w4, #120
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #440
    mov     w2, #120
    mov     w3, #480
    mov     w4, #120
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    // Letter E (x=500) - antialiased green lines
    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #500
    mov     w2, #60
    mov     w3, #500
    mov     w4, #120
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #500
    mov     w2, #60
    mov     w3, #540
    mov     w4, #60
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #500
    mov     w2, #90
    mov     w3, #530
    mov     w4, #90
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #500
    mov     w2, #120
    mov     w3, #540
    mov     w4, #120
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    // Draw a big ship in center as "logo" - antialiased green lines
    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #400            // nose x
    mov     w2, #140            // nose y
    mov     w3, #340            // left x
    mov     w4, #220            // left y
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #340
    mov     w2, #220
    mov     w3, #460
    mov     w4, #220
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #460
    mov     w2, #220
    mov     w3, #400
    mov     w4, #140
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    // "PRESS SPACE" - draw as simple rectangles indicating text
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #255
    mov     w2, #255
    mov     w3, #255
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    // Draw hint bar
    adrp    x8, draw_rect@PAGE
    add     x8, x8, draw_rect@PAGEOFF
    mov     w0, #300
    str     w0, [x8, #0]
    mov     w0, #320
    str     w0, [x8, #4]
    mov     w0, #200
    str     w0, [x8, #8]
    mov     w0, #4
    str     w0, [x8, #12]

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     x1, x8
    bl      _SDL_RenderFillRect

    // Present
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    bl      _SDL_RenderPresent

    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Render game over screen
//------------------------------------------------------------------------------
render_gameover:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!

    // Clear to dark red
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #40
    mov     w2, #0
    mov     w3, #0
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    bl      _SDL_RenderClear

    // Draw "GAME OVER" indicator (red X) - glow effect
    // Pass 1: Outer glow (dim red)
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #60
    mov     w2, #0
    mov     w3, #0
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #350
    mov     w2, #140
    mov     w3, #450
    mov     w4, #240
    bl      _SDL_RenderDrawLine

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #450
    mov     w2, #140
    mov     w3, #350
    mov     w4, #240
    bl      _SDL_RenderDrawLine

    // Pass 2: Medium glow
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #150
    mov     w2, #0
    mov     w3, #0
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #350
    mov     w2, #140
    mov     w3, #450
    mov     w4, #240
    bl      _SDL_RenderDrawLine

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #450
    mov     w2, #140
    mov     w3, #350
    mov     w4, #240
    bl      _SDL_RenderDrawLine

    // Pass 3: Bright core
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #255
    mov     w2, #0
    mov     w3, #0
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #350
    mov     w2, #140
    mov     w3, #450
    mov     w4, #240
    bl      _SDL_RenderDrawLine

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #450
    mov     w2, #140
    mov     w3, #350
    mov     w4, #240
    bl      _SDL_RenderDrawLine

    // Draw final score
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #255
    mov     w2, #255
    mov     w3, #255
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x8, score@PAGE
    ldr     x19, [x8, score@PAGEOFF]
    mov     w0, w19
    mov     w1, #350            // x position
    mov     w2, #300            // y position
    mov     w3, #3              // scale
    bl      draw_number

    // Hint bar
    adrp    x8, draw_rect@PAGE
    add     x8, x8, draw_rect@PAGEOFF
    mov     w0, #300
    str     w0, [x8, #0]
    mov     w0, #380
    str     w0, [x8, #4]
    mov     w0, #200
    str     w0, [x8, #8]
    mov     w0, #4
    str     w0, [x8, #12]

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     x1, x8
    bl      _SDL_RenderFillRect

    // Present
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    bl      _SDL_RenderPresent

    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Render game
//------------------------------------------------------------------------------
render_game:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!

    // Clear to black
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #0
    mov     w2, #0
    mov     w3, #0
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    bl      _SDL_RenderClear

    // Draw obstacles (orange)
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #200
    mov     w2, #150
    mov     w3, #50
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x19, obstacles@PAGE
    add     x19, x19, obstacles@PAGEOFF
    mov     w20, #MAX_OBSTACLES

draw_obs_loop:
    cbz     w20, draw_bullets_start
    ldr     x0, [x19, #32]
    cbz     x0, next_draw_obs

    ldr     w21, [x19, #0]
    ldr     w22, [x19, #8]

    adrp    x8, draw_rect@PAGE
    add     x8, x8, draw_rect@PAGEOFF
    str     w21, [x8, #0]
    str     w22, [x8, #4]
    mov     w0, #16
    str     w0, [x8, #8]
    str     w0, [x8, #12]

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     x1, x8
    bl      _SDL_RenderFillRect

next_draw_obs:
    add     x19, x19, #40
    sub     w20, w20, #1
    b       draw_obs_loop

draw_bullets_start:
    // Draw bullets (yellow)
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #255
    mov     w2, #255
    mov     w3, #0
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x19, bullets@PAGE
    add     x19, x19, bullets@PAGEOFF
    mov     w20, #MAX_BULLETS

draw_bul_loop:
    cbz     w20, draw_ship_start
    ldr     x0, [x19, #32]
    cbz     x0, next_draw_bul

    ldr     w21, [x19, #0]
    ldr     w22, [x19, #8]

    adrp    x8, draw_rect@PAGE
    add     x8, x8, draw_rect@PAGEOFF
    sub     w0, w21, #2
    str     w0, [x8, #0]
    sub     w0, w22, #2
    str     w0, [x8, #4]
    mov     w0, #4
    str     w0, [x8, #8]
    str     w0, [x8, #12]

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     x1, x8
    bl      _SDL_RenderFillRect

next_draw_bul:
    add     x19, x19, #40
    sub     w20, w20, #1
    b       draw_bul_loop

draw_ship_start:
    adrp    x8, ship_alive@PAGE
    ldr     x0, [x8, ship_alive@PAGEOFF]
    cbz     x0, draw_hud

    // Check if flashing (blink every 4 frames)
    adrp    x8, ship_flash@PAGE
    ldr     x0, [x8, ship_flash@PAGEOFF]
    cbz     x0, draw_ship_solid
    and     x0, x0, #4
    cbnz    x0, draw_hud              // skip drawing every other 4 frames

draw_ship_solid:
    // Green ship using aalineRGBA for antialiasing
    adrp    x8, ship_x@PAGE
    ldr     w19, [x8, ship_x@PAGEOFF]
    adrp    x8, ship_y@PAGE
    ldr     w20, [x8, ship_y@PAGEOFF]

    adrp    x8, ship_dir@PAGE
    ldr     x0, [x8, ship_dir@PAGEOFF]
    and     x0, x0, #7

    mov     x1, #48
    mul     x0, x0, x1

    adrp    x8, ship_tri@PAGE
    add     x8, x8, ship_tri@PAGEOFF
    add     x8, x8, x0

    ldr     x9, [x8, #0]
    ldr     x10, [x8, #8]
    ldr     x11, [x8, #16]
    ldr     x12, [x8, #24]
    ldr     x13, [x8, #32]
    ldr     x14, [x8, #40]

    add     w21, w19, w9
    add     w22, w20, w10
    add     w23, w19, w11
    add     w24, w20, w12
    add     w25, w19, w13
    add     w26, w20, w14

    // Draw antialiased green triangle using aalineRGBA
    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, w21
    mov     w2, w22
    mov     w3, w23
    mov     w4, w24
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, w23
    mov     w2, w24
    mov     w3, w25
    mov     w4, w26
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

    sub     sp, sp, #16
    mov     w0, #255
    str     w0, [sp]
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, w25
    mov     w2, w26
    mov     w3, w21
    mov     w4, w22
    mov     w5, #0
    mov     w6, #255
    mov     w7, #0
    bl      _aalineRGBA
    add     sp, sp, #16

draw_hud:
    // Draw lives as small green triangles - antialiased
    adrp    x8, lives@PAGE
    ldr     x19, [x8, lives@PAGEOFF]
    mov     w20, #20                        // start x

draw_lives_loop:
    cbz     x19, draw_level

    // Draw small triangle for each life - green with glow
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #0
    mov     w2, #255
    mov     w3, #0
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    add     w1, w20, #6                     // nose x
    mov     w2, #10                         // nose y
    mov     w3, w20                         // left x
    mov     w4, #25                         // left y
    bl      _SDL_RenderDrawLine

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, w20
    mov     w2, #25
    add     w3, w20, #12
    mov     w4, #25
    bl      _SDL_RenderDrawLine

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    add     w1, w20, #12
    mov     w2, #25
    add     w3, w20, #6
    mov     w4, #10
    bl      _SDL_RenderDrawLine

    add     w20, w20, #20
    sub     x19, x19, #1
    b       draw_lives_loop

draw_level:
    // Draw level number in cyan
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #0
    mov     w2, #255
    mov     w3, #255
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x8, level@PAGE
    ldr     x19, [x8, level@PAGEOFF]
    mov     w0, w19
    mov     w1, #350                        // x position (left of center)
    mov     w2, #10                         // y position
    mov     w3, #2                          // scale
    bl      draw_number

draw_rocks_left:
    // Draw rocks_left counter in red/orange for debugging
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #255
    mov     w2, #100
    mov     w3, #0
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x8, rocks_left@PAGE
    ldr     x19, [x8, rocks_left@PAGEOFF]
    mov     w0, w19
    mov     w1, #450                        // x position (right of center)
    mov     w2, #10                         // y position
    mov     w3, #2                          // scale
    bl      draw_number

draw_score:
    // Draw score in white
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #255
    mov     w2, #255
    mov     w3, #255
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x8, score@PAGE
    ldr     x19, [x8, score@PAGEOFF]
    mov     w0, w19
    mov     w1, #700                        // x position (right side)
    mov     w2, #10                         // y position
    mov     w3, #2                          // scale
    bl      draw_number

draw_spawn_count:
    // Draw spawn_count in yellow (bottom left) for debugging
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     w1, #255
    mov     w2, #255
    mov     w3, #0
    mov     w4, #255
    bl      _SDL_SetRenderDrawColor

    adrp    x8, spawn_count@PAGE
    ldr     x19, [x8, spawn_count@PAGEOFF]
    mov     w0, w19
    mov     w1, #20                         // x position (left side)
    mov     w2, #450                        // y position (bottom)
    mov     w3, #2                          // scale
    bl      draw_number

render_present:
    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    bl      _SDL_RenderPresent

    ldp     x25, x26, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Draw a number at x,y with given scale
// w0 = number, w1 = x, w2 = y, w3 = scale
//------------------------------------------------------------------------------
draw_number:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!

    mov     w19, w0                         // number
    mov     w20, w1                         // x
    mov     w21, w2                         // y
    mov     w22, w3                         // scale

    // Handle zero specially
    cbnz    w19, extract_digits
    mov     w0, #0
    mov     w1, w20
    mov     w2, w21
    mov     w3, w22
    bl      draw_digit
    b       draw_num_done

extract_digits:
    // Extract digits (up to 6 digits) and store on stack
    sub     sp, sp, #16
    mov     w23, #0                         // digit count

extract_loop:
    cbz     w19, draw_digits
    mov     w0, #10
    udiv    w1, w19, w0
    msub    w0, w1, w0, w19                 // w0 = w19 % 10
    add     x8, sp, x23
    strb    w0, [x8]
    mov     w19, w1
    add     w23, w23, #1
    cmp     w23, #6
    blt     extract_loop

draw_digits:
    // Draw digits in reverse order (most significant first)
    // Calculate starting x position
    mov     w24, w22
    lsl     w24, w24, #2                    // digit width = scale * 6
    add     w24, w24, w22
    add     w24, w24, w22
    mul     w0, w23, w24
    sub     w20, w20, w0                    // adjust x to right-align

draw_digit_loop:
    cbz     w23, draw_num_cleanup
    sub     w23, w23, #1
    add     x8, sp, x23
    ldrb    w0, [x8]
    mov     w1, w20
    mov     w2, w21
    mov     w3, w22
    bl      draw_digit
    mov     w0, w22
    lsl     w0, w0, #2
    add     w0, w0, w22
    add     w0, w0, w22
    add     w20, w20, w0                    // x += scale * 6
    b       draw_digit_loop

draw_num_cleanup:
    add     sp, sp, #16

draw_num_done:
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

//------------------------------------------------------------------------------
// Draw a single digit at x,y with scale
// w0 = digit (0-9), w1 = x, w2 = y, w3 = scale
//------------------------------------------------------------------------------
draw_digit:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    stp     x19, x20, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!

    and     w0, w0, #0xF
    cmp     w0, #10
    bge     digit_done

    mov     w19, w1                         // x
    mov     w20, w2                         // y
    mov     w21, w3                         // scale

    // Get digit bitmap pointer
    mov     w1, #7
    mul     w0, w0, w1
    adrp    x8, digits@PAGE
    add     x8, x8, digits@PAGEOFF
    add     x22, x8, x0                     // pointer to 7 bytes

    mov     w23, #0                         // row

digit_row_loop:
    cmp     w23, #7
    bge     digit_done

    ldrb    w0, [x22, x23]                  // get row bitmap
    mov     w24, #0                         // col

digit_col_loop:
    cmp     w24, #5
    bge     digit_next_row

    // Check if bit is set (bit 4-col)
    mov     w1, #4
    sub     w1, w1, w24
    lsr     w2, w0, w1
    and     w2, w2, #1
    cbz     w2, digit_next_col

    // Draw pixel (scaled rectangle)
    adrp    x8, draw_rect@PAGE
    add     x8, x8, draw_rect@PAGEOFF

    mul     w1, w24, w21
    add     w1, w19, w1
    str     w1, [x8, #0]

    mul     w1, w23, w21
    add     w1, w20, w1
    str     w1, [x8, #4]

    str     w21, [x8, #8]
    str     w21, [x8, #12]

    // Preserve w0 (row bitmap)
    stp     x0, x8, [sp, #-16]!

    adrp    x0, renderer@PAGE
    ldr     x0, [x0, renderer@PAGEOFF]
    mov     x1, x8
    bl      _SDL_RenderFillRect

    ldp     x0, x8, [sp], #16

digit_next_col:
    add     w24, w24, #1
    b       digit_col_loop

digit_next_row:
    add     w23, w23, #1
    b       digit_row_loop

digit_done:
    ldp     x23, x24, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    ret

.end
