/*
 * $Id$
 */

#include <sys/types.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/ipc.h>

#include "shared.h"

char *ckalloc(size_t bytes)
{
    char *mem = malloc(bytes);
    if(!mem) panic("NO mem");
    fprintf(stderr, "ckalloc 0x%lX: %ld\n", mem, bytes);
    return mem;
}
ckfree(char *p)
{
    fprintf(stderr, "ckfree 0x%lX\n", p);
    free(p);
}
panic(char *s) {
    fprintf(stderr, "PANIC: %s\n");
    abort();
}
