/* wasmtest-c: a rhun extension in C (rhunext.h), compiled with clang --target=wasm32-wasip1 and a
 * WASI sysroot (tests/wasm-host.py runs it in rhun --wasm-host). Each command answers with a toast
 * that the test reads. */
#define RHUNEXT_IMPLEMENTATION
#include "rhunext.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#ifndef __wasi__
#include <sys/random.h>             /* getentropy (wasi-libc has it in unistd.h) */
#endif

static void toastf(rx_ext *ext, const char *fmt, const char *a, long b, long c) {
    char buf[300];
    snprintf(buf, sizeof buf, fmt, a, b, c);
    rx_toast(ext, buf);
}

/* the position just past the text: its last line and one past that line's last byte */
static rx_range whole(const unsigned char *t, size_t n) {
    rx_range r = {{1, 1}, {1, 1}};
    int line = 1, col = 1;
    for (size_t i = 0; i < n; i++) {
        if (t[i] == '\n') { line++; col = 1; } else col++;
    }
    r.end.line = line;
    r.end.col = col;
    return r;
}

static int readable(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    fclose(f);
    return 1;
}

static void on_command(rx_ext *ext, const char *name, rx_doc doc, void *user) {
    (void)user;
    char path[1024], path2[1024];
    const char *state = getenv("RHUN_STATE");
    if (!state) state = "";
    if (strcmp(name, "hello") == 0) {
        rx_toast(ext, "hello from wasm");
    } else if (strcmp(name, "upper") == 0) {
        size_t n;
        int64_t version;
        unsigned char *t = rx_text(ext, doc, &n, &version);
        if (!t) return;
        rx_range r = whole(t, n);
        for (size_t i = 0; i < n; i++) t[i] = (unsigned char)toupper(t[i]);
        if (rx_replace(ext, doc, version, r, (const char *)t, n) < 0) rx_toast(ext, "upper failed");
        else rx_toast(ext, "upper ok");
        free(t);
    } else if (strcmp(name, "env") == 0) {
        const char *e = getenv("RHUN_EXTENSION");
        toastf(ext, "env %s args %ld", e ? e : "", 1, 0);
    } else if (strcmp(name, "files") == 0) {
        snprintf(path, sizeof path, "%s/probe.txt", state);
        FILE *f = fopen(path, "w");
        if (!f) { toastf(ext, "files failed open %s", strerror(errno), 0, 0); return; }
        fputs("written by wasm\n", f);
        fclose(f);
        char line[100] = "";
        f = fopen(path, "r");
        if (!f || !fgets(line, sizeof line, f)) { rx_toast(ext, "files failed read"); return; }
        fclose(f);
        line[strcspn(line, "\n")] = 0;
        snprintf(path2, sizeof path2, "%s/sub", state);
        mkdir(path2, 0755);
        snprintf(path2, sizeof path2, "%s/sub/deeper", state);
        mkdir(path2, 0755);
        snprintf(path2, sizeof path2, "%s/sub/moved.txt", state);
        if (rename(path, path2) != 0) { rx_toast(ext, "files failed rename"); return; }
        snprintf(path, sizeof path, "%s/sub", state);
        DIR *d = opendir(path);
        long count = 0;
        struct dirent *de;
        while (d && (de = readdir(d)))
            if (strcmp(de->d_name, ".") && strcmp(de->d_name, "..")) count++;
        if (d) closedir(d);
        struct stat st;
        if (stat(path2, &st) != 0) { rx_toast(ext, "files failed stat"); return; }
        toastf(ext, "files ok %s %ld %ld", line, count, (long)st.st_size);
    } else if (strcmp(name, "project") == 0) {
        const char *proj = getenv("RHUN_PROJECT");
        snprintf(path, sizeof path, "%s/a.txt", proj ? proj : "");
        int r = readable(path);
        snprintf(path, sizeof path, "%s/from-wasm.txt", proj ? proj : "");
        FILE *f = fopen(path, "w");
        int w = f != NULL;
        if (f) fclose(f);
        char buf[100];
        snprintf(buf, sizeof buf, "project read=%s write=%s", r ? "true" : "false", w ? "true" : "false");
        rx_toast(ext, buf);
    } else if (strcmp(name, "escape") == 0) {
        const char *secret = getenv("WASMTEST_SECRET");
        if (!secret) secret = "";
        int a = readable(secret);
        snprintf(path, sizeof path, "%s/../../../../../../../../%s", state, secret[0] == '/' ? secret + 1 : secret);
        int b = readable(path);
        char buf[100];
        snprintf(buf, sizeof buf, "escape absolute=%s climb=%s", a ? "true" : "false", b ? "true" : "false");
        rx_toast(ext, buf);
    } else if (strcmp(name, "time") == 0) {
        struct timespec t0, t1, now;
        clock_gettime(CLOCK_REALTIME, &now);
        clock_gettime(CLOCK_MONOTONIC, &t0);
        struct timespec d = {0, 20000000};
        nanosleep(&d, NULL);
        clock_gettime(CLOCK_MONOTONIC, &t1);
        long ms = (t1.tv_sec - t0.tv_sec) * 1000 + (t1.tv_nsec - t0.tv_nsec) / 1000000;
        unsigned char rnd[8];
        int rok = getentropy(rnd, sizeof rnd) == 0;
        char buf[100];
        snprintf(buf, sizeof buf, "time %s slept=%s random=%s", now.tv_sec > 1700000000 ? "true" : "false",
                 ms >= 20 ? "true" : "false", rok ? "true" : "false");
        rx_toast(ext, buf);
    } else if (strcmp(name, "spin") == 0) {
        rx_toast(ext, "spinning");
        volatile unsigned long long x = 0;
        for (;;) {
            x = x * 6364136223846793005ULL + 1;
            if (x == 42) break;
        }
    } else if (strcmp(name, "trap") == 0) {
        __builtin_trap();
    } else if (strcmp(name, "exit") == 0) {
        exit(3);
    }
}

int main(void) {
    rx_handlers h = {0};
    h.command = on_command;
    return rx_run("", &h, NULL);
}
