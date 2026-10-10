// A virtual pointer for the nested test session: vpointer W H STEP...
// W H is the output size. STEP: move X Y | down | up | wait MS | drag X1 Y1 X2 Y2.
// It talks to WAYLAND_DISPLAY only; the tests give it the nested compositor's socket.
#define _DEFAULT_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

#define BTN_LEFT 0x110

static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *manager;

static void on_global(void *data, struct wl_registry *reg, uint32_t name, const char *iface, uint32_t version)
{
    (void)data;
    (void)version;
    if (!strcmp(iface, "wl_seat") && !seat)
        seat = wl_registry_bind(reg, name, &wl_seat_interface, 1);
    else if (!strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name))
        manager = wl_registry_bind(reg, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void on_remove(void *data, struct wl_registry *reg, uint32_t name)
{
    (void)data;
    (void)reg;
    (void)name;
}
static const struct wl_registry_listener listener = { on_global, on_remove };

static uint32_t now(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static struct wl_display *display;
static struct zwlr_virtual_pointer_v1 *ptr;
static uint32_t width, height;

static void at(int x, int y)
{
    zwlr_virtual_pointer_v1_motion_absolute(ptr, now(), (uint32_t)x, (uint32_t)y, width, height);
    zwlr_virtual_pointer_v1_frame(ptr);
}

static void button(int down)
{
    zwlr_virtual_pointer_v1_button(ptr, now(), BTN_LEFT, down ? 1 : 0);
    zwlr_virtual_pointer_v1_frame(ptr);
}

static void pause_ms(int ms)
{
    wl_display_roundtrip(display);
    usleep((useconds_t)ms * 1000);
}

int main(int argc, char **argv)
{
    if (argc < 4)
        return 2;
    width = (uint32_t)atoi(argv[1]);
    height = (uint32_t)atoi(argv[2]);
    display = wl_display_connect(NULL);
    if (!display)
        return 3;
    struct wl_registry *reg = wl_display_get_registry(display);
    wl_registry_add_listener(reg, &listener, NULL);
    wl_display_roundtrip(display);
    if (!manager || !seat)
        return 4;
    ptr = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
    for (int i = 3; i < argc; i++) {
        if (!strcmp(argv[i], "move") && i + 2 < argc) {
            at(atoi(argv[i + 1]), atoi(argv[i + 2]));
            i += 2;
        } else if (!strcmp(argv[i], "down") || !strcmp(argv[i], "up")) {
            button(argv[i][0] == 'd');
        } else if (!strcmp(argv[i], "wait") && i + 1 < argc) {
            pause_ms(atoi(argv[i + 1]));
            i += 1;
        } else if (!strcmp(argv[i], "drag") && i + 4 < argc) {
            int x1 = atoi(argv[i + 1]), y1 = atoi(argv[i + 2]), x2 = atoi(argv[i + 3]), y2 = atoi(argv[i + 4]);
            at(x1, y1);
            pause_ms(150);
            button(1);
            pause_ms(150);
            for (int s = 1; s <= 20; s++) {
                at(x1 + (x2 - x1) * s / 20, y1 + (y2 - y1) * s / 20);
                pause_ms(30);
            }
            pause_ms(200);
            button(0);
            i += 4;
        } else {
            return 2;
        }
        wl_display_roundtrip(display);
    }
    zwlr_virtual_pointer_v1_destroy(ptr);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
