#define _GNU_SOURCE
#include <dlfcn.h>
#include <time.h>
#include <unistd.h>
int fsync(int fd) {
    static int (*real_fsync)(int);
    if (!real_fsync) real_fsync = dlsym(RTLD_NEXT, "fsync");
    struct timespec delay = {.tv_sec=0, .tv_nsec=5000000};
    nanosleep(&delay, 0);
    return real_fsync(fd);
}
