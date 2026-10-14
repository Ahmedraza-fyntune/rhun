/* A stand-in keyboard for headless Sway, with the keymap in the file named on the command line.
   Each line on stdin is "key CODE PRESSED" (an evdev key code, 1 down, 0 up) or "mods DEPRESSED
   LATCHED LOCKED GROUP" (the keymap's modifier masks, as a compositor sends them); "ok" follows
   once Sway has it. The keyboard is made before "ready", so a client started after it has a seat
   keyboard from the start. */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

static const struct wl_interface *no_types[] = {NULL, NULL, NULL, NULL};
static const struct wl_message keyboard_requests[] = {
    {"keymap", "uhu", no_types}, {"key", "uuu", no_types},
    {"modifiers", "uuuu", no_types}, {"destroy", "", no_types},
};
static const struct wl_interface keyboard_interface = {
    "zwp_virtual_keyboard_v1", 1, 4, keyboard_requests, 0, NULL,
};
static const struct wl_interface *manager_types[] = {&wl_seat_interface, &keyboard_interface};
static const struct wl_message manager_requests[] = {
    {"create_virtual_keyboard", "on", manager_types},
};
static const struct wl_interface manager_interface = {
    "zwp_virtual_keyboard_manager_v1", 1, 1, manager_requests, 0, NULL,
};

static struct wl_seat *seat;
static struct wl_proxy *manager;

static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    if (!strcmp(interface, "wl_seat"))
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (!strcmp(interface, manager_interface.name))
        manager = wl_registry_bind(registry, name, &manager_interface, 1);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {
    .global = global, .global_remove = global_remove,
};

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: wayland-keyboard KEYMAP\n");
        return 1;
    }
    FILE *file = fopen(argv[1], "rb");
    if (!file) {
        perror(argv[1]);
        return 1;
    }
    static char keymap[1 << 20];
    size_t size = fread(keymap, 1, sizeof keymap - 1, file);
    fclose(file);
    keymap[size++] = 0;
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "cannot connect to Wayland\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!seat || !manager) {
        fprintf(stderr, "no virtual keyboard manager\n");
        return 1;
    }
    struct wl_proxy *keyboard = wl_proxy_marshal_flags(manager, 0, &keyboard_interface, 1, 0,
                                                       seat, NULL);
    int fd = memfd_create("keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, keymap, size) != (ssize_t)size) {
        fprintf(stderr, "cannot pass the keymap\n");
        return 1;
    }
    wl_proxy_marshal_flags(keyboard, 0, NULL, 1, 0, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd,
                           (uint32_t)size);
    close(fd);
    wl_display_roundtrip(display);
    printf("ready\n");
    fflush(stdout);
    uint32_t time = 0;
    char word[16];
    while (scanf("%15s", word) == 1) {
        if (!strcmp(word, "key")) {
            unsigned code, pressed;
            if (scanf("%u %u", &code, &pressed) != 2)
                break;
            wl_proxy_marshal_flags(keyboard, 1, NULL, 1, 0, ++time, code, pressed);
        } else if (!strcmp(word, "mods")) {
            unsigned depressed, latched, locked, group;
            if (scanf("%u %u %u %u", &depressed, &latched, &locked, &group) != 4)
                break;
            wl_proxy_marshal_flags(keyboard, 2, NULL, 1, 0, depressed, latched, locked, group);
        } else {
            break;
        }
        wl_display_roundtrip(display);
        printf("ok\n");
        fflush(stdout);
    }
    wl_proxy_marshal_flags(keyboard, 3, NULL, 1, WL_MARSHAL_FLAG_DESTROY);
    wl_display_roundtrip(display);
    wl_display_disconnect(display);
    return 0;
}
