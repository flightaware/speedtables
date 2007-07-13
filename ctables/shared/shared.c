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
// with size default_size. Return map info structure or NULL on failure. Errno
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
    mapinfo_buf->free = NULL;
    mapinfo_list = mapinfo_buf;

    return mapinfo_buf;
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

shminitmap(volatile mapinfo *mapinfo)
{
    mapheader *map = mapinfo->map;
    freelist  *free;
    uint32_t  *block;
    uint32_t  freesize;

    map->magic = MAP_MAGIC;
    map->headersize = sizeof *map;
    map->mapsize = size;
    map->addr = map;
    map->write_lock = 0;
    map->cycle = 0;
    map->readers->next = 0;
    map->readers->count = 0;

    mapinfo->unfree = NULL;

    free = mapinfo->free = ckalloc(sizeof *free);

    free->pools = NULL;

    // Initialise the freelist by making the whole of the map after the
    // header three blocks:
    block = &map[1];

    //  One block just containing a 0, lower sentinel
    *block++ = 0;

    //  One "used" block, freesize bytes long
    freesize = size - sizeof *map - 2 * sizeof *block;
    setfree(block, freesize, FALSE);

    //  One block containing a 0, upper sentinel.
    *(uint32_t *)((char *)block) + freesize) = 0;

    // Finally, initialize the free list by freeing it.
    shmdealloc(mapinfo, &block[1]);
}

pool *makepool(char *memory, size_t blocksize, int blocks)
{
    pool *pool = ckalloc(sizeof pool);
    pool->start = memory;
    pool->blocks = blocks;
    pool->blocksize = blocksize;
    pool->avail = blocks;
    pool->brk = pool->start;
    pool->freelist = NULL;
    pool->next = NULL;
    return pool;
}

int shmaddpool(mapinfo *map, size_t blocksize, int blocks)
{
    char *memory = _shmalloc(map, blocksize*blocks);
    pool *pool;

    if(!memory) return 0;

    pool = makepool(memory, blocksize, blocks);
    pool->next = map->free->pools;
    map->free->pools = pool;
    return 1;
}

char *palloc(pool)
{
    if(pool->avail <= 0)
	return NULL;

    if(pool->freelist) {
	block = pool->freelist;
	pool->freelist = pool->freelist->next;
	return block;
    } else {
	block = pool->brk;
	pool->brk += size;
    }
    pool->avail--;
    return block;
}

char *shmalloc(mapinfo *map, size_t size)
{
    char *block = NULL;
    pool *pool = map->free->pools;
    while(pool) {
	if(pool->blocksize == size)
	    if(block = palloc(pool))
		return block;
	pool = pool->next;
    }

    return _shmalloc(map, size);
}

#define free2block(free) (&((uint32_t *)free)[-1])
#define block2free(block) ((freeblock *)&(block)[1])

#define prevsize(block) ((block)[-1])
#define nextblock(block) ((uint32_t *)(((char *)block) + abs(*(block))))
#define nextsize(block) (*nextblock(block))
#define prevblock(block) ((uint32_t *)(((char *)block) - abs(prevsize(block))))

char *_shmalloc(mapinfo *map, size_t size)
{
    freeblock *free = map->free->list;
    size_t fullsize = size + 2 * sizeof uint32_t;

    while(free) {
	uint32_t *block = free2block(free);
	blocksize = *block;

	if(blocksize < 0)
	    panic("corrupt free list");

	if(blocksize > fullsize) {
	    int remnant = fullsize - blocksize;

	    remove_from_freelist(map, free);

	    // See if the remaining chunk is big enough to be worth using
	    if(remnant < sizeof freeblock + 2 * sizeof uint32_t) {
		fullsize = blocksize;
	    } else {
		uint32_t *next = nextblock(block);
		freelist *new = block2free(next);

		// add it into the free list
		setfree(nextblock, remnant, TRUE);
		insert_in_freelist(map, new);
	    }

	    setfree(block, fullsize, FALSE);
	    return &block[1];
	}

	free = free->next;
    }

    return NULL;
}

shmfree(mapinfo *map, char *block)
{
    unfreelist *entry = NULL;
    pool *pool = map->unfreepool;

    while(pool) {
	entry = palloc(pool);
	if(entry) break;
	pool = pool->next;
    }

    if(!entry) {
	pool = makepool(ckalloc(UN_POOL_SIZE * sizeof *entry), sizeof *entry, UN_POOL_SIZE);
	entry = palloc(pool);
    }

    entry->cycle = map->cycle;
    entry->block = block;
    entry->next = map->unfree;
    map->unfree = entry;
}

// Attempt to put a pending freed block back in a pool
int shmdepool(mapinfo *mapinfo, char *block)
{
    pool *pool = mapinfo->free->pools;

    while(pool) {
	size_t offset = block - pool->start;
	if(offset < 0 || offset > (pool->blocks * pool->blocksize)) {
	    pool = pool->next;
	    continue;
	}

	if(offset % pool->blocksize != 0) // partial free, ignore
	    return 1;

	// Thread block into free list. We do not store size in or coalesce
	// pool blocks, they're always all the same size, so all we have in
	// them is the address of the next free block.
	*((char **)block) = pool->freelist;
	pool->freelist = block;
	pool->avail++;

	return 1;
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
//    freeblock;
//    char unused[size - 8 - sizeof(freeblock);
//    int32 size;

// busy block structure:
//    int32 -size;
//    char data[size-8];
//    int32 -size;

int shmdealloc(mapinfo *mapinfo, uint32_t *block)
{
    size_t size;
    freeblock *free;

    // Try and free it back into a pool.
    if(shmdepool(mapinfo, start)) return 1;

    // step back to block header
    block--;

    size = *block;

    // negative size means it's allocated, positive it's free
    if(size > 0)
	panic("freeing freed block");

    size = -size;
    setfree(block, size, TRUE);

    // contents of free block is a freelist entry, create it
    free = (freeblock *)&block[1];
    free->next = free->prev = NULL;

    // merge previous freed blocks
    while(prevsize(block) > 0) {
	uint32_t *prev = prevblock(block);

	// increase the size of the previous block to include this block
	size += prevsize(block);
	setfree(prev, size, TRUE);

	// *become* the previous block
	block = prev;
	free = block2free(block);

	// remove it from the free list
	remove_from_freelist(mapinfo, free);
    }

    // merge following free blocks
    while(nextsize(block) > 0) {
	uint32_t *next = nextblock(block);
	// remove next from the free list
	remove_from_freelist(mapinfo, block2free(next));

	// increase the size of this block to include it
	size += nextsize(block);
	setfree(block, size, TRUE);
    }

    insert_in_freelist(mapinfo, free);
    return 1;
}
