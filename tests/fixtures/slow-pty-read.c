/* platform: macOS-only -- tests/record_drain.sh loads this with DYLD_INSERT_LIBRARIES into
 *           `wezterm record`. Each read(2) of a pseudo-terminal master (a descriptor ptsname(3)
 *           names a slave for) first sleeps $WEZTERM_TEST_PTY_READ_DELAY_MS milliseconds, so
 *           record's reader thread always reads the child's output after the child has exited
 *           and its exit has been reported. The constructor removes both variables, so the
 *           recorded child runs without it. */
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static useconds_t delay_us;

__attribute__((constructor)) static void take_delay(void) {
    const char *ms = getenv("WEZTERM_TEST_PTY_READ_DELAY_MS");
    if (ms != NULL) delay_us = (useconds_t)strtoul(ms, NULL, 10) * 1000;
    unsetenv("WEZTERM_TEST_PTY_READ_DELAY_MS");
    unsetenv("DYLD_INSERT_LIBRARIES");
}

static ssize_t slow_read(int fd, void *buf, size_t len) {
    if (delay_us != 0 && ptsname(fd) != NULL) usleep(delay_us);
    return read(fd, buf, len);
}

__attribute__((used)) static const struct {
    const void *replacement;
    const void *replacee;
} interpose_read __attribute__((section("__DATA,__interpose"))) = {
    (const void *)slow_read, (const void *)read};
