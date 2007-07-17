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

int shared_errno;
char *shared_errmsg[] = {
	"unknown",				// ERROR_0
	"Creating new mapped file",		// NEW_FILE
	"In private memory",			// PRIVATE_MEMORY
	"When mapping file",			// MAP_FILE
	"Opening existing mapped file",		// OPEN_FILE
	NULL
};

void shared_perror(char *text) {
	static char bigbuf [1024];
	if(shared_errno < 0) {
		fprintf(stderr, "%s: %s\n", text, shared_errmsg[-shared_errno]);
	} else if(shared_errno > 0) {
		strcpy(bigbuf, text);
		strcat(bigbuf, ": ");
		strcat(bigbuf, shared_errmsg[shared_errno]);
		perror(bigbuf);
	} else {
		perror(text);
	}
}

// open_new - open a new large, empty, mappable file. Return open file
// descriptor or -1. Errno WILL be set on failure.
int open_new(char *file, size_t size)
{
    char 	*buffer;
    size_t	 nulbufsize = NULBUFSIZE;
    size_t	 nbytes;
    int		 fd = open(file, O_RDWR|O_CREAT, 0666);

    if(fd == -1) {
	shared_errno = SH_NEW_FILE;
	return -1;
    }

    if(nulbufsize > size)
	nulbufsize = (size + 1023) & ~1023;
    buffer = calloc(nulbufsize/1024, 1024);

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
mapinfo *map_file(char *file, char *addr, size_t default_size)
{
    char    *map;
    int      flags = MAP_SHARED|MAP_NOSYNC;
    size_t   size;
    int      fd;
    mapinfo *p;

    fd = open(file, O_RDWR, 0);

    if(fd == -1) {
	fd = open_new(file, default_size);

	if(fd == -1)
	    return 0;

	size = default_size;
    } else {
	struct stat sb;

	if(fstat(fd, &sb) < 0) {
	    shared_errno = SH_OPEN_FILE;
	    return NULL;
	}

	size = (size_t) sb.st_size;

	if(addr == 0) {
	    mapheader tmp;
	    if(read(fd, tmp, sizeof (mapheader)) == sizeof (mapheader))
		addr = tmp.addr;
	    lseek(fd, 0L, SEEK_SET);
	}

    }

    if(addr) flags |= MAP_FIXED;
    map = mmap(addr, size, PROT_READ|PROT_WRITE, flags, fd, (off_t) 0);

    if(map == MAP_FAILED) {
	shared_errno = SH_MAP_FILE;
	close(fd);
	return NULL;
    }

    p = (mapinfo *)ckalloc(sizeof (*p));
    p->map = (mapheader *)map;
    p->size = size;
    p->fd = fd;
    p->next = mapinfo_list;
    p->freelist = NULL;
    p->pools = NULL;
    mapinfo_list = p;

    return p;
}

// unmap_file - Unmap the open and mapped associated with the memory mapped
// at address "map", return 0 if there is no memory we know about mapped
// there. Errno is not meaningful after failure.
int unmap_file(mapinfo *info)
{
    mapinfo *p, *q;
    char *map;
    size_t size;

    p = mapinfo_list;
    q = NULL;

    while(p) {
	if(p == info)
	    break;
	q = p;
	p = p->next;
    }

    if(!p) return 0;

    if(q) q->next = p->next;
    else mapinfo_list = p->next;
    map = (char *)p->map;
    size = p->size;
    munmap((char *)map, size);
    close(p->fd);
    ckfree(p);


    return 1;
}

// unmap_all - Unmap all mapped files.
void unmap_all(void)
{
    while(mapinfo_list) {
	mapinfo *p    = mapinfo_list;
	char    *map  = (char *)p->map;
	size_t   size = p->size;
	int	 fd   = p->fd;

	mapinfo_list = mapinfo_list->next;

	ckfree(p);
	munmap((char *)map, size);
	close(fd);
    }
}

void shminitmap(mapinfo *mapinfo)
{
    volatile mapheader	*map = mapinfo->map;
    cell_t		*block;
    cell_t 		 freesize;

    map->magic = MAP_MAGIC;
    map->headersize = sizeof *map;
    map->mapsize = mapinfo->size;
    map->addr = (char *)map;
    map->cycle = LOST_HORIZON;
    map->readers.next = 0;
    map->readers.count = 0;

    mapinfo->garbage = NULL;
    mapinfo->freelist = NULL;
    mapinfo->pools = NULL;

    // Initialise the freelist by making the whole of the map after the
    // header three blocks:
    block = (cell_t *)&map[1];

    //  One block just containing a 0, lower sentinel
    *block++ = 0;

    //  One "used" block, freesize bytes long
    freesize = mapinfo->size - sizeof *map - 2 * sizeof *block;

    setfree(block, freesize, FALSE);

    //  One block containing a 0, upper sentinel.
    *((cell_t *)((char *)block) + freesize) = 0;

    // Finally, initialize the free list by freeing it.
    shmdealloc(mapinfo, (char *)&block[1]);
}

pool *initpool(char *memory, size_t blocksize, int blocks)
{
    pool *new = (pool *)ckalloc(sizeof *new);
    new->start = memory;
    new->blocks = blocks;
    new->blocksize = blocksize;
    new->avail = blocks;
    new->brk = new->start;
    new->freelist = NULL;
    new->next = NULL;
    return new;
}

int shmaddpool(mapinfo *mapinfo, size_t blocksize, int blocks)
{
    char *memory = _shmalloc(mapinfo, blocksize*blocks);
    pool *pool;

    if(!memory) return 0;

    pool = initpool(memory, blocksize, blocks);
    pool->next = mapinfo->pools;
    mapinfo->pools = pool;
    return 1;
}

pool *ckallocpool(size_t blocksize, int blocks)
{
    return initpool((char *)ckalloc(blocksize * blocks), blocksize, blocks);
}

char *palloc(pool *pool, size_t wanted)
{
    char *block;

    while(pool->avail <= 0 || pool->blocksize != wanted) {
	pool = pool->next;
	if(pool == NULL)
	    return NULL;
    }

    if(pool->freelist) {
	block = pool->freelist;
	pool->freelist = *(char **)block;
    } else {
	block = pool->brk;
	pool->brk += pool->blocksize;
    }
    pool->avail--;
    return block;
}

void remove_from_freelist(mapinfo *mapinfo, volatile freeblock *block)
{
    volatile freeblock *next = block->next, *prev = block->prev;
    if(next == block) {
	if(prev != block)
	    panic("Corrupt free list");
	mapinfo->freelist = NULL;
	return;
    }
    prev->next = block->next;
    next->prev = block->prev;
}

void insert_in_freelist(mapinfo *mapinfo, volatile freeblock *block)
{
    volatile freeblock *next, *prev;
    if(!mapinfo->freelist) {
	mapinfo->freelist = block->next = block->prev = block;
	return;
    }
    next = block->next = mapinfo->freelist->next;
    prev = block->prev = mapinfo->freelist->prev;
    next->prev = prev->next = block;
}

char *_shmalloc(mapinfo *mapinfo, size_t size)
{
    volatile freeblock *free = mapinfo->freelist;
    size_t 		fullsize = size + 2 * CELLSIZE;

    while(free) {
	cell_t *block = data2block(free);
	int blocksize = *block;

	if(blocksize < 0)
	    panic("corrupt free list");

	if(blocksize > fullsize) {
	    int remnant = fullsize - blocksize;

	    remove_from_freelist(mapinfo, free);

	    // See if the remaining chunk is big enough to be worth using
	    if(remnant < sizeof (freeblock) + 2 * CELLSIZE) {
		fullsize = blocksize;
	    } else {
		cell_t *next = nextblock(block);
		freeblock *new = (freeblock *)block2data(next);

		// add it into the free list
		setfree(next, remnant, TRUE);
		insert_in_freelist(mapinfo, new);
	    }

	    setfree(block, fullsize, FALSE);
	    return (char *)&block[1];
	}

	free = free->next;
    }

    return NULL;
}

char *shmalloc(mapinfo *mapinfo, size_t size)
{
    char *block;

    if(!(block = palloc(mapinfo->pools, size)))
	block = _shmalloc(mapinfo, size);
    return block;
}

void shmfree(mapinfo *mapinfo, char *block)
{
    pool *pool = mapinfo->garbage_pool;
    garbage *entry = (garbage *)palloc(pool, GARBAGE_POOL_SIZE);

    if(!entry) {
	pool = ckallocpool(sizeof (garbage), GARBAGE_POOL_SIZE);
	pool->next = mapinfo->garbage_pool;
	mapinfo->garbage_pool = pool;
	entry = (garbage *)palloc(pool, GARBAGE_POOL_SIZE);
    }

    entry->cycle = mapinfo->map->cycle;
    entry->block = block;
    entry->next = mapinfo->garbage;
    mapinfo->garbage = entry;
}

// Attempt to put a pending freed block back in a pool
int shmdepool(pool *pool, char *block)
{
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
void setfree(cell_t *block, size_t size, int is_free)
{
    *block = is_free ? size : -size;
    block = (cell_t *) &((char *)block)[size]; // point to next block;
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

int shmdealloc(mapinfo *mapinfo, char *memory)
{
    size_t size;
    freeblock *free;
    cell_t *block;

    // Try and free it back into a pool.
    if(shmdepool(mapinfo->pools, memory)) return 1;

    // step back to block header
    block = data2block(memory);

    size = *block;

    // negative size means it's allocated, positive it's free
    if(((int)size) > 0)
	panic("freeing freed block");

    size = -size;
    setfree(block, size, TRUE);

    // contents of free block is a freelist entry, create it
    free = (freeblock *)&block[1];
    free->next = free->prev = NULL;

    // merge previous freed blocks
    while(prevsize(block) > 0) {
	cell_t *prev = prevblock(block);

	// increase the size of the previous block to include this block
	size += prevsize(block);
	setfree(prev, size, TRUE);

	// *become* the previous block
	block = prev;
	free = (freeblock *)block2data(block);

	// remove it from the free list
	remove_from_freelist(mapinfo, free);
    }

    // merge following free blocks
    while(nextsize(block) > 0) {
	cell_t *next = nextblock(block);
	// remove next from the free list
	remove_from_freelist(mapinfo, (freeblock *)block2data(next));

	// increase the size of this block to include it
	size += nextsize(block);
	setfree(block, size, TRUE);
    }

    insert_in_freelist(mapinfo, free);
    return 1;
}

int write_lock(mapinfo *mapinfo)
{
    volatile mapheader *map = mapinfo->map;

    while(++map->cycle == LOST_HORIZON)
	continue;
}

void write_unlock(mapinfo *mapinfo)
{
    cell_t new_horizon = oldest_reader_cycle(mapinfo);

    if(new_horizon - mapinfo->horizon > 0) {
	mapinfo->horizon = new_horizon;
	garbage_collect(mapinfo);
    }
}

volatile reader *pid2reader(volatile mapheader *map, int pid)
{
    volatile reader_block *b = &map->readers;
    while(b) {
	if(b->count) {
	    int i;
	    for(i = 0; i < READERS_PER_BLOCK; i++)
		if(b->readers[i].pid == pid)
		    return &b->readers[i];
	}
	b = b->next;
    }
    return NULL;
}

int read_lock(mapinfo *mapinfo)
{
    volatile mapheader *map = mapinfo->map;
    volatile reader *self = mapinfo->self;

    if(!self)
	mapinfo->self = self = pid2reader(map, getpid());
    if(!self)
	return 0;
    return self->cycle = map->cycle;
}

void read_unlock(mapinfo *mapinfo)
{
    volatile mapheader *map = mapinfo->map;
    volatile reader *self = mapinfo->self;

    if(!self)
	return;

    self->cycle = LOST_HORIZON;
}

void garbage_collect(mapinfo *mapinfo)
{
    pool	*pool = mapinfo->garbage_pool;
    garbage	*garbp = mapinfo->garbage;
    garbage	*garbo = NULL;
    cell_t	 horizon = mapinfo->horizon;

    if(horizon != LOST_HORIZON) {
	horizon -= TWILIGHT_ZONE;
	if(horizon == LOST_HORIZON)
	    horizon --;
    }

    while(garbp) {
	if(horizon == LOST_HORIZON || garbp->cycle == LOST_HORIZON || horizon - garbp->cycle > 0) {
	    garbage *next = garbp->next;
	    shmdealloc(mapinfo, garbp->block);
	    shmdepool(mapinfo->garbage_pool, (char *)garbp);
	    garbp = next;

	    if(garbo)
		garbo->next = garbp;
	    else
		mapinfo->garbage = garbp;
	} else {
	    garbo = garbp;
	    garbp = garbp->next;
	}
    }
}

cell_t oldest_reader_cycle(mapinfo *mapinfo)
{
    volatile reader_block *r = &mapinfo->map->readers;
    int i;
    int l;
    cell_t cycle = LOST_HORIZON;
    unsigned oldest_age = 0;
    unsigned age;

    while(r) {
	int count = 0;
        for(i = 0; count < r->count && i < READERS_PER_BLOCK; i++) {
	    if(r->readers[i].pid) {
		count++;
		if(cycle == LOST_HORIZON)
		    continue;
		age = mapinfo->map->cycle - r->readers[i].cycle;
		if(age >= oldest_age) {
		    oldest_age = age;
		    cycle = r->readers[i].cycle;
		}
	    }
	}
	r = r->next;
    }
    return cycle;
}

// Add a symbol to the internal namelist. This will allow the master to
// pass things like the address of a ctable to the reader without having
// more addresses than necessary involved.
//
// Constraint - these entries are never deallocated (though they may be
// removed from the list) and the list is never updated with an incomplete
// entry, so no locking is necessary.

int add_symbol(mapinfo *mapinfo, char *name, char *value)
{
    int i;
    int namelen = strlen(name);
    volatile mapheader *map = mapinfo->map;
    volatile symbol *s =
		(symbol *)shmalloc(mapinfo, sizeof (symbol) + namelen + 1);

    if(!s) return 0;

    for(i = 0; i <= namelen; i++)
	s->name[i] = name[i];

    s->addr = value;
    s->next = map->namelist;

    map->namelist = s;
}

// Get a symbol back.
char *get_symbol(mapinfo *mapinfo, char *name)
{
    volatile mapheader *map = mapinfo->map;
    volatile symbol *s = map->namelist;
    while(s) {
	if(strcmp(name, (char *)s->name) == 0)
	    return (char *)s->addr;
	s = s->next;
    }
    return NULL;
}

