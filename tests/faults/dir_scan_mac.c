/* Linked only with the private native bridge copy. */
#include <dirent.h>
#include <errno.h>
#include <stdint.h>
#include <stddef.h>
extern uint64_t mode __asm__("dst_mode");
extern uint64_t reads __asm__("dst_native_reads");
struct dirent *dst_readdir(DIR *directory) {
    if (mode >= 40 && mode <= 45) {
        ++reads;
        if ((mode == 44 && reads == 4) || (mode == 45 && reads == 1)) {
            errno = EINTR;
            return NULL;
        }
        if (mode == 40 || (mode == 41 && reads == 4) ||
            (mode == 43 && reads == 1000)) {
            errno = EIO;
            return NULL;
        }
    }
    struct dirent *result = readdir(directory);
    if (mode == 42 && result) errno = EIO;
    return result;
}
