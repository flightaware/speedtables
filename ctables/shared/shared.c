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

#ifndef max
#define max(a,b) (((a)>(b))?(a):(b))
#endif

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

#ifndef WITH_TCL
char *ckalloc(size_t size)
{
    char *p = malloc(size);
    if(!p)
	shmpanic("Out of memory!");
    return p;
}
# define ckfree(p) free(p)
#endif

int shared_errno;
char *shared_errmsg[] = {
	"unknown",				// SH_ERROR_0
	"Creating new mapped file",		// SH_NEW_FILE
	"In private memory",			// SH_PRIVATE_MEMORY
	"When mapping file",			// SH_MAP_FILE
	"Opening existing mapped file",		// SH_OPEN_FILE
	"Map or file doesn't exist",		// SH_NO_MAP
	"Existing map is inconsistent",		// SH_ALREADY_MAPPED
	"Map or file is too small",		// SH_TOO_SMALL
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

#define DEFAULT_FLAGS (MAP_SHARED|MAP_NOSYNC)
#define REQUIRED_FLAGS MAP_SHARED
#define FORBIDDEN_FLAGS (MAP_ANON|MAP_FIXED|MAP_PRIVATE|MAP_STACK)

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

    // Use calloc because it is more efficient than bzeroing in some
    // systems, and this is a BIG allocation
    buffer = calloc(nulbufsize/1024, 1024);
    if(!buffer) {
	close(fd);
	return -1;
    }

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
// with size default_size. Return share or NULL on failure. Errno
// WILL be meaningful after a failure.
//
// If the file has already been mapped, return the share associated with the
// file. The file check is purely by name, if multiple different names are
// used by the same process for the same file the result is undefined.
//
// If the file is already mapped, but at a different address, this is an error
//this is an error
//
shm_t   *map_file(char *file, char *addr, size_t default_size, int flags)
{
    char    *map;
    size_t   size;
    int      fd;
    shm_t   *p = share_list;

    if(!flags)
	flags = DEFAULT_FLAGS;
    else {
	flags |= REQUIRED_FLAGS;
	flags &= ~(FORBIDDEN_FLAGS);
    }

    // Look for an already mapped share
    while(p) {
	if(p->filename == file) {
	    if((addr != NULL && addr != (char *)p->map)) {
		shared_errno = -SH_ALREADY_MAPPED;
		return NULL;
	    }
	    if(default_size && default_size > p->size) {
		shared_errno = -SH_TOO_SMALL;
		return NULL;
	    }
	    return p;
	}
	p = p->next;
    }

IFDEBUG(init_debug();)
    fd = open(file, O_RDWR, 0);

    if(fd == -1) {
	if(!size || !addr) {
	    shared_errno = -SH_NO_MAP;
	    return 0;
	}

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

	if(addr == 0) {
	    mapheader tmp;
	    if(read(fd, &tmp, sizeof (mapheader)) == sizeof (mapheader)) {
		if(shmcheckmap(&tmp))
		    addr = tmp.addr;
	    }
	    lseek(fd, 0L, SEEK_SET);
	}

	if(default_size > (size_t) sb.st_size) {
	    close(fd);

	    fd = open_new(file, default_size);

	    if(fd == -1) {
		shared_errno = SH_TOO_SMALL;
	        return 0;
	    }

	    size = default_size;
	} else {
	    if(default_size)
	        size = default_size;
	    else
		size = (size_t) sb.st_size;
	}
    }

    if(addr) flags |= MAP_FIXED;
    map = mmap(addr, size, PROT_READ|PROT_WRITE, flags, fd, (off_t) 0);
IFDEBUG(fprintf(stderr, "mmap(0x%lX, %d, rw, %d, %d, 0) = 0x%lX;\n", (long)addr, size, flags, fd, (long)map);)

    if(map == MAP_FAILED) {
	shared_errno = SH_MAP_FILE;
	close(fd);
	return NULL;
    }

    p = (shm_t*)ckalloc(sizeof(*p));
    p->filename = ckalloc(strlen(file)+1);
    strcpy(p->filename, file);

    // Completely initialise all fields!
    p->next = share_list;
    p->map = (mapheader *)map;
    p->size = size;
    p->flags = flags;
    p->fd = fd;
    p->name = NULL;
    p->creator = 0;
    p->pools = NULL;
    p->freelist = NULL;
    p->garbage = NULL;
    p->garbage_pool = NULL;
    p->horizon = LOST_HORIZON;
    p->self = NULL;
    p->objects = NULL;

    share_list = p;

    return p;
}

// unmap_file - Unmap the open and mapped associated with the memory mapped
// for share. Return 0 on error. Errno is not meaningful after faillure,
// shared_errno is.
int unmap_file(shm_t   *share)
{
    char	*map;
    size_t	 size;
    int		 fd;

    // If there's anyone still using the share, it's a no-op
    if(share->objects)
	return 1;

    // remove from list
    if(!share_list) {
	shared_errno = -SH_NO_MAP;
	return 0;
    } else if(share_list == share) {
	share_list = share->next;
    } else {
	shm_t   *p = share_list;

	while(p && p->next != share)
	    p = p->next;

	if(!p) {
	    shared_errno = -SH_NO_MAP;
	    return 0;
	}

	p->next = share->next;
    }

    map = (char *)share->map;
    size = share->size;
    fd = share->fd;
    ckfree(share->filename);
    ckfree((char *)share);

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

	ckfree((char *)p);

	munmap(map, size);
	close(fd);
    }
}

// Verify that a map file has already been configured.
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

poolhead_t *makepool(size_t blocksize, int blocks, shm_t *share)
{
    poolhead_t *head = (poolhead_t *)ckalloc(sizeof *head);

    // align size
    if(blocksize % CELLSIZE)
	blocksize += CELLSIZE - blocksize % CELLSIZE;

    head->share = share;
    head->blocks = blocks;
    head->blocksize = blocksize;
    head->pool = NULL;
    head->next = NULL;

    return head;
}

// Find a pool that's got a free chunk of the required size
pool_t *findpool(poolhead_t *head)
{
    pool_t *pool = head->pool;
    int count = 0;

    while(pool) {
	if(pool->avail)
	    return pool;
	pool = pool->next;
	count++;
        if(count > 1000)
		shmpanic("too many loops in the pool!");
    }

    pool = (pool_t *)ckalloc(sizeof *pool);

    if(head->share) {
        pool->start = _shmalloc(head->share, head->blocksize*head->blocks);
    } else {
	pool->start = ckalloc(head->blocksize * head->blocks);
    }

    if(!pool->start) {
	ckfree((char *)pool);
    }

    pool->avail = head->blocks;
    pool->brk = pool->start;
    pool->next = head->pool;
    pool->freelist = NULL;

    head->pool = pool;

    return pool;
}

int shmaddpool(shm_t *shm, size_t blocksize, int blocks)
{
    poolhead_t *head = makepool(blocksize, blocks, shm);
    if(!head) return 0;

    head->next = shm->pools;
    shm->pools = head;

    return 1;
}

char *palloc(poolhead_t *head, size_t wanted)
{
    pool_t *pool;
    char *block;

    // align size
    if(wanted % CELLSIZE)
	wanted += CELLSIZE - wanted % CELLSIZE;

    // find a pool list that is the right size;
    while(head) {
	if(head->blocksize == wanted)
	    break;
	head = head->next;
    }
    if(!head)
	return NULL;

    // find (or allocate) a pool that's got a free block
    pool = findpool(head);
    if(!pool)
	return NULL;

    if(pool->freelist) { // use a free block, if available
	block = pool->freelist;
	pool->freelist = *(char **)block;
    } else { // use the next unused block
	block = pool->brk;
	pool->brk += head->blocksize;
    }

    pool->avail--;

    return block;
}

void remove_from_freelist(shm_t   *shm, volatile freeblock *block)
{
    volatile freeblock *next = block->next, *prev = block->prev;
//IFDEBUG(fprintf(SHM_DEBUG_FP, "remove_from_freelist(shm, 0x%lX);\n", (long)block);)
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    prev = 0x%lX, next=0x%lX\n", (long)prev, (long)next);)
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
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    last free, empty freelist\n");)
	shm->freelist = NULL;
	return;
    }

    if(prev == NULL)
	shmpanic("Corrupt free list (prev == NULL)!");
    if(next == NULL)
	shmpanic("Corrupt free list (next == NULL)!");
    if(prev->next != block)
	shmpanic("Corrupt free list (prev->next != block)!");
    if(next->prev != block)
	shmpanic("Corrupt free list (next->prev != block)!");
	
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    set 0x%lX->next = 0x%lX\n", (long)prev, (long)next);)
    prev->next = next;
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    set 0x%lX->prev = 0x%lX\n", (long)next, (long)prev);)
    next->prev = prev;

    if(shm->freelist == block) {
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    set freelist = 0x%lX\n", (long)next);)
	shm->freelist = next;
    }
}

void insert_in_freelist(shm_t   *shm, volatile freeblock *block)
{
    volatile freeblock *next, *prev;
//IFDEBUG(fprintf(SHM_DEBUG_FP, "insert_in_freelist(shm, 0x%lX);\n", (long)block);)

    if(!shm->freelist) {
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    empty freelist, set all to block\n");)
	shm->freelist = block->next = block->prev = block;
	return;
    }
    next = block->next = shm->freelist;
    prev = block->prev = shm->freelist->prev;
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    insert between 0x%lX and 0x%lX\n", (long)prev, (long)next);)
    next->prev = prev->next = block;
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    done\n");)
}

char *_shmalloc(shm_t   *shm, size_t nbytes)
{
    volatile freeblock *block = shm->freelist;
    size_t 		needed = nbytes + 2 * CELLSIZE;
IFDEBUG(fprintf(SHM_DEBUG_FP, "_shmalloc(shm_t  , %ld);\n", (long)nbytes);)

    // align size
    if(nbytes % CELLSIZE)
	nbytes += CELLSIZE - nbytes % CELLSIZE;

    // really a do-while loop, null check should never fail
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

//IFDEBUG(fprintf(SHM_DEBUG_FP, "    removing block size %d\n", used);)
	    remove_from_freelist(shm, block);
	    setfree(block, used, FALSE);

	    // If there's space left
	    if(left) {
		freeblock *new_block = (freeblock *)(((char *)block) + needed);
		
		// make it a valid freelist entry
		setfree(new_block, left, TRUE);
		new_block->next = new_block->prev = NULL;

//IFDEBUG(fprintf(SHM_DEBUG_FP, "    adding new block 0s%lX size %d\n", (long)new_block, left);)
		// add it into the free list
		insert_in_freelist(shm, new_block);
	    }

IFDEBUG(fprintf(SHM_DEBUG_FP, "      return block2data(0x%lX) ==> 0x%lX\n", (long)block, (long)block2data(block));)

	    return block2data(block);
	}

	if(block == block->next)
	    break;

	block = block->next;
    }

    return NULL;
}

char *shmalloc(shm_t   *shm, size_t size)
{
    char *block;
IFDEBUG(fprintf(SHM_DEBUG_FP, "shmalloc(shm, %ld);\n", (long)size);)

    // align size
    if(size % CELLSIZE)
	size += CELLSIZE - size % CELLSIZE;

    if(!(block = palloc(shm->pools, size)))
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

    entry = (garbage *)palloc(shm->garbage_pool, sizeof *entry);
    if(!entry)
	shmpanic("Can't allocate memory in garbage pool");

    entry->cycle = shm->map->cycle;
    entry->block = block;
    entry->next = shm->garbage;
    shm->garbage = entry;
}

// Attempt to put a pending freed block back in a pool
int shmdepool(poolhead_t *head, char *block)
{
    while(head) {
	pool_t *pool = head->pool;
        pool_t *prev = NULL;
        while(pool) {
	    size_t offset = block - pool->start;
	    if(offset < 0 || offset > (head->blocks * head->blocksize)) {
	        prev = pool;
	        pool = pool->next;
	        continue;
	    }

	    if(offset % head->blocksize != 0) // partial free, ignore
	        return 1;

	    // Thread block into free list. We do not store size in or coalesce
	    // pool blocks, they're always all the same size, so all we have in
	    // them is the address of the next free block.
	    *((char **)block) = pool->freelist;
	    pool->freelist = block;
	    pool->avail++;

	    // Move the pool with the free block to the beginning of the free
	    // pool list, if it's not already there. This means that free blocks
	    // will tend to be found quickly.
	    if(prev) {
	        prev->next = pool->next;
	        pool->next = head->pool;
	        head->pool = pool;
	    }

	    return 1;
        }
        head = head->next;
    }
    return 0;
}

// Marks a block as free or busy, by storing the size of the block at both
// ends... positive if free, negative if not.
void setfree(volatile freeblock *block, size_t size, int is_free)
{
//IFDEBUG(fprintf(SHM_DEBUG_FP, "setfree(0x%lX, %ld, %d);\n", (long)block, (long)size, is_free);)
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
//IFDEBUG(fprintf(SHM_DEBUG_FP, "  block=0x%lX\n", (long)memory);)

    size = block->size;
//IFDEBUG(fprintf(SHM_DEBUG_FP, "  size=%ld\n", (long)size);)

    // negative size means it's allocated, positive it's free
    if(((int)size) > 0)
	shmpanic("freeing freed block");

    size = -size;

    // merge previous freed blocks
    while(((int)prevsize(block)) > 0) {
	freeblock *prev = prevblock(block);
        size_t new_size = prev->size;

//IFDEBUG(fprintf(SHM_DEBUG_FP, "    merge prev block 0x%lX size %d\n", (long)prev, new_size);)
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

//IFDEBUG(fprintf(SHM_DEBUG_FP, "    merge next block 0x%lX\n", (long)next);)
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

#ifdef LAZY_GC
static int garbage_strike = 0;
#endif
void write_unlock(shm_t   *shm)
{
    cell_t new_horizon;
    int    age;
#ifdef LAZY_GC
    if(++garbage_strike < LAZY_GC) return;
    garbage_strike = 0;
#endif

    new_horizon = oldest_reader_cycle(shm);

    // If no active readers, then work back from current time
    if(new_horizon == LOST_HORIZON)
	new_horizon = shm->map->cycle;

    age = new_horizon - shm->horizon;

    if(age > TWILIGHT_ZONE) {
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

int shmattachpid(shm_t   *share, int pid)
{
    volatile mapheader *map = share->map;
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
    b = (reader_block *)shmalloc(share, sizeof *b);
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
    if(!self) {
	fprintf(stderr, "%d: Can't find reader slot!\n", getpid());
	return LOST_HORIZON;
    }
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
    garbage	*garbp = shm->garbage;
    garbage	*garbo = NULL;
    cell_t	 horizon = shm->horizon;
    int		 collected = 0;
    int		 skipped = 0;

    if(horizon != LOST_HORIZON) {
	horizon -= TWILIGHT_ZONE;
	if(horizon == LOST_HORIZON)
	    horizon --;
    }

    while(garbp) {
	int delta = horizon - garbp->cycle;
	if(horizon == LOST_HORIZON || garbp->cycle == LOST_HORIZON || delta > 0) {
	    garbage *next = garbp->next;
	    shmdealloc(shm, garbp->block);
	    shmdepool(shm->garbage_pool, (char *)garbp);
	    garbp = next;

	    if(garbo)
		garbo->next = garbp;
	    else
		shm->garbage = garbp;

	    collected++;
	} else {
	    garbo = garbp;
	    garbp = garbp->next;
	    skipped++;
	}
    }
//fprintf(stderr, "%d: garbage_collect: cycle %d, horizon %d, collected %d, skipped %d\n", getpid(), shm->map->cycle, shm->horizon, collected, skipped);
}

cell_t oldest_reader_cycle(shm_t   *shm)
{
    volatile reader_block *r = shm->map->readers;
    cell_t new_cycle = LOST_HORIZON;
    cell_t map_cycle = shm->map->cycle;
    cell_t rdr_cycle = LOST_HORIZON;
    int oldest_age = 0;
    int age;

    while(r) {
	int count = 0;
        int i;
        for(i = 0; count < r->count && i < READERS_PER_BLOCK; i++) {
	    if(r->readers[i].pid) {
		count++;

		rdr_cycle = r->readers[i].cycle;

		if(rdr_cycle == LOST_HORIZON)
		    continue;

		age = map_cycle - rdr_cycle;

		if(new_cycle == LOST_HORIZON || age >= oldest_age) {
		    oldest_age = age;
		    new_cycle = rdr_cycle;
		}
	    }
	}
	r = r->next;
    }
    return new_cycle;
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

// Attach to an object (represented by an arbitrary string) in the shared
// memory file
int use_name(shm_t *share, char *name)
{
    object_t *ob = share->objects;
    while(ob) {
	if(strcmp(ob->name, name) == 0) return 1;
	ob = ob->next;
    }
    ob = (object_t *)ckalloc(sizeof *ob + strlen(name) + 1);

    ob->next = share->objects;
    strcpy(ob->name, name);
    share->objects = ob;
    return 1;
}

// Detach from an object (represented by a string) in the shared memory file
void release_name(shm_t *share, char *name)
{
    object_t *ob = share->objects;
    object_t *prev = NULL;
    while(ob) {
	if(strcmp(ob->name, name) == 0) {
	    if(prev) prev->next = ob->next;
	    else share->objects = ob->next;
	    ckfree((char *)ob);
	    return;
	}
	prev = ob;
	ob = ob->next;
    }
}

// Fatal error
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

int parse_flags(char *s)
{
    char *word;
    int   flags = DEFAULT_FLAGS;

    while(*s) {
        while(isspace(*s)) s++;

	word = s;
	while(*s && !isspace(*s)) s++;
	if(*s) *s++ = 0;

	     if(strcmp(word, "nocore") == 0) flags |= MAP_NOCORE;
	else if(strcmp(word, "core") == 0) flags &= ~MAP_NOCORE;
	else if(strcmp(word, "nosync") == 0) flags |= MAP_NOSYNC;
	else if(strcmp(word, "sync") == 0) flags &= MAP_NOSYNC;
    }
    return flags;
}

char *flags2string(int flags)
{
    static char buffer[32]; // only has to hold "nocore nosync shared"

    if(flags & MAP_NOCORE)
	strcat(buffer, "nocore ");
    else
	strcat(buffer, "core ");

    if(flags & MAP_NOSYNC)
	strcat(buffer, "nosync ");
    else
	strcat(buffer, "sync ");

    strcat(buffer, "shared");

    return buffer;
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

int doCreateOrAttach(Tcl_Interp *interp, char *sharename, char *filename, size_t size, int flags, shm_t **sharePtr)
{
    shm_t     *share;
    int	       creator = 1;
    int	       new_share = 1;

    if(size == ATTACH_ONLY) {
	creator = 0;
	size = 0;
    }

    if(strcmp(sharename, "#auto") == 0) {
	static char namebuf[32];
	sprintf(namebuf, "share%d", ++autoshare);
	sharename = namebuf;
    }

    share = map_file(filename, share_base, size, flags);
    if(!share) {
	TclShmError(interp, filename);
	return TCL_ERROR;
    }
    if(share->name) { // pre-existing share
	creator = 0;
	new_share = 0;
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

    if(new_share) {
        share->name = ckalloc(strlen(sharename)+1);
        strcpy(share->name, sharename);
    }

    if(sharePtr)
	*sharePtr = share;
    else
        Tcl_AppendResult(interp, share->name, NULL);

    return TCL_OK;
}

int doDetach(Tcl_Interp *interp, shm_t *share)
{
    if(share->objects)
	return TCL_OK;

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

int shareCmd (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])
{
    int   	 cmdIndex  = -1;
    char	*sharename = NULL;
    shm_t	*share     = NULL;

    static CONST char *commands[] = {"create", "attach", "list", "detach", "names", "get", "set", "info", (char *)NULL};
    enum commands {CMD_CREATE, CMD_ATTACH, CMD_LIST, CMD_DETACH, CMD_NAMES, CMD_GET, CMD_SET, CMD_INFO};

    static CONST struct {
	int need_share;		// if a missing share is an error
	int nargs;		// >0 number args, <0 -minimum number
	char *args;		// String for Tcl_WrongNumArgs
    } template[] = {
	{0, -5, "filename size ?flags?"},
	{0,  4, "filename"},
	{0, -2, "?share?"},
	{1,  3, ""},
	{1, -3, "names"},
	{1, -4, "name ?name?..."},
	{1, -5, "name value ?name value?..."},
	{1,  3, ""}
    };

    if (Tcl_GetIndexFromObj (interp, objv[1], commands, "command", TCL_EXACT, &cmdIndex) != TCL_OK) {
	return TCL_ERROR;
    }

    if(
	(template[cmdIndex].nargs > 0 && objc != template[cmdIndex].nargs) ||
	(template[cmdIndex].nargs < 0 && objc < -template[cmdIndex].nargs)
    ) {
	int nargs = abs(template[cmdIndex].nargs);
	Tcl_WrongNumArgs (interp, max(nargs,3), objv, template[cmdIndex].args);
	return TCL_ERROR;
    }

    if(objc > 2) {
        sharename = Tcl_GetString(objv[2]);

        share = share_list;
        while(share) {
	    if(sharename[0]) {
		if (strcmp(share->name, sharename) == 0)
	            break;
	    } else {
		if(share == (shm_t *)cData)
		    break;
	    }
	    share = share->next;
        }
	if(share && !sharename[0])
	    sharename = share->name;
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
	    int	       flags = DEFAULT_FLAGS;

	    if(share) {
	         Tcl_AppendResult(interp, "Share already exists: ", sharename, NULL);
	         return TCL_ERROR;
	    }

	    filename = Tcl_GetString(objv[3]);

	    if (TclGetSizeFromObj (interp, objv[4], &size) == TCL_ERROR) {
		Tcl_AppendResult(interp, " in ... create ", sharename, NULL);
		return TCL_ERROR;
	    }

	    if(objc > 6) {
		Tcl_WrongNumArgs (interp, 3, objv, template[cmdIndex].args);
		return TCL_ERROR;
	    } else if(objc == 6) {
		flags = parse_flags(Tcl_GetString(objv[5]));
	    }

	    return doCreateOrAttach(interp, sharename, filename, size, flags, NULL);
	}

        case CMD_ATTACH: {
	    if(share) {
	         Tcl_AppendResult(interp, "Share already exists: ", sharename);
	         return TCL_ERROR;
	    }

	    return doCreateOrAttach(
		interp, sharename, Tcl_GetString(objv[3]), ATTACH_ONLY, 0, NULL);
	}

        case CMD_DETACH: {
	    return doDetach(interp, share);
	}

	// list shares, or list objects in share
	case CMD_LIST: {
	    if(share) {
		object_t *object = share->objects;
		while(object) {
		    Tcl_AppendElement(interp, object->name);
		    object = object->next;
		}
	    } else {
	        share = share_list;
	        while(share) {
		    Tcl_AppendElement(interp, share->name);
		    share = share->next;
	        }
	    }
	    return TCL_OK;
	}

	// Return miscellaneous info about the share as a name-value list
	case CMD_INFO: {
	    Tcl_Obj *list = Tcl_NewObj();

#define APPSTRING(i,l,s) Tcl_ListObjAppendElement(i,l,Tcl_NewStringObj(s,-1))
#define APPINT(i,l,n) Tcl_ListObjAppendElement(i,l,Tcl_NewIntObj(n))
#define APPBOOL(i,l,n) Tcl_ListObjAppendElement(i,l,Tcl_NewBooleanObj(n))

	    if( TCL_OK != APPSTRING(interp, list, "size")
	     ||	TCL_OK != APPINT(interp, list, share->size)
	     || TCL_OK != APPSTRING(interp, list, "flags")
	     || TCL_OK != APPSTRING(interp, list, flags2string(share->flags))
	     || TCL_OK != APPSTRING(interp, list, "name")
	     || TCL_OK != APPSTRING(interp, list, share->name)
	     || TCL_OK != APPSTRING(interp, list, "creator")
	     || TCL_OK != APPBOOL(interp, list, share->creator)
	     || TCL_OK != APPSTRING(interp, list, "filename")
	     || TCL_OK != APPSTRING(interp, list, share->filename)
	    ) {
		return TCL_ERROR;
	    }
	    Tcl_SetObjResult(interp, list);
	    return TCL_OK;
	}

	// Return a list of names
	case CMD_NAMES: {
	    if (objc == 3) { // No args, all names
	        volatile symbol *sym = share->map->namelist;
	        while(sym) {
		    Tcl_AppendElement(interp, (char *)sym->name);
		    sym = sym->next;
	        }
	    } else { // Otherwise, just the names defined here
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
#ifdef SHARED_TCL_EXTENSION
    if (NULL == Tcl_InitStubs (interp, TCL_VERSION, 0))
        return TCL_ERROR;
#endif

    Tcl_CreateObjCommand(interp, "share", (Tcl_ObjCmdProc *) shareCmd, (ClientData)NULL, (Tcl_CmdDeleteProc *)NULL);

#ifdef SHARED_TCL_EXTENSION
    return Tcl_PkgProvide(interp, "Shared", "1.0");
#else
    return TCL_OK;
#endif
}
#endif
