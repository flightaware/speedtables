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

static mapinfo *mapinfo_list;

// open_new - open a new large, empty, mappable file. Return open file
// descriptor or -1. Errno WILL be set on failure.
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

// map_file - map a file at addr. If the file doesn't exist, create it first
// with size default_size. Return mapped address or NULL on failure. Errno
// WILL be meaningful after a failure.
char *map_file(char *file, char *addr, size_t default_size)
{
    char    *map;
    int      flags = MAP_SHARED|MAP_NOSYNC;
    size_t   size;
    int      fd;
    mapinfo *mapinfo_buf;

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

// unmap_file - Unmap the open and mapped associated with the memory mapped
// at address "map", return 0 if there is no memory we know about mapped
// there. Errno is not meaningful after failure.
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

shminitmap(mapheader *map, size_t size)
{
    map->magic = MAP_MAGIC;
    map->size = size;
    map->pools->next = 0;
    map->pools->count = 0;
    map->write_lock = 0;
    map->cycle = 0;
    map->readers->next = 0;
    map->readers->count = 0;

    // Initialise the freelist by making the whole of the map after the
    // header one big free block...
    setfree(&map[1], size-sizeof *map, TRUE);
    // ... and storing the offset in the freelist
    map->free = sizeof *map;
}

shmaddpool(mapheader *map, size_t size, int nentries)
{
}

shmalloc(mapheader *map, size_t size)
{
}

shmfree(char *block)
{
}

// Attempt to put a pending freed block back in a pool
int shmdepool(mapheader *map, uint32_t start)
{
    pool_block *pool = &map->pools;
    uint32_t *block = (uint32_t *)off2ptr(map, start);

    while(pool->count || pool->next) {
      for(i = 0; i < pool->count; i++) {
	if(pool->start <= start && pool->end > start) {
	  if(pool->start % pool->size != 0) // partial free in pool, ignore
	    return 1;

	  // Thread block into free list. We do not store size in or coalesce
	  // pool blocks, they're always all the same size, so all we have in
	  // them is the offset of the next free block.
	  *block = pool->free;
	  pool->free = start;

	  pool->avail++;

	  return 1;
	}
      }
    }
    return 0;
}

// Marks a block as free or busy, by storing the size of the block at both
// ends... positive if free, negative if not.
setfree(uint32_t *block, size_t size, int is_free)
{
    *block = is_free ? size : -size;
    block = (uint32_t *) &((char *)block)[size]; // point to next block;
    block--; // step back one word;
    *block = is_free ? size : -size;
}

// attempt to free a block
// first, try to free it into a pool as an unstructured block
// then, thread it on the free list
// TODO: coalesce the free list

// free block structure:
//    int32 size;
//    int32 next;
//    int32 prev;
//    ...
//    int32 size;

// busy block structure:
//    int32 -size;
//    ...
//    int32 -size;

int shmdealloc(mapheader *map, uint32_t start)
{
    uint32_t *block;
    size_t size;

    if(shmdepool(map, start)) return 1;

    // step back over block size.
    start -= sizeof (uint32_t);

    block = (uint32_t *)off2ptr(start);

    // first word is the size of the block, negative if busy
    if(*block > 0)
	panic("freeing freed block");

    size = -*block;

    setfree(block, size, TRUE);

    // TODO add code to coalesce the free list here

    block[1] = map->free;
    block[2] = 0;
    free = start;

    return 1;
}
