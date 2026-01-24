// SPACE - Asteroids-style game with NanoVG vector graphics
// Pure C implementation with smooth antialiased lines

#define GL_SILENCE_DEPRECATION
#include <SDL2/SDL.h>
#include <OpenGL/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

#define NANOVG_GL3_IMPLEMENTATION
#include "nanovg.h"
#include "nanovg_gl.h"

// Constants
#define SCREEN_W 800
#define SCREEN_H 480
#define MAX_OBSTACLES 20
#define MAX_BULLETS 10

// Game states
enum { STATE_START, STATE_PLAYING, STATE_GAMEOVER };

// Game modes
#define MODE_ORIGINAL 0
#define MODE_DELUXE   1

// Ship triangle vertices for 8 directions
static const float ship_tri[8][6] = {
    { 0, -10, -7, 7, 7, 7 },      // Dir 0: up
    { 7, -7, -10, 0, 0, 10 },     // Dir 1: up-right
    { 10, 0, -7, -7, -7, 7 },     // Dir 2: right
    { 7, 7, 0, -10, -10, 0 },     // Dir 3: down-right
    { 0, 10, 7, -7, -7, -7 },     // Dir 4: down
    { -7, 7, 10, 0, 0, -10 },     // Dir 5: down-left
    { -10, 0, 7, 7, 7, -7 },      // Dir 6: left
    { -7, -7, 0, 10, 10, 0 },     // Dir 7: up-left
};

// Direction vectors
static const int dir_dx[] = { 0, 2, 2, 2, 0, -2, -2, -2 };
static const int dir_dy[] = { -2, -2, 0, 2, 2, 2, 0, -2 };

// Asteroid sizes (matching Swift version)
#define SIZE_LARGE  0
#define SIZE_MEDIUM 1
#define SIZE_SMALL  2

#define MAX_ASTEROID_VERTS 24  // Large: 8 points × 3 = 24

// Obstacle structure
typedef struct {
    float x, y;
    float vx, vy;
    int active;
    int size;           // SIZE_LARGE, SIZE_MEDIUM, SIZE_SMALL
    int num_verts;      // Number of vertices in shape
    float verts[MAX_ASTEROID_VERTS][2];  // Pre-generated vertex positions
    float angle;        // Current rotation angle (deluxe mode)
    float rot_speed;    // Rotation speed (deluxe mode)
} Obstacle;

// Bullet structure
typedef struct {
    float x, y;
    float vx, vy;
    int life;
} Bullet;

// Game state
static struct {
    SDL_Window* window;
    SDL_GLContext gl_ctx;
    NVGcontext* vg;

    int running;
    int state;
    int game_mode;      // MODE_ORIGINAL or MODE_DELUXE

    // Ship
    float ship_x, ship_y;
    float ship_vx, ship_vy;
    float ship_angle;      // Rotation angle in radians (continuous)
    float rotation_rate;   // Current rotation rate
    int ship_alive;
    int ship_flash;

    // Stats
    int lives;
    int score;
    int level;
    int rocks_left;

    // Input
    int key_up, key_down, key_left, key_right, key_space;
    int key_space_prev;
    int fire_cooldown;
    int turn_cooldown;
    int thrust_cooldown;
    int friction_counter;

    // Game objects
    Obstacle obstacles[MAX_OBSTACLES];
    Bullet bullets[MAX_BULLETS];

    unsigned long random_seed;
} game;

// Random number generator
static unsigned int random_num(void) {
    game.random_seed = game.random_seed * 6364136223846793005ULL + 1;
    return (unsigned int)(game.random_seed >> 33);
}

// Random float between 0 and 1
static float random_float(void) {
    return (float)(random_num() % 10000) / 10000.0f;
}

// Generate asteroid shape (like Swift's createAsteroidPath)
static void generate_asteroid_shape(Obstacle* o, int size) {
    // Size parameters matching Swift version
    float radius;
    int base_points;

    switch (size) {
        case SIZE_LARGE:  radius = 40.0f; base_points = 8; break;
        case SIZE_MEDIUM: radius = 20.0f; base_points = 6; break;
        case SIZE_SMALL:  radius = 10.0f; base_points = 4; break;
        default:          radius = 40.0f; base_points = 8; break;
    }

    o->size = size;
    o->num_verts = base_points * 3;  // 3x points for smoother shape
    o->angle = 0;
    o->rot_speed = (random_float() - 0.5f) * 0.04f;  // Random rotation speed for deluxe mode

    float angle_step = (2.0f * M_PI) / (float)base_points;

    for (int i = 0; i < o->num_verts; i++) {
        float base_angle = angle_step * (float)i / 3.0f;

        // Radius variation based on point type
        float variation;
        if (i % 3 == 0) {
            // Main points - moderate variation (0.85 to 1.15)
            variation = 0.85f + random_float() * 0.30f;
        } else {
            // Intermediate points - more variation (0.7 to 1.2)
            variation = 0.70f + random_float() * 0.50f;
        }

        float r = radius * variation;
        o->verts[i][0] = cosf(base_angle) * r;
        o->verts[i][1] = sinf(base_angle) * r;
    }
}

// Find empty obstacle slot
static int find_empty_obstacle_slot(void) {
    for (int i = 0; i < MAX_OBSTACLES; i++) {
        if (!game.obstacles[i].active) return i;
    }
    return -1;
}

// Spawn split asteroids (2 smaller ones from a destroyed asteroid)
static void spawn_split_asteroids(float x, float y, int new_size) {
    for (int s = 0; s < 2; s++) {
        int slot = find_empty_obstacle_slot();
        if (slot < 0) return;  // No room

        Obstacle* o = &game.obstacles[slot];
        o->x = x;
        o->y = y;

        // Random velocity in opposite-ish directions
        float angle = (s == 0) ? random_float() * M_PI : random_float() * M_PI + M_PI;
        float speed = 1.0f + random_float() * 2.0f;
        o->vx = cosf(angle) * speed;
        o->vy = sinf(angle) * speed;

        generate_asteroid_shape(o, new_size);
        o->active = 1;
        game.rocks_left++;
    }
}

// Spawn obstacles for current level
static void spawn_level_obstacles(void) {
    // Clear ALL obstacle slots to inactive
    for (int i = 0; i < MAX_OBSTACLES; i++) {
        game.obstacles[i].active = 0;
    }

    // Number of obstacles = level + 2
    int count = game.level + 2;
    if (count > MAX_OBSTACLES) count = MAX_OBSTACLES;
    game.rocks_left = count;

    for (int i = 0; i < count; i++) {
        Obstacle* o = &game.obstacles[i];

        // Random X position (50-750, avoid center 350-450)
        int x = (random_num() % 700) + 50;
        if (x >= 350 && x <= 450) x += 250;
        o->x = x;

        // Random Y position (50-430)
        o->y = (random_num() % 380) + 50;

        // Random Velocity X: -1 to +2, never zero
        int vx = (random_num() & 3) - 1;
        if (vx == 0) vx = 1;
        o->vx = vx;

        // Random Velocity Y: -1 to +2, never zero
        int vy = (random_num() & 3) - 1;
        if (vy == 0) vy = -1;
        o->vy = vy;

        // Random size: 60% large, 30% medium, 10% small
        int size_roll = random_num() % 100;
        int size;
        if (size_roll < 60) size = SIZE_LARGE;
        else if (size_roll < 90) size = SIZE_MEDIUM;
        else size = SIZE_SMALL;

        generate_asteroid_shape(o, size);
        o->active = 1;
    }
}

// Initialize game
static void init_game(void) {
    game.ship_x = 400;
    game.ship_y = 240;
    game.ship_vx = 0;
    game.ship_vy = 0;
    game.ship_angle = -M_PI_2;  // Start pointing up
    game.rotation_rate = 0;
    game.ship_alive = 1;
    game.ship_flash = 0;

    game.lives = 3;
    game.score = 0;
    game.level = 1;

    // Clear bullets
    for (int i = 0; i < MAX_BULLETS; i++) {
        game.bullets[i].life = 0;
    }

    // Spawn obstacles
    spawn_level_obstacles();
}

// Process events
static void process_events(void) {
    game.key_space_prev = game.key_space;

    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) {
            game.running = 0;
        } else if (e.type == SDL_KEYDOWN) {
            switch (e.key.keysym.scancode) {
                case SDL_SCANCODE_Q: game.running = 0; break;
                case SDL_SCANCODE_UP: game.key_up = 1; break;
                case SDL_SCANCODE_DOWN: game.key_down = 1; break;
                case SDL_SCANCODE_LEFT: game.key_left = 1; break;
                case SDL_SCANCODE_RIGHT: game.key_right = 1; break;
                case SDL_SCANCODE_SPACE: game.key_space = 1; break;
                case SDL_SCANCODE_1:
                    if (game.state == STATE_START) {
                        game.game_mode = MODE_ORIGINAL;
                        game.state = STATE_PLAYING;
                    }
                    break;
                case SDL_SCANCODE_2:
                    if (game.state == STATE_START) {
                        game.game_mode = MODE_DELUXE;
                        game.state = STATE_PLAYING;
                    }
                    break;
                default: break;
            }
        } else if (e.type == SDL_KEYUP) {
            switch (e.key.keysym.scancode) {
                case SDL_SCANCODE_UP: game.key_up = 0; break;
                case SDL_SCANCODE_DOWN: game.key_down = 0; break;
                case SDL_SCANCODE_LEFT: game.key_left = 0; break;
                case SDL_SCANCODE_RIGHT: game.key_right = 0; break;
                case SDL_SCANCODE_SPACE: game.key_space = 0; break;
                default: break;
            }
        }
    }

    // State transitions on space press
    if (game.key_space && !game.key_space_prev) {
        if (game.state == STATE_START) {
            game.state = STATE_PLAYING;
        } else if (game.state == STATE_GAMEOVER) {
            init_game();
            game.state = STATE_PLAYING;
        }
    }
}

// Update game logic
static void update_game(void) {
    if (!game.ship_alive) return;

    // Decrement flash timer
    if (game.ship_flash > 0) game.ship_flash--;

    // Turning - continuous rotation like Swift version
    if (game.key_left) {
        game.rotation_rate = -0.05f;
    } else if (game.key_right) {
        game.rotation_rate = 0.05f;
    } else {
        game.rotation_rate = 0;
    }
    game.ship_angle += game.rotation_rate;

    // Thrust
    if (game.thrust_cooldown > 0) {
        game.thrust_cooldown--;
    } else if (game.key_up || game.key_down) {
        game.thrust_cooldown = 6;

        float dx = cosf(game.ship_angle);
        float dy = sinf(game.ship_angle);

        if (game.key_up) {
            game.ship_vx += dx;
            game.ship_vy += dy;
        } else {
            game.ship_vx -= dx;
            game.ship_vy -= dy;
        }

        // Clamp velocity
        if (game.ship_vx > 6) game.ship_vx = 6;
        if (game.ship_vx < -6) game.ship_vx = -6;
        if (game.ship_vy > 6) game.ship_vy = 6;
        if (game.ship_vy < -6) game.ship_vy = -6;
    }

    // Fire
    if (game.fire_cooldown > 0) {
        game.fire_cooldown--;
    } else if (game.key_space && game.state == STATE_PLAYING) {
        game.fire_cooldown = 12;

        for (int i = 0; i < MAX_BULLETS; i++) {
            if (game.bullets[i].life == 0) {
                game.bullets[i].x = game.ship_x;
                game.bullets[i].y = game.ship_y;
                game.bullets[i].vx = cosf(game.ship_angle) * 8;
                game.bullets[i].vy = sinf(game.ship_angle) * 8;
                game.bullets[i].life = 60;
                break;
            }
        }
    }

    // Apply velocity
    game.ship_x += game.ship_vx;
    game.ship_y += game.ship_vy;

    // Wrap around
    if (game.ship_x >= SCREEN_W) game.ship_x -= SCREEN_W;
    if (game.ship_x < 0) game.ship_x += SCREEN_W;
    if (game.ship_y >= SCREEN_H) game.ship_y -= SCREEN_H;
    if (game.ship_y < 0) game.ship_y += SCREEN_H;

    // Friction
    game.friction_counter++;
    if (game.friction_counter >= 30) {
        game.friction_counter = 0;
        if (game.ship_vx > 0) game.ship_vx--;
        else if (game.ship_vx < 0) game.ship_vx++;
        if (game.ship_vy > 0) game.ship_vy--;
        else if (game.ship_vy < 0) game.ship_vy++;
    }

    // Update bullets
    for (int i = 0; i < MAX_BULLETS; i++) {
        Bullet* b = &game.bullets[i];
        if (b->life > 0) {
            b->life--;
            b->x += b->vx;
            b->y += b->vy;

            if (b->x < 0 || b->x >= SCREEN_W || b->y < 0 || b->y >= SCREEN_H) {
                b->life = 0;
            }
        }
    }

    // Update obstacles
    for (int i = 0; i < MAX_OBSTACLES; i++) {
        Obstacle* o = &game.obstacles[i];
        if (o->active) {
            o->x += o->vx;
            o->y += o->vy;

            // Rotate asteroids in deluxe mode
            if (game.game_mode == MODE_DELUXE) {
                o->angle += o->rot_speed;
            }

            if (o->x >= SCREEN_W) o->x -= SCREEN_W;
            if (o->x < 0) o->x += SCREEN_W;
            if (o->y >= SCREEN_H) o->y -= SCREEN_H;
            if (o->y < 0) o->y += SCREEN_H;
        }
    }

    // Check collisions
    for (int i = 0; i < MAX_OBSTACLES; i++) {
        Obstacle* o = &game.obstacles[i];
        if (!o->active) continue;

        // Get collision radius based on asteroid size
        float hit_radius;
        switch (o->size) {
            case SIZE_LARGE:  hit_radius = 35.0f; break;
            case SIZE_MEDIUM: hit_radius = 18.0f; break;
            case SIZE_SMALL:  hit_radius = 9.0f;  break;
            default:          hit_radius = 35.0f; break;
        }

        // Ship collision (if not flashing)
        if (game.ship_flash == 0) {
            float dx = game.ship_x - o->x;
            float dy = game.ship_y - o->y;
            float dist = sqrtf(dx*dx + dy*dy);
            if (dist < hit_radius + 8) {  // 8 = ship radius
                game.lives--;
                if (game.lives <= 0) {
                    game.ship_alive = 0;
                    game.state = STATE_GAMEOVER;
                } else {
                    game.ship_x = 400;
                    game.ship_y = 240;
                    game.ship_vx = 0;
                    game.ship_vy = 0;
                    game.ship_angle = -M_PI_2;  // Reset to pointing up
                    game.rotation_rate = 0;
                    game.ship_flash = 90;
                }
                return;
            }
        }

        // Bullet collision
        for (int j = 0; j < MAX_BULLETS; j++) {
            Bullet* b = &game.bullets[j];
            if (b->life > 0) {
                float dx = b->x - o->x;
                float dy = b->y - o->y;
                float dist = sqrtf(dx*dx + dy*dy);
                if (dist < hit_radius) {
                    // Hit!
                    b->life = 0;
                    float hit_x = o->x;
                    float hit_y = o->y;
                    int hit_size = o->size;
                    o->active = 0;
                    game.rocks_left--;

                    // Score: small=100, medium=50, large=20 (like original)
                    switch (hit_size) {
                        case SIZE_LARGE:  game.score += 20;  break;
                        case SIZE_MEDIUM: game.score += 50;  break;
                        case SIZE_SMALL:  game.score += 100; break;
                    }

                    // Split into smaller asteroids
                    if (hit_size == SIZE_LARGE) {
                        spawn_split_asteroids(hit_x, hit_y, SIZE_MEDIUM);
                    } else if (hit_size == SIZE_MEDIUM) {
                        spawn_split_asteroids(hit_x, hit_y, SIZE_SMALL);
                    }
                    // Small asteroids just disappear

                    // Check for level complete
                    if (game.rocks_left <= 0) {
                        game.level++;
                        game.score += 5000;
                        spawn_level_obstacles();
                        return;
                    }
                    break;
                }
            }
        }
    }
}

// Draw a single digit at position
static void draw_digit(NVGcontext* vg, int d, float x, float y, float scale) {
    float w = 4 * scale;
    float h = 6 * scale;
    float hh = 3 * scale;

    nvgBeginPath(vg);

    switch (d) {
        case 0:
            nvgMoveTo(vg, x, y);
            nvgLineTo(vg, x + w, y);
            nvgLineTo(vg, x + w, y + h);
            nvgLineTo(vg, x, y + h);
            nvgClosePath(vg);
            break;
        case 1:
            nvgMoveTo(vg, x + w/2, y);
            nvgLineTo(vg, x + w/2, y + h);
            break;
        case 2:
            nvgMoveTo(vg, x, y);
            nvgLineTo(vg, x + w, y);
            nvgLineTo(vg, x + w, y + hh);
            nvgLineTo(vg, x, y + hh);
            nvgLineTo(vg, x, y + h);
            nvgLineTo(vg, x + w, y + h);
            break;
        case 3:
            nvgMoveTo(vg, x, y);
            nvgLineTo(vg, x + w, y);
            nvgLineTo(vg, x + w, y + h);
            nvgLineTo(vg, x, y + h);
            nvgMoveTo(vg, x, y + hh);
            nvgLineTo(vg, x + w, y + hh);
            break;
        case 4:
            nvgMoveTo(vg, x, y);
            nvgLineTo(vg, x, y + hh);
            nvgLineTo(vg, x + w, y + hh);
            nvgMoveTo(vg, x + w, y);
            nvgLineTo(vg, x + w, y + h);
            break;
        case 5:
            nvgMoveTo(vg, x + w, y);
            nvgLineTo(vg, x, y);
            nvgLineTo(vg, x, y + hh);
            nvgLineTo(vg, x + w, y + hh);
            nvgLineTo(vg, x + w, y + h);
            nvgLineTo(vg, x, y + h);
            break;
        case 6:
            nvgMoveTo(vg, x + w, y);
            nvgLineTo(vg, x, y);
            nvgLineTo(vg, x, y + h);
            nvgLineTo(vg, x + w, y + h);
            nvgLineTo(vg, x + w, y + hh);
            nvgLineTo(vg, x, y + hh);
            break;
        case 7:
            nvgMoveTo(vg, x, y);
            nvgLineTo(vg, x + w, y);
            nvgLineTo(vg, x + w, y + h);
            break;
        case 8:
            nvgMoveTo(vg, x, y);
            nvgLineTo(vg, x + w, y);
            nvgLineTo(vg, x + w, y + h);
            nvgLineTo(vg, x, y + h);
            nvgClosePath(vg);
            nvgMoveTo(vg, x, y + hh);
            nvgLineTo(vg, x + w, y + hh);
            break;
        case 9:
            nvgMoveTo(vg, x + w, y + h);
            nvgLineTo(vg, x + w, y);
            nvgLineTo(vg, x, y);
            nvgLineTo(vg, x, y + hh);
            nvgLineTo(vg, x + w, y + hh);
            break;
    }
    nvgStroke(vg);
}

// Draw a number using vector lines
static void draw_number(NVGcontext* vg, int num, float x, float y, float scale) {
    char buf[16];
    sprintf(buf, "%d", num);

    // Calculate total width to right-align
    int len = (int)strlen(buf);
    float digit_w = 6 * scale;
    float start_x = x - (len * digit_w);

    for (int i = 0; buf[i]; i++) {
        int d = buf[i] - '0';
        if (d >= 0 && d <= 9) {
            draw_digit(vg, d, start_x + i * digit_w, y, scale);
        }
    }
}

// Render start screen
static void render_start(void) {
    NVGcontext* vg = game.vg;

    glClearColor(0, 0, 0.15f, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

    int winW, winH, fbW, fbH;
    SDL_GetWindowSize(game.window, &winW, &winH);
    SDL_GL_GetDrawableSize(game.window, &fbW, &fbH);
    float pxRatio = (float)fbW / (float)winW;

    nvgBeginFrame(vg, winW, winH, pxRatio);

    // Draw "SPACE" title
    nvgStrokeColor(vg, nvgRGB(0, 255, 0));
    nvgStrokeWidth(vg, 2.0f);

    // S
    nvgBeginPath(vg);
    nvgMoveTo(vg, 300, 60); nvgLineTo(vg, 260, 60);
    nvgLineTo(vg, 260, 90); nvgLineTo(vg, 300, 90);
    nvgLineTo(vg, 300, 120); nvgLineTo(vg, 260, 120);
    nvgStroke(vg);

    // P
    nvgBeginPath(vg);
    nvgMoveTo(vg, 320, 120); nvgLineTo(vg, 320, 60);
    nvgLineTo(vg, 360, 60); nvgLineTo(vg, 360, 90);
    nvgLineTo(vg, 320, 90);
    nvgStroke(vg);

    // A
    nvgBeginPath(vg);
    nvgMoveTo(vg, 380, 120); nvgLineTo(vg, 400, 60);
    nvgLineTo(vg, 420, 120);
    nvgMoveTo(vg, 388, 95); nvgLineTo(vg, 412, 95);
    nvgStroke(vg);

    // C
    nvgBeginPath(vg);
    nvgMoveTo(vg, 480, 60); nvgLineTo(vg, 440, 60);
    nvgLineTo(vg, 440, 120); nvgLineTo(vg, 480, 120);
    nvgStroke(vg);

    // E
    nvgBeginPath(vg);
    nvgMoveTo(vg, 540, 60); nvgLineTo(vg, 500, 60);
    nvgLineTo(vg, 500, 120); nvgLineTo(vg, 540, 120);
    nvgMoveTo(vg, 500, 90); nvgLineTo(vg, 530, 90);
    nvgStroke(vg);

    // Big ship logo
    nvgStrokeWidth(vg, 1.5f);
    nvgBeginPath(vg);
    nvgMoveTo(vg, 400, 140);  // nose
    nvgLineTo(vg, 340, 220);  // left
    nvgLineTo(vg, 460, 220);  // right
    nvgClosePath(vg);
    nvgStroke(vg);

    // Menu options - aligned text
    nvgStrokeColor(vg, nvgRGB(255, 255, 255));
    nvgStrokeWidth(vg, 1.5f);

    // Row 1: "1  ORIGINAL" at y=280-300
    float y1 = 280;
    // "1" - same size as "2" (20px tall)
    nvgBeginPath(vg);
    nvgMoveTo(vg, 255, y1+3); nvgLineTo(vg, 262, y1); nvgLineTo(vg, 262, y1+20);
    nvgMoveTo(vg, 252, y1+20); nvgLineTo(vg, 272, y1+20);
    nvgStroke(vg);

    // "ORIGINAL" - each letter 12px wide, starting at x=290
    nvgStrokeWidth(vg, 1.2f);
    float x = 290;
    // O
    nvgBeginPath(vg);
    nvgMoveTo(vg, x, y1); nvgLineTo(vg, x+10, y1); nvgLineTo(vg, x+10, y1+20);
    nvgLineTo(vg, x, y1+20); nvgClosePath(vg);
    nvgStroke(vg);
    x += 14;
    // R
    nvgBeginPath(vg);
    nvgMoveTo(vg, x, y1+20); nvgLineTo(vg, x, y1); nvgLineTo(vg, x+10, y1);
    nvgLineTo(vg, x+10, y1+10); nvgLineTo(vg, x, y1+10);
    nvgMoveTo(vg, x+2, y1+10); nvgLineTo(vg, x+10, y1+20);
    nvgStroke(vg);
    x += 14;
    // I
    nvgBeginPath(vg);
    nvgMoveTo(vg, x+5, y1); nvgLineTo(vg, x+5, y1+20);
    nvgStroke(vg);
    x += 14;
    // G
    nvgBeginPath(vg);
    nvgMoveTo(vg, x+10, y1); nvgLineTo(vg, x, y1); nvgLineTo(vg, x, y1+20);
    nvgLineTo(vg, x+10, y1+20); nvgLineTo(vg, x+10, y1+10); nvgLineTo(vg, x+5, y1+10);
    nvgStroke(vg);
    x += 14;
    // I
    nvgBeginPath(vg);
    nvgMoveTo(vg, x+5, y1); nvgLineTo(vg, x+5, y1+20);
    nvgStroke(vg);
    x += 14;
    // N
    nvgBeginPath(vg);
    nvgMoveTo(vg, x, y1+20); nvgLineTo(vg, x, y1); nvgLineTo(vg, x+10, y1+20);
    nvgLineTo(vg, x+10, y1);
    nvgStroke(vg);
    x += 14;
    // A
    nvgBeginPath(vg);
    nvgMoveTo(vg, x, y1+20); nvgLineTo(vg, x+5, y1); nvgLineTo(vg, x+10, y1+20);
    nvgMoveTo(vg, x+2, y1+12); nvgLineTo(vg, x+8, y1+12);
    nvgStroke(vg);
    x += 14;
    // L
    nvgBeginPath(vg);
    nvgMoveTo(vg, x, y1); nvgLineTo(vg, x, y1+20); nvgLineTo(vg, x+10, y1+20);
    nvgStroke(vg);
    x += 14;
    // Line after text
    nvgBeginPath(vg);
    nvgMoveTo(vg, x+5, y1+10); nvgLineTo(vg, 550, y1+10);
    nvgStroke(vg);

    // Row 2: "2  DELUXE" at y=330-350
    float y2 = 330;
    nvgStrokeWidth(vg, 1.5f);
    // "2" - same size as "1" (20px tall)
    nvgBeginPath(vg);
    nvgMoveTo(vg, 252, y2); nvgLineTo(vg, 272, y2); nvgLineTo(vg, 272, y2+10);
    nvgLineTo(vg, 252, y2+10); nvgLineTo(vg, 252, y2+20); nvgLineTo(vg, 272, y2+20);
    nvgStroke(vg);

    // "DELUXE"
    nvgStrokeWidth(vg, 1.2f);
    x = 290;
    // D
    nvgBeginPath(vg);
    nvgMoveTo(vg, x, y2); nvgLineTo(vg, x, y2+20); nvgLineTo(vg, x+7, y2+20);
    nvgLineTo(vg, x+10, y2+15); nvgLineTo(vg, x+10, y2+5); nvgLineTo(vg, x+7, y2);
    nvgClosePath(vg);
    nvgStroke(vg);
    x += 14;
    // E
    nvgBeginPath(vg);
    nvgMoveTo(vg, x+10, y2); nvgLineTo(vg, x, y2); nvgLineTo(vg, x, y2+20);
    nvgLineTo(vg, x+10, y2+20);
    nvgMoveTo(vg, x, y2+10); nvgLineTo(vg, x+8, y2+10);
    nvgStroke(vg);
    x += 14;
    // L
    nvgBeginPath(vg);
    nvgMoveTo(vg, x, y2); nvgLineTo(vg, x, y2+20); nvgLineTo(vg, x+10, y2+20);
    nvgStroke(vg);
    x += 14;
    // U
    nvgBeginPath(vg);
    nvgMoveTo(vg, x, y2); nvgLineTo(vg, x, y2+20); nvgLineTo(vg, x+10, y2+20);
    nvgLineTo(vg, x+10, y2);
    nvgStroke(vg);
    x += 14;
    // X
    nvgBeginPath(vg);
    nvgMoveTo(vg, x, y2); nvgLineTo(vg, x+10, y2+20);
    nvgMoveTo(vg, x+10, y2); nvgLineTo(vg, x, y2+20);
    nvgStroke(vg);
    x += 14;
    // E
    nvgBeginPath(vg);
    nvgMoveTo(vg, x+10, y2); nvgLineTo(vg, x, y2); nvgLineTo(vg, x, y2+20);
    nvgLineTo(vg, x+10, y2+20);
    nvgMoveTo(vg, x, y2+10); nvgLineTo(vg, x+8, y2+10);
    nvgStroke(vg);
    x += 14;
    // Line after text
    nvgBeginPath(vg);
    nvgMoveTo(vg, x+5, y2+10); nvgLineTo(vg, 550, y2+10);
    nvgStroke(vg);

    nvgEndFrame(vg);
    SDL_GL_SwapWindow(game.window);
}

// Render game over screen
static void render_gameover(void) {
    NVGcontext* vg = game.vg;

    glClearColor(0.15f, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

    int winW, winH, fbW, fbH;
    SDL_GetWindowSize(game.window, &winW, &winH);
    SDL_GL_GetDrawableSize(game.window, &fbW, &fbH);
    float pxRatio = (float)fbW / (float)winW;

    nvgBeginFrame(vg, winW, winH, pxRatio);

    // Red X
    nvgStrokeColor(vg, nvgRGB(255, 0, 0));
    nvgStrokeWidth(vg, 3.0f);
    nvgBeginPath(vg);
    nvgMoveTo(vg, 350, 140);
    nvgLineTo(vg, 450, 240);
    nvgMoveTo(vg, 450, 140);
    nvgLineTo(vg, 350, 240);
    nvgStroke(vg);

    // Final score
    nvgStrokeColor(vg, nvgRGB(255, 255, 255));
    nvgStrokeWidth(vg, 1.5f);
    draw_number(vg, game.score, 350, 300, 3);

    // Hint bar
    nvgStrokeWidth(vg, 1.0f);
    nvgBeginPath(vg);
    nvgMoveTo(vg, 300, 380);
    nvgLineTo(vg, 500, 380);
    nvgStroke(vg);

    nvgEndFrame(vg);
    SDL_GL_SwapWindow(game.window);
}

// Render game
static void render_game(void) {
    NVGcontext* vg = game.vg;

    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

    int winW, winH, fbW, fbH;
    SDL_GetWindowSize(game.window, &winW, &winH);
    SDL_GL_GetDrawableSize(game.window, &fbW, &fbH);
    float pxRatio = (float)fbW / (float)winW;

    nvgBeginFrame(vg, winW, winH, pxRatio);

    // Draw asteroids with proper shapes
    nvgStrokeColor(vg, nvgRGB(200, 150, 50));  // Original brown color
    nvgStrokeWidth(vg, 1.5f);
    for (int i = 0; i < MAX_OBSTACLES; i++) {
        Obstacle* o = &game.obstacles[i];
        if (o->active && o->num_verts > 0) {
            nvgSave(vg);
            nvgTranslate(vg, o->x, o->y);
            if (game.game_mode == MODE_DELUXE) {
                nvgRotate(vg, o->angle);
            }
            nvgBeginPath(vg);
            nvgMoveTo(vg, o->verts[0][0], o->verts[0][1]);
            for (int v = 1; v < o->num_verts; v++) {
                nvgLineTo(vg, o->verts[v][0], o->verts[v][1]);
            }
            nvgClosePath(vg);
            nvgStroke(vg);
            nvgRestore(vg);
        }
    }

    // Draw bullets
    nvgStrokeColor(vg, nvgRGB(255, 255, 0));
    nvgStrokeWidth(vg, 1.0f);
    for (int i = 0; i < MAX_BULLETS; i++) {
        Bullet* b = &game.bullets[i];
        if (b->life > 0) {
            nvgBeginPath(vg);
            nvgCircle(vg, b->x, b->y, 2);
            nvgStroke(vg);
        }
    }

    // Draw ship - rotate around center point
    if (game.ship_alive && (game.ship_flash == 0 || (game.ship_flash & 4) == 0)) {
        nvgStrokeColor(vg, nvgRGB(0, 255, 0));
        nvgStrokeWidth(vg, 1.0f);

        nvgSave(vg);
        nvgTranslate(vg, game.ship_x, game.ship_y);
        nvgRotate(vg, game.ship_angle + M_PI_2);  // +90° because ship points up

        // Ship triangle at origin (pointing up before rotation)
        nvgBeginPath(vg);
        nvgMoveTo(vg, 0, -10);   // nose
        nvgLineTo(vg, -7, 7);    // left wing
        nvgLineTo(vg, 7, 7);     // right wing
        nvgClosePath(vg);
        nvgStroke(vg);
        nvgRestore(vg);
    }

    // Draw HUD - lives
    nvgStrokeColor(vg, nvgRGB(0, 255, 0));
    nvgStrokeWidth(vg, 1.0f);
    for (int i = 0; i < game.lives; i++) {
        float lx = 20 + i * 20;
        nvgBeginPath(vg);
        nvgMoveTo(vg, lx + 6, 10);
        nvgLineTo(vg, lx, 25);
        nvgLineTo(vg, lx + 12, 25);
        nvgClosePath(vg);
        nvgStroke(vg);
    }

    // Level (cyan)
    nvgStrokeColor(vg, nvgRGB(0, 255, 255));
    draw_number(vg, game.level, 350, 10, 2);

    // Rocks left (orange)
    nvgStrokeColor(vg, nvgRGB(255, 100, 0));
    draw_number(vg, game.rocks_left, 450, 10, 2);

    // Score (white)
    nvgStrokeColor(vg, nvgRGB(255, 255, 255));
    draw_number(vg, game.score, 700, 10, 2);

    nvgEndFrame(vg);
    SDL_GL_SwapWindow(game.window);
}

int main(int argc, char* argv[]) {
    (void)argc; (void)argv;

    // Initialize SDL
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        printf("SDL init failed: %s\n", SDL_GetError());
        return 1;
    }

    // Set OpenGL attributes
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);

    // Create window
    game.window = SDL_CreateWindow(
        "SPACE - Arrow Keys, Space to Fire, Q to Quit",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        SCREEN_W, SCREEN_H,
        SDL_WINDOW_SHOWN | SDL_WINDOW_OPENGL | SDL_WINDOW_ALLOW_HIGHDPI
    );
    if (!game.window) {
        printf("Window creation failed: %s\n", SDL_GetError());
        return 1;
    }

    // Create OpenGL context
    game.gl_ctx = SDL_GL_CreateContext(game.window);
    if (!game.gl_ctx) {
        printf("GL context creation failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_GL_SetSwapInterval(1);  // VSync

    // Create NanoVG context
    game.vg = nvgCreateGL3(NVG_ANTIALIAS | NVG_STENCIL_STROKES);
    if (!game.vg) {
        printf("NanoVG creation failed\n");
        return 1;
    }

    // Initialize game
    game.random_seed = (unsigned long)time(NULL);
    game.running = 1;
    game.state = STATE_START;
    init_game();

    // Main loop
    while (game.running) {
        process_events();

        if (game.state == STATE_START) {
            render_start();
        } else if (game.state == STATE_PLAYING) {
            update_game();
            render_game();
        } else {
            render_gameover();
        }
    }

    // Cleanup
    nvgDeleteGL3(game.vg);
    SDL_GL_DeleteContext(game.gl_ctx);
    SDL_DestroyWindow(game.window);
    SDL_Quit();

    return 0;
}
