// NanoVG wrapper for ARM64 assembly
#define GL_SILENCE_DEPRECATION
#include <OpenGL/gl3.h>

#define NANOVG_GL3_IMPLEMENTATION
#include "nanovg/src/nanovg.h"
#include "nanovg/src/nanovg_gl.h"

static NVGcontext* vg = NULL;

// Initialize NanoVG - call after creating OpenGL context
int nvg_init(void) {
    vg = nvgCreateGL3(NVG_ANTIALIAS | NVG_STENCIL_STROKES);
    return vg ? 0 : -1;
}

// Cleanup
void nvg_cleanup(void) {
    if (vg) nvgDeleteGL3(vg);
    vg = NULL;
}

// Begin frame - call with window width, height, pixel ratio
void nvg_begin_frame(int w, int h, float ratio) {
    nvgBeginFrame(vg, w, h, ratio);
}

// End frame
void nvg_end_frame(void) {
    nvgEndFrame(vg);
}

// Set stroke color (RGB 0-255)
void nvg_stroke_color(int r, int g, int b) {
    nvgStrokeColor(vg, nvgRGB(r, g, b));
}

// Set stroke width
void nvg_stroke_width(float w) {
    nvgStrokeWidth(vg, w);
}

// Draw a line from (x1,y1) to (x2,y2)
void nvg_line(float x1, float y1, float x2, float y2) {
    nvgBeginPath(vg);
    nvgMoveTo(vg, x1, y1);
    nvgLineTo(vg, x2, y2);
    nvgStroke(vg);
}

// Draw a triangle (3 points)
void nvg_triangle(float x1, float y1, float x2, float y2, float x3, float y3) {
    nvgBeginPath(vg);
    nvgMoveTo(vg, x1, y1);
    nvgLineTo(vg, x2, y2);
    nvgLineTo(vg, x3, y3);
    nvgClosePath(vg);
    nvgStroke(vg);
}

// Draw filled rectangle
void nvg_fill_rect(float x, float y, float w, float h, int r, int g, int b) {
    nvgBeginPath(vg);
    nvgRect(vg, x, y, w, h);
    nvgFillColor(vg, nvgRGB(r, g, b));
    nvgFill(vg);
}

// Clear screen with color
void nvg_clear(float r, float g, float b) {
    glClearColor(r, g, b, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
}
