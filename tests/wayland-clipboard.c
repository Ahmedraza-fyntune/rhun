/* Private-compositor clipboard peers with explicit transfer handshakes. */
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <wayland-client.h>

static const struct wl_interface dc_source, dc_device, dc_offer;
static const struct wl_interface *manager_source_types[] = {&dc_source};
static const struct wl_interface *manager_device_types[] = {&dc_device, &wl_seat_interface};
static const struct wl_message manager_requests[] = {
    {"create_data_source", "n", manager_source_types},
    {"get_data_device", "no", manager_device_types}, {"destroy", "", NULL},
};
static const struct wl_interface dc_manager = {
    "zwlr_data_control_manager_v1", 1, 3, manager_requests, 0, NULL,
};
static const struct wl_message source_requests[] = {
    {"offer", "s", NULL}, {"destroy", "", NULL},
};
static const struct wl_message source_events[] = {
    {"send", "sh", NULL}, {"cancelled", "", NULL},
};
static const struct wl_interface dc_source = {
    "zwlr_data_control_source_v1", 1, 2, source_requests, 2, source_events,
};
static const struct wl_interface *device_selection_types[] = {&dc_source};
static const struct wl_message device_requests[] = {
    {"set_selection", "?o", device_selection_types}, {"destroy", "", NULL},
};
static const struct wl_interface *device_offer_types[] = {&dc_offer};
static const struct wl_message device_events[] = {
    {"data_offer", "n", device_offer_types}, {"selection", "?o", device_offer_types},
    {"finished", "", NULL},
};
static const struct wl_interface dc_device = {
    "zwlr_data_control_device_v1", 1, 2, device_requests, 3, device_events,
};
static const struct wl_message offer_requests[] = {
    {"receive", "sh", NULL}, {"destroy", "", NULL},
};
static const struct wl_message offer_events[] = {{"offer", "s", NULL}};
static const struct wl_interface dc_offer = {
    "zwlr_data_control_offer_v1", 1, 2, offer_requests, 1, offer_events,
};

static struct wl_display *display;
static struct wl_seat *seat;
static struct wl_proxy *manager, *source, *current_offer;
static const char native_mime[] = "application/x-rhun-clipboard-v1";
static unsigned char *payload, *native_payload;
static size_t native_length, transfer_length;
static const unsigned char *transfer_payload;
static int distinct_formats;
static struct wl_proxy *latest_offer;
static unsigned latest_formats, current_formats;
static size_t payload_length, sent;
static int transfer_fd = -1, receiving;
static const char *receive_path, *receive_mime;

static void fail(const char *message) {
    fprintf(stderr, "wayland clipboard fixture: %s\n", message);
    exit(1);
}
static void source_send(void *data, struct wl_proxy *object, const char *mime, int32_t fd) {
    struct stat st;
    if (transfer_fd >= 0 || fstat(fd, &st) < 0)
        fail("unexpected transfer descriptor");
    transfer_fd = fd;
    sent = 0;
    transfer_payload = payload;
    transfer_length = payload_length;
    if (distinct_formats && !strcmp(mime, native_mime)) {
        transfer_payload = native_payload;
        transfer_length = native_length;
    }
    if (!transfer_payload)
        fail("unoffered representation requested");
    printf("request %s %llu\n", mime, (unsigned long long)st.st_ino);
    fflush(stdout);
}
static void source_cancelled(void *data, struct wl_proxy *object) {
    printf("cancelled\n");
    fflush(stdout);
}
static const struct { void (*send)(void *, struct wl_proxy *, const char *, int32_t);
    void (*cancelled)(void *, struct wl_proxy *); } source_listener = {
        source_send, source_cancelled,
};
static void offered_mime(void *data, struct wl_proxy *object, const char *mime) {
    if (object != latest_offer)
        fail("unexpected offer ordering");
    if (!strcmp(mime, "text/plain;charset=utf-8")) latest_formats |= 1;
    else if (!strcmp(mime, "text/plain")) latest_formats |= 2;
    else if (!strcmp(mime, "UTF8_STRING")) latest_formats |= 4;
    else if (!strcmp(mime, native_mime)) latest_formats |= 8;
}
static const struct { void (*offer)(void *, struct wl_proxy *, const char *); }
    offer_listener = {offered_mime};
static void device_offer(void *data, struct wl_proxy *object, struct wl_proxy *offer) {
    latest_offer = offer;
    latest_formats = 0;
    wl_proxy_add_listener(offer, (void (**)(void))&offer_listener, NULL);
}
static void device_selection(void *data, struct wl_proxy *object, struct wl_proxy *offer) {
    if (current_offer)
        wl_proxy_marshal_flags(current_offer, 1, NULL, 1, WL_MARSHAL_FLAG_DESTROY);
    current_offer = offer;
    current_formats = offer && offer == latest_offer ? latest_formats : 0;
}
static void device_finished(void *data, struct wl_proxy *object) {
    fail("data device finished");
}
static const struct {
    void (*offer)(void *, struct wl_proxy *, struct wl_proxy *);
    void (*selection)(void *, struct wl_proxy *, struct wl_proxy *);
    void (*finished)(void *, struct wl_proxy *);
} device_listener = {device_offer, device_selection, device_finished};
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    if (!strcmp(interface, "wl_seat"))
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (!strcmp(interface, dc_manager.name))
        manager = wl_registry_bind(registry, name, &dc_manager, 1);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {global, global_remove};

static void send_bytes(size_t count, int finish) {
    if (transfer_fd < 0 || count > transfer_length - sent)
        fail("invalid write action");
    int error = 0;
    while (count) {
        ssize_t n = write(transfer_fd, transfer_payload + sent, count);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0) {
            error = n < 0 ? errno : EIO;
            break;
        }
        count -= (size_t)n;
        sent += (size_t)n;
    }
    if (finish || error) {
        close(transfer_fd);
        transfer_fd = -1;
        printf("closed %d\n", error);
    } else {
        printf("part %zu\n", sent);
    }
    fflush(stdout);
}

static void receive_start(void) {
    int pipe_fds[2];
    struct stat st;
    if (!current_offer || transfer_fd >= 0 || pipe(pipe_fds) < 0)
        fail("cannot begin receive");
    transfer_fd = pipe_fds[0];
    if (fstat(transfer_fd, &st) < 0)
        fail("cannot identify receive pipe");
    wl_proxy_marshal_flags(current_offer, 0, NULL, 1, 0, receive_mime, pipe_fds[1]);
    close(pipe_fds[1]);
    if (wl_display_flush(display) < 0)
        fail("cannot flush receive request");
    printf("receiving %llu\n", (unsigned long long)st.st_ino);
    fflush(stdout);
}

static void receive_drain(void) {
    if (transfer_fd < 0)
        fail("missing receive pipe");
    FILE *output = fopen(receive_path, "wb");
    if (!output)
        fail("cannot open receive output");
    size_t total = 0;
    for (;;) {
        struct pollfd p = {transfer_fd, POLLIN, 0};
        int result = poll(&p, 1, 10000);
        if (result < 0 && errno == EINTR)
            continue;
        if (result <= 0)
            fail("receive stalled");
        unsigned char buffer[65536];
        ssize_t n = read(transfer_fd, buffer, sizeof buffer);
        if (n < 0 && errno == EINTR)
            continue;
        if (n < 0)
            fail("receive failed");
        if (!n)
            break;
        total += (size_t)n;
        if (total > (!strcmp(receive_mime, native_mime) ? 67117088u : 67108864u) || fwrite(buffer, 1, (size_t)n, output) != (size_t)n)
            fail("receive output exceeded limit or failed");
    }
    close(transfer_fd);
    transfer_fd = -1;
    if (fclose(output))
        fail("cannot finish receive output");
    printf("received %zu\n", total);
    fflush(stdout);
}

static unsigned char *load_payload(const char *path, size_t *length, size_t limit) {
    if (!strcmp(path, "-")) return NULL;
    FILE *file = fopen(path, "rb");
    struct stat st;
    if (!file || fstat(fileno(file), &st) < 0 || st.st_size < 0 || (uint64_t)st.st_size > limit)
        fail("cannot load payload");
    *length = (size_t)st.st_size;
    unsigned char *bytes = malloc(*length + 1);
    if (!bytes || fread(bytes, 1, *length, file) != *length)
        fail("cannot read payload");
    fclose(file);
    return bytes;
}

int main(int argc, char **argv) {
    if (argc < 3)
        fail("usage: wayland-clipboard FILE MIME... | --receive OUTPUT MIME");
    signal(SIGPIPE, SIG_IGN);
    receiving = !strcmp(argv[1], "--receive");
    distinct_formats = !strcmp(argv[1], "--formats");
    if (receiving) {
        if (argc != 4)
            fail("receive requires output and MIME");
        receive_path = argv[2];
        receive_mime = argv[3];
    } else if (distinct_formats) {
        if (argc != 4) fail("formats requires native and plain file paths");
        native_payload = load_payload(argv[2], &native_length, 67117089);
        payload = load_payload(argv[3], &payload_length, 67108865);
        if (!native_payload && !payload) fail("no formats");
    } else {
        payload = load_payload(argv[1], &payload_length, 67117089);
        if (!payload) fail("missing payload");
    }
    display = wl_display_connect(NULL);
    if (!display)
        fail("cannot connect");
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !seat || !manager)
        fail("missing seat or data-control manager");
    if (!receiving) {
        source = wl_proxy_marshal_flags(manager, 0, &dc_source, 1, 0, NULL);
        wl_proxy_add_listener(source, (void (**)(void))&source_listener, NULL);
        if (distinct_formats) {
            if (native_payload) wl_proxy_marshal_flags(source, 0, NULL, 1, 0, native_mime);
            if (payload) {
                wl_proxy_marshal_flags(source, 0, NULL, 1, 0, "text/plain;charset=utf-8");
                wl_proxy_marshal_flags(source, 0, NULL, 1, 0, "text/plain");
                wl_proxy_marshal_flags(source, 0, NULL, 1, 0, "UTF8_STRING");
            }
        } else {
            for (int index = 2; index < argc; ++index)
                wl_proxy_marshal_flags(source, 0, NULL, 1, 0, argv[index]);
        }
    }
    struct wl_proxy *device = wl_proxy_marshal_flags(manager, 1, &dc_device, 1, 0, NULL, seat);
    wl_proxy_add_listener(device, (void (**)(void))&device_listener, NULL);
    if (!receiving)
        wl_proxy_marshal_flags(device, 0, NULL, 1, 0, source);
    if (wl_display_roundtrip(display) < 0)
        fail("selection setup failed");
    puts("ready");
    fflush(stdout);
    for (;;) {
        if (wl_display_dispatch_pending(display) < 0 || wl_display_flush(display) < 0)
            fail("display dispatch failed");
        struct pollfd fds[] = {{STDIN_FILENO, POLLIN, 0},
                              {wl_display_get_fd(display), POLLIN, 0}};
        int result = poll(fds, 2, -1);
        if (result < 0 && errno == EINTR)
            continue;
        if (result < 0)
            fail("poll failed");
        if (fds[1].revents & (POLLIN | POLLHUP | POLLERR)) {
            if (wl_display_dispatch(display) < 0)
                fail("display disconnected");
        }
        if (fds[0].revents & POLLIN) {
            char command[80];
            if (!fgets(command, sizeof command, stdin))
                break;
            if (!strcmp(command, "formats\n")) {
                if (wl_display_roundtrip(display) < 0) fail("formats dispatch failed");
                printf("formats %u\n", current_formats);
                fflush(stdout);
            } else if (receiving && !strcmp(command, "receive\n"))
                receive_start();
            else if (receiving && !strcmp(command, "drain\n"))
                receive_drain();
            else if (receiving && !strcmp(command, "probe\n")) {
                if (transfer_fd < 0)
                    fail("missing probe pipe");
                struct pollfd p = {transfer_fd, POLLIN, 0};
                if (poll(&p, 1, 0) < 0)
                    fail("probe failed");
                printf("hup %d\n", !!(p.revents & POLLHUP));
                fflush(stdout);
            } else if (!receiving && !strcmp(command, "finish\n"))
                send_bytes(transfer_length - sent, 1);
            else if (!receiving && !strncmp(command, "set ", 4)) {
                if (distinct_formats) fail("cannot replace distinct format payloads");
                if (sent && transfer_fd >= 0)
                    fail("cannot replace a partial transfer");
                size_t length = strcspn(command + 4, "\n");
                unsigned char *replacement = malloc(length + 1);
                if (!replacement)
                    fail("cannot replace test payload");
                memcpy(replacement, command + 4, length);
                free(payload);
                payload = replacement;
                payload_length = length;
                if (transfer_fd >= 0) { transfer_payload = payload; transfer_length = length; }
                sent = 0;
                puts("updated");
                fflush(stdout);
            }
            else if (!receiving && !strncmp(command, "part ", 5))
                send_bytes((size_t)strtoull(command + 5, NULL, 10), 0);
            else if (!strcmp(command, "quit\n"))
                break;
            else
                fail("unknown command");
        } else if (fds[0].revents & (POLLHUP | POLLERR)) {
            break;
        }
    }
    if (transfer_fd >= 0)
        close(transfer_fd);
    wl_display_disconnect(display);
    free(payload);
    free(native_payload);
    return 0;
}
