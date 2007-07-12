/*
 * $Id$
 */

#include <sys/types.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/ipc.h>

#define NULBUFSIZE (1024L * 1024L)

typedef struct _mapinfo {
    struct _mapinfo *next;
    char	    *map;
    size_t	     size;
    int		     fd;
} mapinfo;

static mapinfo *mapinfo_list;

int open_new(char *file, size_t size)
{
    char *buffer;
    size_t nulbufsize = NULBUFSIZE;
    size_t nbytes;
    int fd = open(file, O_RDWR|O_CREAT, 0666);
    if(fd == -1) return -1;
    if(nulbufsize > size)
	nulbufsize = (size + 1023) & ~1023;
    buffer = calloc(nulbufsize/1024, 1024);
    if(!buffer) { close(fd); unlink(file); return -1; }
    while(size > 0) {
	if(nulbufsize > size) nulbufsize = size;
	nbytes = write(fd, buffer, nulbufsize);
	if(nbytes < 0) { close(fd); unlink(file); return -1; }
	size -= nbytes;
    }
    free(buffer);
    return fd;
}

char *map_file(char *file, char *addr, size_t default_size)
{
    char    *map;
    int     flags = MAP_SHARED|MAP_NOSYNC;
    size_t     size;
    int     fd;
    mapinfo    *mapinfo_buf;

    fd = open(file, O_RDWR, 0);

    if(fd == -1) {
	fd = open_new(file, default_size);

	if(fd == -1)
	    return 0;

	size = default_size;
    } else {
	struct stat sb;

	if(fstat(fd, &sb) < 0)
	    return NULL;

	size = (size_t) sb.st_size;
    }

    if(addr) flags |= MAP_FIXED;
    map = mmap(addr, size, PROT_READ|PROT_WRITE, flags, fd, (off_t) 0);

    if(map == MAP_FAILED) {
	close(fd);
	return NULL;
    }

    mapinfo_buf = (mapinfo *)ckalloc(sizeof (mapinfo));
    mapinfo_buf->map = map;
    mapinfo_buf->size = size;
    mapinfo_buf->fd = fd;
    mapinfo_buf->next = mapinfo_list;
    mapinfo_list = mapinfo_bust;

    return map;
}

int unmap_file(char *map)
{
    mapinfo *p, *q;

    p = mapinfo_list;
    q = NULL;

    while(p) {
	if(p->map == map)
	    break;
	q = p;
	p = p->next;
    }

    if(!p) return 0;

    if(q) q->next = p->next;
    else mapinfo_list = p->next;

    munmap(p->map, p->size);
    close(p->fd);

    ckfree(p);

    return 1;
}

