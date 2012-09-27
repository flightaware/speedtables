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

void *ckalloc(size_t bytes)
{
    void *mem = malloc(bytes);
    if(!mem) panic("NO mem");
    fprintf(stderr, "ckalloc 0x%lX: %ld\n", mem, bytes);
    return mem;
}
void ckfree(void *p)
{
    fprintf(stderr, "ckfree 0x%lX\n", p);
    free(p);
}
void panic(const char *s) {
    fprintf(stderr, "PANIC: %s\n", s);
    abort();
}
