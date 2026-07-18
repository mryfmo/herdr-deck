#pragma once

#include <stdio.h>
#include <stddef.h>
#include <sys/ioctl.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*mosh_state_callback)(const void *, const void *, size_t);

int mosh_main(
    FILE *,
    FILE *,
    struct winsize *,
    mosh_state_callback,
    const void *,
    const char *,
    const char *,
    const char *,
    const char *,
    const char *,
    size_t,
    const char *
);

#ifdef __cplusplus
}
#endif
