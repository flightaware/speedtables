/*
 * $Id$
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include <ctype.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/ipc.h>
#ifdef WITH_TCL
#include <tcl.h>
#endif

#include "shared.h"

static shm_t   *share_list;

#ifdef SHM_DEBUG_TRACE
# ifdef SHM_DEBUG_TRACE_FILE
    static void init_debug(void)
    {
        time_t now;
        SHM_DEBUG_FP = fopen(SHM_DEBUG_TRACE_FILE, "a");
        if(!SHM_DEBUG_FP) {
	    perror(SHM_DEBUG_TRACE_FILE);
	    SHM_DEBUG_FP = stderr;
	    return;
        }
        now = time(NULL);
        fprintf(SHM_DEBUG_FP, "\n# TRACE BEGINS %s\n", ctime(&now));
    }
# else
#   define init_debug()
# endif
#endif

int shared_errno;
char *shared_errmsg[] = {
	"unknown",				// SH_ERROR_0
	"Creating new mapped file",		// SH_NEW_FILE
	"In private memory",			// SH_PRIVATE_MEMORY
	"When mapping file",			// SH_MAP_FILE
	"Opening existing mapped file",		// SH_OPEN_FILE
	"Map doesn't exist",			// SH_NO_MAP
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

IFDEBUG(init_debug();)
    if(fd == -1) {
	shared_errno = SH_NEW_FILE;
	return -1;
    }

    if(nulbufsize > size)
	nulbufsize = (size + 1023) & ~1023;
#ifdef WITH_TCL
    buffer = ckalloc(nulbufsize);
    bzero(buffer, nulbufsize);
#else
    buffer = calloc(nulbufsize/1024, 1024);
#endif

    while(size > 0) {
	if(nulbufsize > size) nulbufsize = size;

	nbytes = write(fd, buffer, nulbufsize);

	if(nbytes < 0) { close(fd); unlink(file); return -1; }

	size -= nbytes;
    }

#ifdef WITH_TCL
    ckfree(buffer);
#else
    free(buffer);
#endif

    return fd;
}

// map_file - map a file at addr. If the file doesn't exist, create it first
// with size default_size. Return map info structure or NULL on failure. Errno
// WILL be meaningful after a failure.
shm_t   *map_file(char *file, char *addr, size_t default_size)
{
    char    *map;
    int      flags = MAP_SHARED|MAP_NOSYNC;
    size_t   size;
    int      fd;
    shm_t   *p;

IFDEBUG(init_debug();)
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
	    if(read(fd, &tmp, sizeof (mapheader)) == sizeof (mapheader)) {
		if(shmcheckmap(&tmp))
			addr = tmp.addr;
	    }
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

#ifdef WITH_TCL
    p = (shm_t*)ckalloc(sizeof(*p));
#else
    p = (shm_t*)malloc(sizeof (*p));
    if(!p) {
	shared_errno = SH_PRIVATE_MEMORY;
	munmap(map, size);
	close(fd);
	return NULL;
    }
#endif

    // Completely initialise all fields!
    p->next = share_list;
    p->map = (mapheader *)map;
    p->size = size;
    p->fd = fd;
    p->name = NULL;
    p->creator = 0;
    p->pools = NULL;
    p->freelist = NULL;
    p->garbage = NULL;
    p->garbage_pool = NULL;
    p->horizon = LOST_HORIZON;
    p->self = NULL;

    share_list = p;

    return p;
}

// unmap_file - Unmap the open and mapped associated with the memory mapped
// at address "map", return 0 if there is no memory we know about mapped
// there. Errno is not meaningful after failure.
int unmap_file(shm_t   *info)
{
    char	*map;
    size_t	 size;
    int		 fd;

    // remove from list
    if(!share_list) {
	shared_errno = -SH_NO_MAP;
	return 0;
    } else if(share_list == info) {
	share_list = info->next;
    } else {
	shm_t   *p = share_list;

	while(p && p->next != info)
	    p = p->next;

	if(!p) {
	    shared_errno = -SH_NO_MAP;
	    return 0;
	}

	p->next = info->next;
    }

    map = (char *)info->map;
    size = info->size;
    fd = info->fd;
#ifdef WITH_TCL
    ckfree((char *)info);
#else
    free(info);
#endif

    munmap(map, size);
    close(fd);

    return 1;
}

// unmap_all - Unmap all mapped files.
void unmap_all(void)
{
    while(share_list) {
	shm_t   *p    = share_list;
	char    *map  = (char *)p->map;
	size_t   size = p->size;
	int	 fd   = p->fd;

	share_list = share_list->next;

#ifdef WITH_TCL
	ckfree((char *)p);
#else
	free(p);
#endif

	munmap(map, size);
	close(fd);
    }
}

int shmcheckmap(volatile mapheader *map)
{
IFDEBUG(init_debug();)
    if(map->magic != MAP_MAGIC) return 0;
    if(map->headersize != sizeof *map) return 0;
    return 1;
}

void shminitmap(shm_t   *shm)
{
    volatile mapheader	*map = shm->map;
    cell_t		*block;
    cell_t 		 freesize;

IFDEBUG(init_debug();)
    // COMPLETELY initialise map.
    map->magic = MAP_MAGIC;
    map->headersize = sizeof *map;
    map->mapsize = shm->size;
    map->addr = (char *)map;
    map->namelist = NULL;
    map->cycle = LOST_HORIZON;
    map->readers = NULL;

    // freshly mapped, so this stuff is void
    shm->garbage = NULL;
    shm->garbage_pool = NULL;
    shm->freelist = NULL;
    shm->pools = NULL;
    shm->horizon = LOST_HORIZON;

    // Remember that we own this.
    shm->creator = 1;

    // Initialise the freelist by making the whole of the map after the
    // header three blocks:
    block = (cell_t *)&map[1];

    //  One block just containing a 0, lower sentinel
    *block++ = 0;

    //  One "used" block, freesize bytes long
    freesize = shm->size - sizeof *map - 2 * sizeof *block;

    setfree((freeblock *)block, freesize, FALSE);

    //  One block containing a 0, upper sentinel.
    *((cell_t *)(((char *)block) + freesize)) = 0;

    // Finally, initialize the free list by freeing it.
    shmdealloc(shm, (char *)&block[1]);
}

pool_t *makepool(size_t blocksize, int blocks, shm_t *share)
{
    pool_t *pool;
#ifdef WITH_TCL
    pool = (pool_t *)ckalloc(sizeof *pool);
#else
    pool = (pool_t *)malloc(sizeof *pool);
    if(!pool) {
	shared_errno = SH_PRIVATE_MEMORY;
	return NULL;
    }
#endif

    // align size
    if(blocksize % CELLSIZE)
	blocksize += CELLSIZE - blocksize % CELLSIZE;

    pool->share = share;
    pool->start = NULL;
    pool->blocks = blocks;
    pool->blocksize = blocksize;
    pool->avail = 0;
    pool->brk = NULL;
    pool->freelist = NULL;
    pool->next = NULL;

    return pool;
}

// Find a pool that's got a free chunk of the required size
pool_t *findpool(pool_t **poolhead, size_t blocksize)
{
    pool_t *pool = *poolhead;
    pool_t *first = NULL;

    // align size
    if(blocksize % CELLSIZE)
	blocksize += CELLSIZE - blocksize % CELLSIZE;

    while(pool) {
	if(pool->blocksize == blocksize) {
	    if(pool->avail)
		return pool;
	    if(!first) first = pool;
	}
	pool = pool->next;
    }

    if(!first) return NULL;

    pool = makepool(blocksize, first->blocks, first->share);
    pool->next = *poolhead;
    *poolhead = pool;

    if(pool->share) {
        pool->start = _shmalloc(first->share, blocksize*first->blocks);
    } else {
#ifdef WITH_TCL
	pool->start = ckalloc(blocksize * first->blocks);
#else
	if(!(pool->start = malloc(blocksize * first->blocks)))
	    shared_errno = SH_PRIVATE_MEMORY;
#endif
    }
    if(!pool->start) return NULL;

    // initialise empty pool
    pool->avail = pool->blocks;
    pool->brk = pool->start;

    return pool;
}

int shmaddpool(shm_t *shm, size_t blocksize, int blocks)
{
    pool_t *pool = makepool(blocksize, blocks, shm);
    if(!pool) return 0;

    pool->next = shm->pools;
    shm->pools = pool;

    return 1;
}

pool_t *mallocpool(size_t blocksize, int blocks)
{
    return makepool(blocksize, blocks, NULL);
}

char *palloc(pool_t **poolhead, size_t wanted)
{
    pool_t *pool;
    char *block;

    // find (or allocate) a pool that's got a free block of the right size
    pool = findpool(poolhead, wanted);
    if(!pool)
	return NULL;

    if(pool->freelist) { // use a free block, if available
	block = pool->freelist;
	pool->freelist = *(char **)block;
    } else { // use the next unused block
	block = pool->brk;
	pool->brk += pool->blocksize;
    }

    pool->avail--;

    return block;
}

void remove_from_freelist(shm_t   *shm, volatile freeblock *block)
{
    volatile freeblock *next = block->next, *prev = block->prev;
IFDEBUG(fprintf(SHM_DEBUG_FP, "remove_from_freelist(shm, 0x%lX);\n", (long)block);)
IFDEBUG(fprintf(SHM_DEBUG_FP, "    prev = 0x%lX, next=0x%lX\n", (long)prev, (long)next);)
    if(!block->next)
	shmpanic("Freeing freed block (next == NULL)!");
    if(!block->prev)
	shmpanic("Freeing freed block (prev == NULL)!");

    // We don't need this any more.
    block->next = block->prev = NULL;

    if(next == block || prev == block) {
	if(next != prev)
	    shmpanic("Corrupt free list (half-closed list)!");
	if(block != shm->freelist)
	    shmpanic("Corrupt free list (closed list != freelist)!");
IFDEBUG(fprintf(SHM_DEBUG_FP, "    last free, empty freelist\n");)
	shm->freelist = NULL;
	return;
    }

    if(prev == NULL)
	shmpanic("Corrupt free list (prev == NULL)!");
    if(next == NULL)
	shmpanic("Corrupt free list (next == NULL)!");
    if(prev->next != block)
	shmpanic("Corrunpt free list (prev->next != block)!");
    if(next->prev != block)
	shmpanic("Corrunpt free list (next->prev != block)!");
	
IFDEBUG(fprintf(SHM_DEBUG_FP, "    set 0x%lX->next = 0x%lX\n", (long)prev, (long)next);)
    prev->next = next;
IFDEBUG(fprintf(SHM_DEBUG_FP, "    set 0x%lX->prev = 0x%lX\n", (long)next, (long)prev);)
    next->prev = prev;

    if(shm->freelist == block) {
IFDEBUG(fprintf(SHM_DEBUG_FP, "    set freelist = 0x%lX\n", (long)next);)
	shm->freelist = next;
    }
}

void insert_in_freelist(shm_t   *shm, volatile freeblock *block)
{
    volatile freeblock *next, *prev;
IFDEBUG(fprintf(SHM_DEBUG_FP, "insert_in_freelist(shm, 0x%lX);\n", (long)block);)

    if(!shm->freelist) {
IFDEBUG(fprintf(SHM_DEBUG_FP, "    empty freelist, set all to block\n");)
	shm->freelist = block->next = block->prev = block;
	return;
    }
    next = block->next = shm->freelist;
    prev = block->prev = shm->freelist->prev;
IFDEBUG(fprintf(SHM_DEBUG_FP, "    insert between 0x%lX and 0x%lX\n", (long)prev, (long)next);)
    next->prev = prev->next = block;
IFDEBUG(fprintf(SHM_DEBUG_FP, "    done\n");)
}

char *_shmalloc(shm_t   *shm, size_t nbytes)
{
    volatile freeblock *block = shm->freelist;
    size_t 		needed = nbytes + 2 * CELLSIZE;
IFDEBUG(fprintf(SHM_DEBUG_FP, "_shmalloc(shm_t  , %ld);\n", (long)nbytes);)

    // align size
    if(nbytes % CELLSIZE)
	nbytes += CELLSIZE - nbytes % CELLSIZE;

    while(block) {
	int space = block->size;

	if(space < 0)
	    shmpanic("trying to allocate non-free block");

	if(space >= needed) {
	    size_t left = space - needed;
	    size_t used = needed;

	    // See if the remaining chunk is big enough to be worth saving
	    if(left < sizeof (freeblock) + 2 * CELLSIZE) {
		used = space;
		left = 0;
	    }

IFDEBUG(fprintf(SHM_DEBUG_FP, "    removing block size %d\n", used);)
	    remove_from_freelist(shm, block);
	    setfree(block, used, FALSE);

	    // If there's space left
	    if(left) {
		freeblock *new_block = (freeblock *)(((char *)block) + needed);
		
		// make it a valid freelist entry
		setfree(new_block, left, TRUE);
		new_block->next = new_block->prev = NULL;

IFDEBUG(fprintf(SHM_DEBUG_FP, "    adding new block 0s%lX size %d\n", (long)new_block, left);)
		// add it into the free list
		insert_in_freelist(shm, new_block);
	    }

IFDEBUG(fprintf(SHM_DEBUG_FP, "      return block2data(0x%lX) ==> 0x%lX\n", (long)block, (long)block2data(block));)

	    return block2data(block);
	}

	block = block->next;
    }

    return NULL;
}

char *shmalloc(shm_t   *shm, size_t size)
{
    char *block;
IFDEBUG(fprintf(SHM_DEBUG_FP, "shmalloc(shm, 0x%lX);\n", (long)size);)

    // align size
    if(size % CELLSIZE)
	size += CELLSIZE - size % CELLSIZE;

    
    if(!(block = palloc(&shm->pools, size)))
	block = _shmalloc(shm, size);
    return block;
}

void shmfree(shm_t *shm, char *block)
{
    garbage *entry;

IFDEBUG(fprintf(SHM_DEBUG_FP, "shmfree(shm, 0x%lX);\n", (long)block);)

    if(block < (char *)shm->map || block >= ((char *)shm->map)+shm->map->mapsize)
	shmpanic("Trying to free pointer outside mapped memory!");

    if(!shm->garbage_pool) {
	shm->garbage_pool = makepool(sizeof *entry, GARBAGE_POOL_SIZE, NULL);
	if(!shm->garbage_pool)
	    shmpanic("Can't create garbage pool");
    }

    entry = (garbage *)palloc(&shm->garbage_pool, sizeof *entry);
    if(!entry)
	shmpanic("Can't allocate memory in garbage pool");

    entry->cycle = shm->map->cycle;
    entry->block = block;
    entry->next = shm->garbage;
    shm->garbage = entry;
}

// Attempt to put a pending freed block back in a pool
int shmdepool(pool_t *pool, char *block)
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
void setfree(volatile freeblock *block, size_t size, int is_free)
{
IFDEBUG(fprintf(SHM_DEBUG_FP, "setfree(0x%lX, %ld, %d);\n", (long)block, (long)size, is_free);)
    volatile cell_t *cell = (cell_t *)block;
    *cell = is_free ? size : -size;
    cell = (cell_t *) &((char *)cell)[size]; // point to next block;
    cell--; // step back one word;
    *cell = is_free ? size : -size;
}

// attempt to free a block
// first, try to free it into a pool as an unstructured block
// then, thread it on the free list

// free block structure:
//    int32 size;
//    pointer next
//    pointer free
//    char unused[size - 8 - sizeof(freeblock);
//    int32 size;

// busy block structure:
//    int32 -size;
//    char data[size-8];
//    int32 -size;

int shmdealloc(shm_t *shm, char *memory)
{
    size_t size;
    freeblock *block;
IFDEBUG(fprintf(SHM_DEBUG_FP, "shmdealloc(shm=0x%lX, memory=0x%lX);\n", (long)shm, (long)memory);)

    if(memory < (char *)shm->map || memory >= ((char *)shm->map)+shm->map->mapsize)
	shmpanic("Trying to dealloc pointer outside mapped memory!");

    // Try and free it back into a pool.
    if(shmdepool(shm->pools, memory)) return 1;

    // step back to block header
    block = data2block(memory);
IFDEBUG(fprintf(SHM_DEBUG_FP, "  block=0x%lX\n", (long)memory);)

    size = block->size;
IFDEBUG(fprintf(SHM_DEBUG_FP, "  size=%ld\n", (long)size);)

    // negative size means it's allocated, positive it's free
    if(((int)size) > 0)
	shmpanic("freeing freed block");

    size = -size;

    // merge previous freed blocks
    while(((int)prevsize(block)) > 0) {
	freeblock *prev = prevblock(block);
        size_t new_size = prev->size;

IFDEBUG(fprintf(SHM_DEBUG_FP, "    merge prev block 0x%lX size %d\n", (long)prev, new_size);)
	// remove it from the free list
	remove_from_freelist(shm, prev);

	// increase the size of the previous block to include this block
	new_size += size;
	setfree(prev, new_size, FALSE); // not in freelist so not really free

	// *become* the previous block
	block = prev;
	size = new_size;
    }

    // merge following free blocks
    while(((int)nextsize(block)) > 0) {
	freeblock *next = nextblock(block);
	size_t new_size = next->size;

IFDEBUG(fprintf(SHM_DEBUG_FP, "    merge next block 0x%lX\n", (long)next);)
	// remove next from the free list
	remove_from_freelist(shm, next);

	// increase the size of this block to include it
	size += new_size;
	setfree(block, size, FALSE); // not in freelist so not free
    }

    // Finally, create a new free block from all merged blocks
    setfree(block, size, TRUE);

    // contents of free block is a freelist entry, create it
    block->next = block->prev = NULL;

    insert_in_freelist(shm, block);
IFDEBUG(fprintf(SHM_DEBUG_FP, "  deallocated 0x%lX size %ld\n", (long)block, (long)size);)
    return 1;
}

int write_lock(shm_t   *shm)
{
    volatile mapheader *map = shm->map;

    while(++map->cycle == LOST_HORIZON)
	continue;

    return map->cycle;
}

void write_unlock(shm_t   *shm)
{
#ifdef LAZY_GC
    static garbage_strike = 0;
    if(++garbage_strike < LAZY_GC) return;
    garbage_strike = 0;
#endif
    cell_t new_horizon = oldest_reader_cycle(shm);

    if(new_horizon - shm->horizon > 0) {
	shm->horizon = new_horizon;
	garbage_collect(shm);
    }
}

volatile reader *pid2reader(volatile mapheader *map, int pid)
{
    volatile reader_block *b = map->readers;
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

int shmattachpid(shm_t   *info, int pid)
{
    volatile mapheader *map = info->map;
    volatile reader_block *b = map->readers;

    if(pid2reader(map, pid)) return 1;

    while(b) {
	int i;
	for(i = 0; i < b->count; i++) {
	    if(b->readers[i].pid == 0) {
		b->readers[i].pid = pid;
		return 1;
	    }
	}
	if(b->count < READERS_PER_BLOCK) {
	    b->readers[b->count++].pid = pid;
	    return 1;
	}
	b = b->next;
    }
    b = (reader_block *)shmalloc(info, sizeof *b);
    if(!b) {
	return 0;
    }
    b->count = 0;
    b->next = map->readers;
    map->readers = (reader_block *)b;
    b->readers[b->count++].pid = pid;
    return 1;
}

int read_lock(shm_t   *shm)
{
    volatile mapheader *map = shm->map;
    volatile reader *self = shm->self;

    if(!self)
	shm->self = self = pid2reader(map, getpid());
    if(!self)
	return 0;
    return self->cycle = map->cycle;
}

void read_unlock(shm_t   *shm)
{
    volatile reader *self = shm->self;

    if(!self)
	return;

    self->cycle = LOST_HORIZON;
}

void garbage_collect(shm_t   *shm)
{
    pool_t	*pool = shm->garbage_pool;
    garbage	*garbp = shm->garbage;
    garbage	*garbo = NULL;
    cell_t	 horizon = shm->horizon;

    if(horizon != LOST_HORIZON) {
	horizon -= TWILIGHT_ZONE;
	if(horizon == LOST_HORIZON)
	    horizon --;
    }

    while(garbp) {
	if(horizon == LOST_HORIZON || garbp->cycle == LOST_HORIZON || horizon - garbp->cycle > 0) {
	    garbage *next = garbp->next;
	    shmdealloc(shm, garbp->block);
	    shmdepool(pool, (char *)garbp);
	    garbp = next;

	    if(garbo)
		garbo->next = garbp;
	    else
		shm->garbage = garbp;
	} else {
	    garbo = garbp;
	    garbp = garbp->next;
	}
    }
}

cell_t oldest_reader_cycle(shm_t   *shm)
{
    volatile reader_block *r = shm->map->readers;
    cell_t cycle = LOST_HORIZON;
    unsigned oldest_age = 0;
    unsigned age;

    while(r) {
	int count = 0;
        int i;
        for(i = 0; count < r->count && i < READERS_PER_BLOCK; i++) {
	    if(r->readers[i].pid) {
		count++;
		if(cycle == LOST_HORIZON)
		    continue;
		age = shm->map->cycle - r->readers[i].cycle;
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

int add_symbol(shm_t   *shm, char *name, char *value, int type)
{
    int i;
    int namelen = strlen(name);
    volatile mapheader *map = shm->map;
    volatile symbol *s;
    int len = sizeof(symbol) + namelen + 1;
    if(type == SYM_TYPE_STRING)
	len += strlen(value) + 1;

    s = (symbol *)shmalloc(shm, len);

    if(!s) return 0;

    for(i = 0; i <= namelen; i++)
	s->name[i] = name[i];

    if(type == SYM_TYPE_STRING) {
	s->addr = &s->name[namelen+1];
	len = strlen(value);
	for(i = 0; i <= len; i++)
	    s->name[namelen+1+i] = value[i];
    } else {
	s->addr = value;
    }

    s->type = type;

    s->next = map->namelist;

    map->namelist = s;

    return 1;
}

// Change the value of a symbol. Note that old values of symbols are never
// freed, because we don't know what they're used for and we don't want to
// lock the garbage collector for long-term symbol use. It's up to the
// caller to determine if the value can be freed and to do it.
int set_symbol(shm_t *shm, char *name, char *value, int type)
{
    volatile mapheader *map = shm->map;
    volatile symbol *s = map->namelist;
    while(s) {
	if(strcmp(name, (char *)s->name) == 0) {
	    if(type != SYM_TYPE_ANY && type != s->type) {
		return 0;
	    }
	    if(type == SYM_TYPE_STRING) {
		char *copy = shmalloc(shm, strlen(value));
		if(!copy)
		    return 0;
		strcpy(copy, value);
		s->addr = copy;
	    } else {
	        s->addr = value;
	    }
	    return 1;
	}
	s = s->next;
    }
    return 0;
}

// Get a symbol back.
char *get_symbol(shm_t *shm, char *name, int wanted)
{
    volatile mapheader *map = shm->map;
    volatile symbol *s = map->namelist;
    while(s) {
	if(strcmp(name, (char *)s->name) == 0) {
	    if(wanted != SYM_TYPE_ANY && wanted != s->type) {
		return NULL;
	    }
	    return (char *)s->addr;
	}
	s = s->next;
    }
    return NULL;
}

void shmpanic(char *s)
{
    fprintf(stderr, "PANIC: %s\n", s);
    abort();
}

// parse a string of type "nnnnK" or "mmmmG" to bytes;

int parse_size(char *s, size_t *ptr)
{
    size_t size = 0;

    while(isdigit(*s)) {
	size = size * 10 + *s - '0';
	s++;
    }
    switch(toupper(*s)) {
	case 'G': size *= 1024;
	case 'M': size *= 1024;
	case 'K': size *= 1024;
	    s++;
    }
    if(*s)
	return 0;
    *ptr = size;
    return 1;
}

#ifdef WITH_TCL
int TclGetSizeFromObj(Tcl_Interp *interp, Tcl_Obj *obj, size_t *ptr)
{
    if(parse_size(Tcl_GetString(obj), ptr))
	return TCL_OK;

    Tcl_ResetResult(interp);
    Tcl_AppendResult(interp, "Bad size, must be an integer optionally followed by 'k', 'm', or 'g': ", Tcl_GetString(obj), NULL);
    return TCL_ERROR;
}

void TclShmError(Tcl_Interp *interp, char *name)
{
    if(shared_errno >= 0) {
        char CONST*msg = Tcl_PosixError(interp);
        Tcl_AppendResult(interp, name, ": ", msg, NULL);
    } else {
        Tcl_AppendResult(interp, name, NULL);
	shared_errno = -shared_errno;
    }
    if(shared_errno)
	Tcl_AppendResult(interp, ": ", shared_errmsg[shared_errno], NULL);
}

static int autoshare = 0;

static char *share_base = NULL;

void setShareBase(char *new_base)
{
	share_base = new_base;
}

int doCreateOrAttach(Tcl_Interp *interp, char *sharename, char *filename, size_t size, shm_t **sharePtr)
{
    shm_t     *share;
    int	       creator = 1;

    if(size == ATTACH_ONLY) {
	creator = 0;
	size = 0;
    }

    if(strcmp(sharename, "#auto") == 0) {
	static char namebuf[32];
	sprintf(namebuf, "share%d", ++autoshare);
	sharename = namebuf;
    }

    share = map_file(filename, share_base, size);
    if(!share) {
	TclShmError(interp, filename);
	return TCL_ERROR;
    }
    if(creator) {
	shminitmap(share);
    } else if(!shmcheckmap(share->map)) {
	Tcl_AppendResult(interp, "Not a valid share: ", filename, NULL);
	unmap_file(share);
        return TCL_ERROR;
    }

    if((char *)share == share_base)
	share_base = share_base + size;

    share->name = ckalloc(strlen(sharename)+1);
    strcpy(share->name, sharename);

    if(sharePtr)
	*sharePtr = share;
    else
        Tcl_AppendResult(interp, sharename, NULL);

    return TCL_OK;
}

int doDetach(Tcl_Interp *interp, shm_t *share)
{
    if(share->name) {
	ckfree(share->name);
	share->name = NULL;
    }

    if(!unmap_file(share)) {
	TclShmError(interp, share->name);
	return TCL_ERROR;
    }

    return TCL_OK;
}
#endif

#ifdef SHARED_TCL_EXTENSION
int shareCmd (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])
{
    int   	 cmdIndex;
    char	*sharename;
    shm_t	*share;

    static CONST char *commands[] = {"create", "attach", "detach", "names", "get", "set", (char *)NULL};
    enum commands {CMD_CREATE, CMD_ATTACH, CMD_DETACH, CMD_NAMES, CMD_GET, CMD_SET};

    static CONST struct {
	int need_share;
	int nargs;
	char *args;
    } template[] = {
	{0, 5, "filename size"},
	{0, 4, "filename"},
	{1, 3, ""},
	{1, 0, "names"},
	{1, -4, "name ?name?..."},
	{1, -5, "name value ?name value?..."},
    };

    if(objc < 3) {
	Tcl_WrongNumArgs (interp, 1, objv, "command sharename ?args...?");
        return TCL_ERROR;
    }
     
    if (Tcl_GetIndexFromObj (interp, objv[1], commands, "command", TCL_EXACT, &cmdIndex) != TCL_OK) {
	return TCL_ERROR;
    }

    if(
	(template[cmdIndex].nargs > 0 && objc != template[cmdIndex].nargs) ||
	(template[cmdIndex].nargs < 0 && objc < -template[cmdIndex].nargs)
    ) {
	Tcl_WrongNumArgs (interp, 3, objv, template[cmdIndex].args);
	return TCL_ERROR;
    }

    sharename = Tcl_GetString(objv[2]);

    share = share_list;
    while(share) {
	if(strcmp(share->name, sharename) == 0) {
	    break;
	}
	share = share->next;
    }

    if(template[cmdIndex].need_share) {
	if(!share) {
	    Tcl_AppendResult(interp, "No such share: ", sharename, NULL);
	    return TCL_ERROR;
	}
    }

    switch (cmdIndex) {
        case CMD_CREATE: {
	    char      *filename;
	    size_t     size;

	    if(share) {
	         Tcl_AppendResult(interp, "Share already exists: ", sharename, NULL);
	         return TCL_ERROR;
	    }

	    filename = Tcl_GetString(objv[3]);

	    if (TclGetSizeFromObj (interp, objv[4], &size) == TCL_ERROR) {
		Tcl_AppendResult(interp, " in ... create ", sharename, NULL);
		return TCL_ERROR;
	    }

	    return doCreateOrAttach(interp, sharename, filename, size, NULL);
	}
        case CMD_ATTACH: {
	    if(share) {
	         Tcl_AppendResult(interp, "Share already exists: ", sharename);
	         return TCL_ERROR;
	    }

	    return doCreateOrAttach(
		interp, sharename, Tcl_GetString(objv[3]), ATTACH_ONLY, NULL);
	}
        case CMD_DETACH: {
	    return doDetach(interp, share);
	}
	case CMD_NAMES: {
	    if (objc == 3) {
	        volatile symbol *sym = share->map->namelist;
	        while(sym) {
		    Tcl_AppendElement(interp, (char *)sym->name);
		    sym = sym->next;
	        }
	    } else {
		int i;
		for (i = 3; i < objc; i++) {
		    char *name = Tcl_GetString(objv[i]);
		    if(get_symbol(share, name, SYM_TYPE_ANY))
			Tcl_AppendElement(interp, name);
		}
	    }
	    return TCL_OK;
	}
	case CMD_GET: {
	    int   i;
	    for (i = 3; i < objc; i++) {
		char *name = Tcl_GetString(objv[i]);
		char *s = get_symbol(share, name, SYM_TYPE_STRING);
		if(!s) {
		    Tcl_ResetResult(interp);
		    Tcl_AppendResult(interp, "Unknown name ",name," in ",sharename, NULL);
		    return TCL_ERROR;
		}
		Tcl_AppendElement(interp, s);
	    }
	    return TCL_OK;
	}
	case CMD_SET: {
	    int   i;

	    if (!share->creator) {
		Tcl_AppendResult(interp, "Can not write to ",sharename,": Permission denied", NULL);
		return TCL_ERROR;
	    }
	    if (!(objc & 1)) {
		Tcl_AppendResult(interp, "Odd number of elements in name-value list.",NULL);
		return TCL_ERROR;
	    }

	    for (i = 3; i < objc; i+=2) {
		char *name = Tcl_GetString(objv[i]);
		if(get_symbol(share, name, SYM_TYPE_ANY))
		    set_symbol(share, name, Tcl_GetString(objv[i+1]), SYM_TYPE_STRING);
		else
		    add_symbol(share, name, Tcl_GetString(objv[i+1]), SYM_TYPE_STRING);
	    }
	    return TCL_OK;
	}
    }
    Tcl_AppendResult(interp, "Should not happen, internal error: no defined subcommand or missing break in switch", NULL);
    return TCL_ERROR;
}

int
Shared_Init(Tcl_Interp *interp)
{
    if (NULL == Tcl_InitStubs (interp, TCL_VERSION, 0))
        return TCL_ERROR;

    Tcl_CreateObjCommand(interp, "share", (Tcl_ObjCmdProc *) shareCmd, (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);

    return Tcl_PkgProvide(interp, "Shared", "1.0");
}
#endif
