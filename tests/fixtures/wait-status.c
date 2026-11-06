/* platform: macOS-only -- tests/mux_daemonize.sh loads this with DYLD_INSERT_LIBRARIES into
 *           `wezterm-mux-server --daemonize`. It appends "PID STATUS" to $WEZTERM_TEST_WAIT_LOG for
 *           each child that process reaps with waitpid. Its first fork's child exits without being
 *           seen by anyone else: the parent reaps it and exits 0 whatever its status was. The
 *           constructor removes both variables, so the server that the daemon execs, and any
 *           process that server starts, records nothing. */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static char log_path[1024];

__attribute__((constructor)) static void take_log_path(void) {
    const char *path = getenv("WEZTERM_TEST_WAIT_LOG");
    if (path != NULL && strlen(path) < sizeof log_path) strcpy(log_path, path);
    unsetenv("WEZTERM_TEST_WAIT_LOG");
    unsetenv("DYLD_INSERT_LIBRARIES");
}

static pid_t recording_waitpid(pid_t pid, int *status, int options) {
    int st = 0;
    pid_t reaped = waitpid(pid, &st, options);
    if (status != NULL) *status = st;
    if (reaped > 0 && log_path[0] != '\0') {
        char line[64];
        int n = snprintf(line, sizeof line, "%d %d\n", (int)reaped, st);
        int fd = open(log_path, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            write(fd, line, (size_t)n);
            close(fd);
        }
    }
    return reaped;
}

__attribute__((used)) static const struct {
    const void *replacement;
    const void *replacee;
} interpose_waitpid __attribute__((section("__DATA,__interpose"))) = {
    (const void *)recording_waitpid, (const void *)waitpid};
