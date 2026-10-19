/* probe: one WASI call per run, for tests/wasm-wasi.py; prints the result. Built with
 * build.sh (clang --target=wasm32-wasip1); the module is kept beside the source so the tests run
 * where no WASI toolchain is.
 *   probe open PATH | create PATH | mkdir PATH | unlink PATH | stat PATH | lstat PATH
 *   probe append PATH | poll-ready | poll-clocks | poll-abs
 * Paths are relative to descriptor 3, the first preopened directory. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wasi/api.h>

static __wasi_timestamp_t now(__wasi_clockid_t id) {
    __wasi_timestamp_t t = 0;
    if (__wasi_clock_time_get(id, 1, &t)) return 0;
    return t;
}

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    const char *t = argv[1], *p = argc > 2 ? argv[2] : ".";
    __wasi_fd_t fd;
    __wasi_errno_t e;
    if (!strcmp(t, "open")) {
        e = __wasi_path_open(3, __WASI_LOOKUPFLAGS_SYMLINK_FOLLOW, p, 0, __WASI_RIGHTS_FD_READ, 0, 0, &fd);
        printf("%d\n", e);
    } else if (!strcmp(t, "create")) {
        e = __wasi_path_open(3, __WASI_LOOKUPFLAGS_SYMLINK_FOLLOW, p, __WASI_OFLAGS_CREAT,
                             __WASI_RIGHTS_FD_READ | __WASI_RIGHTS_FD_WRITE, 0, 0, &fd);
        printf("%d\n", e);
    } else if (!strcmp(t, "mkdir")) {
        printf("%d\n", __wasi_path_create_directory(3, p));
    } else if (!strcmp(t, "unlink")) {
        printf("%d\n", __wasi_path_unlink_file(3, p));
    } else if (!strcmp(t, "stat") || !strcmp(t, "lstat")) {
        __wasi_filestat_t st;
        e = __wasi_path_filestat_get(3, t[0] == 's' ? __WASI_LOOKUPFLAGS_SYMLINK_FOLLOW : 0, p, &st);
        printf("%d %d\n", e, e ? -1 : st.filetype);
    } else if (!strcmp(t, "append")) {
        /* open to write without append, switch append on, write X */
        e = __wasi_path_open(3, __WASI_LOOKUPFLAGS_SYMLINK_FOLLOW, p, 0, __WASI_RIGHTS_FD_WRITE, 0, 0, &fd);
        if (!e) e = __wasi_fd_fdstat_set_flags(fd, __WASI_FDFLAGS_APPEND);
        __wasi_ciovec_t iov = {(const uint8_t *)"X", 1};
        __wasi_size_t n = 0;
        if (!e) e = __wasi_fd_write(fd, &iov, 1, &n);
        printf("%d %lu\n", e, (unsigned long)n);
    } else if (!strcmp(t, "poll-ready")) {
        /* a read of an empty standard input and a write: the write is ready now */
        __wasi_subscription_t s[2];
        memset(s, 0, sizeof s);
        s[0].userdata = 10;
        s[0].u.tag = __WASI_EVENTTYPE_FD_READ;
        s[0].u.u.fd_read.file_descriptor = 0;
        s[1].userdata = 20;
        s[1].u.tag = __WASI_EVENTTYPE_FD_WRITE;
        s[1].u.u.fd_write.file_descriptor = 1;
        __wasi_event_t ev[2];
        __wasi_size_t n = 0;
        e = __wasi_poll_oneoff(s, ev, 2, &n);
        printf("%d %lu %llu\n", e, (unsigned long)n, n ? (unsigned long long)ev[0].userdata : 0ULL);
    } else if (!strcmp(t, "poll-clocks")) {
        /* 1 ms and 30 s: only the first is due, after about 1 ms */
        __wasi_subscription_t s[2];
        memset(s, 0, sizeof s);
        for (int i = 0; i < 2; i++) {
            s[i].userdata = i + 1;
            s[i].u.tag = __WASI_EVENTTYPE_CLOCK;
            s[i].u.u.clock.id = __WASI_CLOCKID_MONOTONIC;
            s[i].u.u.clock.timeout = i ? 30000000000ULL : 1000000ULL;
        }
        __wasi_timestamp_t t0 = now(__WASI_CLOCKID_MONOTONIC);
        __wasi_event_t ev[2];
        __wasi_size_t n = 0;
        e = __wasi_poll_oneoff(s, ev, 2, &n);
        __wasi_timestamp_t ms = (now(__WASI_CLOCKID_MONOTONIC) - t0) / 1000000;
        printf("%d %lu %llu %s\n", e, (unsigned long)n, (unsigned long long)ev[0].userdata, ms >= 1 && ms < 5000 ? "prompt" : "slow");
    } else if (!strcmp(t, "poll-abs")) {
        /* an absolute realtime deadline 20 ms ahead */
        __wasi_subscription_t s;
        memset(&s, 0, sizeof s);
        s.userdata = 7;
        s.u.tag = __WASI_EVENTTYPE_CLOCK;
        s.u.u.clock.id = __WASI_CLOCKID_REALTIME;
        s.u.u.clock.timeout = now(__WASI_CLOCKID_REALTIME) + 20000000ULL;
        s.u.u.clock.flags = __WASI_SUBCLOCKFLAGS_SUBSCRIPTION_CLOCK_ABSTIME;
        __wasi_timestamp_t t0 = now(__WASI_CLOCKID_MONOTONIC);
        __wasi_event_t ev;
        __wasi_size_t n = 0;
        e = __wasi_poll_oneoff(&s, &ev, 1, &n);
        __wasi_timestamp_t ms = (now(__WASI_CLOCKID_MONOTONIC) - t0) / 1000000;
        printf("%d %lu %llu %s\n", e, (unsigned long)n, (unsigned long long)ev.userdata, ms >= 15 && ms < 5000 ? "prompt" : "wrong");
    } else {
        return 2;
    }
    return 0;
}
