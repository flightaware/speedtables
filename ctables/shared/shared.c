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
#include <time.h>
#include <signal.h>
#ifdef WITH_TCL
#include <tcl.h>
#endif

#include "shared.h"

#ifndef max
#define max(a,b) (((a)>(b))?(a):(b))
#endif

static shm_t   *share_list;

#ifdef SHARED_LOG
FILE *logfp;
#endif

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
        "unknown",                              // SH_ERROR_0
        "Creating new mapped file",             // SH_NEW_FILE
        "In private memory",                    // SH_PRIVATE_MEMORY
        "When mapping file",                    // SH_MAP_FILE
        "Opening existing mapped file",         // SH_OPEN_FILE
        "Map or file doesn't exist",            // SH_NO_MAP
        "Existing map is inconsistent",         // SH_ALREADY_MAPPED
        "Map or file is too small",             // SH_TOO_SMALL
        "Out of shared memory",                 // SH_MAP_FULL
        "Can't map correct address",            // SH_ADDRESS_MISMATCH
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


#ifdef MAP_NOSYNC
# define DEFAULT_FLAGS (MAP_SHARED|MAP_NOSYNC)
# define WITH_FLAGS 1
#else
# define DEFAULT_FLAGS MAP_SHARED
# ifdef MAP_NOCORE
#  define WITH_FLAGS 1
# else
#  define WITH_FLAGS 0
# endif
#endif

#define REQUIRED_FLAGS MAP_SHARED
#ifdef MAP_STACK
#define FORBIDDEN_FLAGS (MAP_ANON|MAP_FIXED|MAP_PRIVATE|MAP_STACK)
#else
#define FORBIDDEN_FLAGS (MAP_ANON|MAP_FIXED|MAP_PRIVATE)
#endif

// open_new - open a new large, empty, mappable file. Return open file
// descriptor or -1. Errno WILL be set on failure.
int open_new(char *file, size_t size)
{
    char        *buffer;
    size_t       nulbufsize = NULBUFSIZE;
    ssize_t      nbytes;
    int          fd = open(file, O_RDWR|O_CREAT, 0666);

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
//
shm_t   *map_file(char *file, char *addr, size_t default_size, int flags, int create)
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
        if(file && p->filename && strcmp(p->filename, file) == 0) {
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
    // look for an already mapped file
    fd = open(file, O_RDWR, 0);

    if(fd == -1) {
        // No file, and not creator, can't recover
        if(!create) {
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

    if(addr == (char *)-1)
        addr = 0;
    if(addr) flags |= MAP_FIXED;
    map = mmap(addr, size, PROT_READ|PROT_WRITE, flags, fd, (off_t) 0);
IFDEBUG(fprintf(stderr, "mmap(0x%lX, %ld, rw, %d, %d, 0) = 0x%lX;\n", (long)addr, (long)size, flags, fd, (long)map);)

    if(map == MAP_FAILED) {
        shared_errno = SH_MAP_FILE;
        close(fd);
        return NULL;
    }

    if(addr != 0 && !create && map != addr) {
        munmap(map, size);
        shared_errno = SH_ADDRESS_MISMATCH;
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
// for share. Return 0 on error, -1 if the map is still busy, 1 if it's
// been umapped. Errno is not meaningful after faillure, shared_errno is.
int unmap_file(shm_t   *share)
{
    char                *map;
    size_t               size;
    int                  fd;
    volatile reader     *r;

    // If there's anyone still using the share, it's a no-op
    if(share->objects)
        return -1;

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

    // If we're a reader, zero out our reader entry for re-use
    r = pid2reader(share->map, getpid());
    if(r) {
        r->pid = 0;
        r->cycle = LOST_HORIZON;
    }

    freepools(share->pools, 0);
    freepools(share->garbage_pool, 0);

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
        int      fd   = p->fd;

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

// Initialize a map file for use.
void shminitmap(shm_t   *shm)
{
    volatile mapheader  *map = shm->map;
    cell_t              *block;
    cell_t               freesize;

#ifdef SHARED_LOG
    if(!logfp) {
        logfp = fopen(SHARED_LOG, "a");
        if(logfp) {
            long now = time(NULL);
            fprintf(logfp, "START LOGGING @ %s\n", ctime(&now));
        }
        fflush(logfp);
    }
#endif

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
    shm->free_space = 0;
    shm->pools = NULL;
    shm->horizon = LOST_HORIZON;

    // Remember that we own this.
    shm->creator = 1;

    // Initialise the freelist by making the whole of the map after the
    // header three blocks:
    block = (cell_t *)&map[1];

    //  One block just containing a special lower sentinel
    *block++ = SENTINAL_MAGIC;

    //  One "used" block, freesize bytes long with a sentinel on both ends.
    freesize = shm->size - sizeof(*map) - 2 * CELLSIZE;

    setfree((freeblock *)block, freesize, FALSE);

    //  One block containing a special upper sentinel.
    *((cell_t *)(((char *)block) + freesize)) = SENTINAL_MAGIC;

    //  Some functionality assertions.
    if (!is_prev_sentinal(block))
      shmpanic("is_prev_sentinal failed");
    if (!is_next_sentinal(block))
      shmpanic("is_next_sentinal failed");
    if (((freeblock*)block)->magic != BUSY_MAGIC)
      shmpanic("invalid magic");

    // Finally, initialize the free list by freeing it.
    shmdealloc_raw(shm, block2data(block));
}

poolhead_t *makepool(size_t blocksize, int nblocks, int maxchunks, shm_t *share)
{
    poolhead_t *head = (poolhead_t *)ckalloc(sizeof *head);

    // align size
    if(blocksize % CELLSIZE)
        blocksize += CELLSIZE - blocksize % CELLSIZE;

    memset((void*)head, 0, sizeof *head);
    head->magic = POOL_MAGIC;
    head->share = share;
    head->nblocks = nblocks;
    head->blocksize = blocksize;
    head->chunks = NULL;
    head->next = NULL;
    head->numchunks = 0;
    head->maxchunks = maxchunks;
    head->freelist = NULL;

    return head;
}

// allocate a new pool chunk to a pool
chunk_t *addchunk(poolhead_t *head)
{
    chunk_t *chunk;

    if (head->magic != POOL_MAGIC)
        shmpanic("Invalid pool magic!");

    if(head->maxchunks && head->numchunks >= head->maxchunks)
        return NULL;

    chunk = (chunk_t *)ckalloc(sizeof *chunk);
    memset((void*)chunk, 0, sizeof *chunk);
    chunk->magic = CHUNK_MAGIC;

    if(head->share) {
        chunk->start = _shmalloc(head->share, head->blocksize*head->nblocks);
    } else {
        chunk->start = ckalloc(head->blocksize * head->nblocks);
    }

    if(!chunk->start) {
        // If we can't allocate memory, set maxchunks to -1 to make
        // sure we don't try again.
        head->maxchunks = -1;
        ckfree((char *)chunk);
        return NULL;
    }

    chunk->avail = head->nblocks;
    chunk->brk = chunk->start;
    chunk->next = head->chunks;

    head->chunks = chunk;
    head->numchunks++;

    return chunk;
}

int shmaddpool(shm_t *shm, size_t blocksize, int nblocks, int maxchunks)
{
    poolhead_t *head;

    // align size
    if(blocksize % CELLSIZE)
        blocksize += CELLSIZE - blocksize % CELLSIZE;

    // avoid duplicates - must not have multiple pools the same size
    for(head = shm->pools; head; head=head->next) {
        if (head->magic != POOL_MAGIC)
            shmpanic("Invalid pool magic!");
        if(head->blocksize == blocksize)
            return 1;
    }

    head = makepool(blocksize, nblocks, maxchunks, shm);
    if(!head) return 0;

    head->next = shm->pools;
    shm->pools = head;

    return 1;
}

char *palloc(poolhead_t *head, size_t wanted)
{
    chunk_t *chunk;
    char *block;

    // align size
    if(wanted % CELLSIZE)
        wanted += CELLSIZE - wanted % CELLSIZE;

    // find a pool list that is the right size;
    while(head) {
        if (head->magic != POOL_MAGIC)
           shmpanic("Invalid pool magic!");

        if(head->blocksize == wanted)
            break;
        head = head->next;
    }

    // No pools for this size, return null
    if(!head)
        return NULL;

    // Use a free block if available
    if(head->freelist) { // use a free block if available
        block = (char *)head->freelist;
        head->freelist = head->freelist->next;
        return block;
    }

    // If there's no room in the pool, get a new chunk
    if(head->chunks && head->chunks->avail > 0)
        chunk = head->chunks;
    else if (!(chunk = addchunk(head)))
        return NULL;

    // Pull another block out of the pool
    block = chunk->brk;
    chunk->brk += head->blocksize;
    chunk->avail--;

    return block;
}

void freepools(poolhead_t *head, int also_free_shared)
{
    while(head) {
        poolhead_t *next = head->next;
        if (head->magic != POOL_MAGIC)
            shmpanic("Invalid pool magic!");

        while(head->chunks) {
            chunk_t *chunk = head->chunks;
            if (chunk->magic != CHUNK_MAGIC)
              shmpanic("Invalid chunk magic!");

            head->chunks = head->chunks->next;
            if(head->share == NULL)
                ckfree(chunk->start);
            else if(also_free_shared)
                shmfree_raw(head->share, chunk->start);

            chunk->magic = 0;
            ckfree((char *)chunk);
        }

        head->magic = 0;
        ckfree((char *)head);
        head = next;
    }
}

// Take a specific block of memory out of the list of free memory.
void remove_from_freelist(shm_t   *shm, volatile freeblock *block)
{
    volatile freeblock *next = block->next, *prev = block->prev;
//IFDEBUG(fprintf(SHM_DEBUG_FP, "remove_from_freelist(shm, 0x%lX);\n", (long)block);)
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    prev = 0x%lX, next=0x%lX\n", (long)prev, (long)next);)
    if(block->magic != FREE_MAGIC)
        shmpanic("Invalid free block magic!");
    if(!next)
        shmpanic("Freeing freed block (next == NULL)!");
    if(!prev)
        shmpanic("Freeing freed block (prev == NULL)!");

    // We don't need this any more.
    block->magic = 0;
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

    if(prev->magic != FREE_MAGIC)
        shmpanic("Invalid free prev magic");
    if(prev->next != block)
        shmpanic("Corrupt free list (prev->next != block)!");
    if(next->magic != FREE_MAGIC)
        shmpanic("Invalid next prev magic");
    if(next->prev != block)
        shmpanic("Corrupt free list (next->prev != block)!");
        
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    set 0x%lX->next = 0x%lX\n", (long)prev, (long)next);)
    prev->next = next;
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    set 0x%lX->prev = 0x%lX\n", (long)next, (long)prev);)
    next->prev = prev;

#if 1
    // Adjust the start of the freelist to point to the block
    // prior to the one we just removed.  This ensures that we'll
    // avoid wasting time always walking over the same tiny blocks.
    shm->freelist = prev;
#else
    if(shm->freelist == block) {
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    set freelist = 0x%lX\n", (long)next);)
        shm->freelist = next;
    }
#endif
}

// Add a block of memory to the list of free memory available for immediate reuse.
void insert_in_freelist(shm_t   *shm, volatile freeblock *block)
{
    volatile freeblock *next, *prev;
//IFDEBUG(fprintf(SHM_DEBUG_FP, "insert_in_freelist(shm, 0x%lX);\n", (long)block);)

    if (block->magic != FREE_MAGIC)
      shmpanic("Invalid free magic");

    if(!shm->freelist) {
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    empty freelist, set all to block\n");)
        shm->freelist = block->next = block->prev = block;
        return;
    }
    next = block->next = shm->freelist;
    if (next->magic != FREE_MAGIC)
      shmpanic("Invalid next free magic");

    prev = block->prev = shm->freelist->prev;
    if (prev->magic != FREE_MAGIC)
      shmpanic("Invalid prev free magic");

//IFDEBUG(fprintf(SHM_DEBUG_FP, "    insert between 0x%lX and 0x%lX\n", (long)prev, (long)next);)
    next->prev = prev->next = block;
//IFDEBUG(fprintf(SHM_DEBUG_FP, "    done\n");)
}

// Prints out diagnostic information about the state of memory blocks.
static void shmdump(shm_t *shm)
{
    fprintf(stderr, "#DUMP 0x%08lx at 0x%08lx (%ld bytes)\n",
        (long)shm, (long)shm->map->addr, (long)shm->map->mapsize);

    freeblock *freelist = (freeblock *)shm->freelist;
    freeblock *freebase = freelist;

    while(freelist) {
        fprintf(stderr, "#  FREE BLOCK 0x%08lx (%ld bytes)\n", (long)freelist, (long)freelist->size);
        freelist = (freeblock *)freelist->next;
        if(freelist == freebase) break;
    }

    garbage *garbage = shm->garbage;
    while(garbage) {
        fprintf(stderr, "#  GARBAGE 0x%08lx (cycle 0x%08lx)\n", (long)garbage->memory, (long)garbage->cycle);
        garbage = garbage->next;
        if(garbage == shm->garbage) break;
    }

    fprintf(stderr, "#DUMP end\n");
    fflush(stderr);
}

// Return estimate of free memory available.  Does not include memory waiting to be garbage collected.
size_t shmfreemem(shm_t *shm, int check)
{
    if(!check) return shm->free_space;

    freeblock *freelist = (freeblock *)shm->freelist;
    freeblock *freebase = freelist;
    size_t freemem = 0;

    while(freelist) {
        if (freelist->magic != FREE_MAGIC) {
            shmpanic("Invalid free magic!");
        }
        if (freelist->size < sizeof(freeblock)) {
            shmpanic("Invalid freeblock size (was negative or too small)");
        }
        freemem += freelist->size;
        freelist = (freeblock *)freelist->next;
        if(freelist == freebase) break;
    }

    return freemem;
}

char *_shmalloc(shm_t   *shm, size_t nbytes)
{
    volatile freeblock *block = shm->freelist;
    freeblock *freebase = (freeblock*)block;
    size_t              needed;
IFDEBUG(fprintf(SHM_DEBUG_FP, "_shmalloc(shm_t  , %ld);\n", (long)nbytes);)

    // align size - increase requested size to a multiple of CELLSIZE
    if(nbytes % CELLSIZE)
        nbytes += CELLSIZE - nbytes % CELLSIZE;

    // Actual allocation includes our structure plus an upper sentinal.
    // We really only need room initall for a busyblock, but since the
    // freeblock struct is larger we need to ensure there is room to
    // also allow this block to become freed later.
    needed = nbytes + sizeof(freeblock) + CELLSIZE;

    // really a do-while loop, null check should never fail
    while(block) {
        ssize_t space = block->size;
        if (block->magic != FREE_MAGIC)
            shmpanic("invalid free magic");

        if(space < 0)
            shmpanic("trying to allocate non-free block");

        if (prevsize(nextblock(block)) != block->size)
            shmpanic("block upper sentinal size does not agree with header size");

        if(space >= needed) {
            size_t left = space - needed;
            size_t used = needed;

            // See if the remaining chunk is big enough to be worth saving
            if(left <= sizeof (freeblock) + 2 * CELLSIZE) {
                used = space;
                left = 0;
            }

	    shm->free_space -= used;
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

            if((char *)block < (char *)shm->map || (char *)block > (char *)shm->map + shm->map->mapsize)
                shmpanic("Ludicrous block!");
            return block2data(block);
        }

        if(block == block->next)
            break;

        block = block->next;

        if (block == freebase)
            break;
    }

    shared_errno = -SH_MAP_FULL;

// Change to "if(1)" to enable fallback panic
if (0) {
  static int debugcountdown = 30;
  if(debugcountdown-- <= 0) {
    shmpanic("out of memory");
  }
}
// Change to "if(1)" to dump shared memory when done
if (0) {
  fprintf(stderr, "_shmalloc(shm, 0x%08lx) failed\n", (long)nbytes);
  shmdump(shm);
}

    return NULL;
}

char *shmalloc_raw(shm_t   *shm, size_t size)
{
    char *block;
IFDEBUG(fprintf(SHM_DEBUG_FP, "shmalloc_raw(shm, %ld);\n", (long)size);)

    // align size
    if(size % CELLSIZE)
        size += CELLSIZE - size % CELLSIZE;

    if(!(block = palloc(shm->pools, size)))
        block = _shmalloc(shm, size);

    if(!block)
        return NULL;

    if (block < (char *)shm->map || (char *)block > (char *)shm->map + shm->map->mapsize)
        shmpanic("Ludicrous block!");
IFDEBUG(fprintf(SHM_DEBUG_FP, "shmalloc_raw(shm, %ld) => 0x%8lx\n", (long)size, (long)block);)

    return block;
}

// Add a block of memory into the garbage pool to be deleted later.
void shmfree_raw(shm_t *shm, char *memory)
{
    garbage *entry;

IFDEBUG(fprintf(SHM_DEBUG_FP, "shmfree_raw(shm, 0x%lX);\n", (long)block);)

    if(memory < (char *)shm->map || memory >= ((char *)shm->map)+shm->map->mapsize)
        shmpanic("Trying to free pointer outside mapped memory!");

    if(!shm->garbage_pool) {
        shm->garbage_pool = makepool(sizeof *entry, GARBAGE_POOL_SIZE, 0, NULL);
        if(!shm->garbage_pool)
            shmpanic("Can't create garbage pool");
    }

    entry = (garbage *)palloc(shm->garbage_pool, sizeof *entry);
    if(!entry)
        shmpanic("Can't allocate memory in garbage pool");

    entry->cycle = shm->map->cycle;
    entry->memory = memory;
    entry->next = shm->garbage;
    shm->garbage = entry;
IFDEBUG(fprintf(SHM_DEBUG_FP, "shmfree_raw to garbage pool 0x%08lx\n", (long)shm->garbage);)
}

// Attempt to put a pending freed block back in a pool
int shmdepool(poolhead_t *head, char *block)
{
    while(head) {
        chunk_t *chunk = head->chunks;
        if (head->magic != POOL_MAGIC)
          shmpanic("Invalid pool magic!");
        while(chunk) {
            pool_freelist_t *free;
            ssize_t offset = block - chunk->start;
            if (chunk->magic != CHUNK_MAGIC)
              shmpanic("Invalid chunk magic!");

            if(offset < 0 || offset > (head->nblocks * head->blocksize)) {
                chunk = chunk->next;
                continue;
            }

            if(offset % head->blocksize != 0)
                shmpanic("Unalligned free from pool!");

            // Thread block into free list. We do not store size in or coalesce
            // pool blocks, they're always all the same size, so all we have in
            // them is the address of the next free block.
            free = (pool_freelist_t *)block;
            free->next = head->freelist;
            head->freelist = free;

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
    volatile cell_t *cell;
    if (size <= sizeof(freeblock))
      shmpanic("Invalid block size!");

    block->magic = (is_free ? FREE_MAGIC : BUSY_MAGIC);
    block->size = (is_free ? ((ssize_t)size) : -((ssize_t)size));

    // put a trailing sentinal containing the size
    cell = (cell_t *) &((char *)block)[size]; // point to next block;
    cell--; // step back one word;
    *cell = is_free ? ((ssize_t)size) : -((ssize_t)size);
}

// attempt to free a block
// first, try to free it into a pool as an unstructured block
// then, thread it on the free list

// free block structure:
//    cell_t magic == FREE_MAGIC
//    cell_t size;
//    pointer next
//    pointer free
//    char unused[size - 12 - sizeof(freeblock)];
//    cell_t size;

// busy block structure:
//    cell_t magic == BUSY_MAGIC
//    cell_t -size;
//    char data[size-12];
//    cell_t -size;

int shmdealloc_raw(shm_t *shm, char *memory)
{
    ssize_t size;
    freeblock *block;
IFDEBUG(fprintf(SHM_DEBUG_FP, "shmdealloc_raw(shm=0x%lX, memory=0x%lX);\n", (long)shm, (long)memory);)

    if(memory < (char *)shm->map || memory >= ((char *)shm->map)+shm->map->mapsize)
        shmpanic("Trying to dealloc pointer outside mapped memory!");

    // Try and free it back into a pool.
    if(shmdepool(shm->pools, memory)) return 1;

    // step back to block header
    block = data2block(memory);
//IFDEBUG(fprintf(SHM_DEBUG_FP, "  block=0x%lX\n", (long)memory);)

    if (block->magic != BUSY_MAGIC)
        shmpanic("invalid busy magic");

    size = block->size;
//IFDEBUG(fprintf(SHM_DEBUG_FP, "  size=%ld\n", (long)size);)

    // negative size means it's allocated, positive it's free
    if(((ssize_t)size) > 0)
        shmpanic("freeing freed block");

    size = -size;

    shm->free_space += size;

    // merge previous freed blocks
    while(!is_prev_sentinal(block)) {
        freeblock *prev = prevblock(block);
        size_t new_size;

        if ((char*)prev < (char*)shm->map) {
          shmpanic("Previous block is outside mapped memory!");
        }

        if (prev->magic != FREE_MAGIC) {
          if (prev->magic != BUSY_MAGIC) {
            shmpanic("found bad magic for previous block");
          }
          break;
        }
        new_size = prev->size;
        if (new_size <= 0)
            shmpanic("invalid free size");
        if (prevsize(block) != new_size)
            shmpanic("inconsistent sizes at lower vs upper sentinal");

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
    while(!is_next_sentinal(block)) {
        freeblock *next = nextblock(block);
        size_t new_size;

        if((char*)next >= ((char *)shm->map)+shm->map->mapsize) {
          shmpanic("Next block is outside mapped memory!");
        }

        if (next->magic != FREE_MAGIC) {
          if (next->magic != BUSY_MAGIC) {
            shmpanic("found bad magic for previous block");
          }
          break;
        }

        new_size = next->size;
        if (new_size <= 0)
            shmpanic("invalid free size");
        if (nextsize(block) != new_size)
          shmpanic("inconsistent sizes at lower vs upper sentinal");

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

// Called by the master before making an update to shared-memory.
// Increments the cycle number and returns the new cycle number.
int write_lock(shm_t   *shm)
{
    volatile mapheader *map = shm->map;

    while(++map->cycle == LOST_HORIZON)
        continue;

    return map->cycle;
}

// Called by the master at the end of an update to shared-memory.
// Performs garbage collection of deleted memory blocks that are
// no longer being accessed by readers.
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


// Find the reader structure associated with a reader's pid.
// Returns NULL if no match found.
volatile reader *pid2reader(volatile mapheader *map, int pid)
{
    volatile reader_block *b = map->readers;
    if(!pid) return NULL;
    while(b) {
        if(b->count) {
            int i;
            for(i = 0; i < b->count && i < READERS_PER_BLOCK; i++)
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

    if(!pid) return 0;
    if(pid2reader(map, pid)) return 1;

    while(b) {
        int i;
        for(i = 0; i < b->count; i++) {
            if(b->readers[i].pid == 0) {
                b->readers[i].pid = pid;
                b->readers[i].cycle = LOST_HORIZON;
                return 1;
            }
        }
        if(b->count < READERS_PER_BLOCK) {
            b->readers[b->count].pid = pid;
            b->readers[b->count].cycle = LOST_HORIZON;
            b->count++;
            return 1;
        }
        b = b->next;
    }
    b = (reader_block *)shmalloc_raw(share, sizeof *b);
    if(!b) return 0;

    memset((void*)b, 0, sizeof *b);
    b->count = 0;
    b->next = map->readers;
    map->readers = (reader_block *)b;
    b->readers[b->count].pid = pid;
    b->readers[b->count].cycle = LOST_HORIZON;
    b->count++;
    return 1;
}

// Called by a reader to start a read transaction on the current state of memory.
// Returns the cycle number that is locked, or LOST_HORIZON (0) on error.
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

// Called by a reader to end a read transaction on the current state of memory.
void read_unlock(shm_t   *shm)
{
    volatile reader *self = shm->self;

    if(!self)
        return;

    self->cycle = LOST_HORIZON;
}

// Go through each garbage block and, if it's not in use by any readers, return it to the free list.
void garbage_collect(shm_t   *shm)
{
    garbage     *garbp = shm->garbage;
    garbage     *garbo = NULL;
    cell_t       horizon = shm->horizon;
    int          collected = 0;
    int          skipped = 0;

    if(horizon != LOST_HORIZON) {
        horizon -= TWILIGHT_ZONE;
        if(horizon == LOST_HORIZON)
            horizon --;
    }
IFDEBUG(fprintf(SHM_DEBUG_FP, "garbage_collect(shm);\n");)

    while(garbp) {
        int delta = horizon - garbp->cycle;
        if(horizon == LOST_HORIZON || garbp->cycle == LOST_HORIZON || delta > 0) {
            garbage *next = garbp->next;
            shmdealloc_raw(shm, garbp->memory);
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
IFDEBUG(fprintf(SHM_DEBUG_FP, "garbage_collect(shm): cycle 0x%08lx, horizon 0x%08lx, collected %d, skipped %d\n", (long)shm->map->cycle, (long)shm->horizon, collected, skipped);)
}

// Find the cycle number for the oldest reader.
cell_t oldest_reader_cycle(shm_t   *shm)
{
    volatile reader_block *r = shm->map->readers;
    cell_t new_cycle = LOST_HORIZON;
    cell_t map_cycle = shm->map->cycle;
    cell_t rdr_cycle = LOST_HORIZON;
    int oldest_age = 0;
    int age;

    while(r) {
        int i;
        for(i = 0; i < r->count && i < READERS_PER_BLOCK; i++) {
            if(r->readers[i].pid) {
                if (kill(r->readers[i].pid, 0) == -1) {
                    // Found a pid belonging to a dead process.  Remove it.
                    IFDEBUG(fprintf(SHM_DEBUG_FP, "oldest_reader_cycle: found dead reader pid %d, removing\n", (int) r->readers[i].pid);)
                    r->readers[i].pid = 0;
                    r->readers[i].cycle = LOST_HORIZON;
                    continue;
                }

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

    s = (symbol *)shmalloc_raw(shm, len);
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
                char *copy = shmalloc_raw(shm, strlen(value));
                if(!copy) return 0;

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

    while(isdigit((unsigned char)*s)) {
        size = size * 10 + *s - '0';
        s++;
    }
    switch(toupper((unsigned char)*s)) {
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

#ifdef WITH_FLAGS
    while(*s) {
        while(isspace((unsigned char)*s)) s++;

        word = s;
        while(*s && !isspace((unsigned char)*s)) s++;
        if(*s) *s++ = 0;

#ifdef MAP_NOCORE
             if(strcmp(word, "nocore") == 0) flags |= MAP_NOCORE;
        else if(strcmp(word, "core") == 0) flags &= ~MAP_NOCORE;
#ifdef MAP_NOSYNC
        else
#endif
#endif
#ifdef MAP_NOSYNC
             if(strcmp(word, "nosync") == 0) flags |= MAP_NOSYNC;
        else if(strcmp(word, "sync") == 0) flags &= MAP_NOSYNC;
#endif
    }
#endif
    return flags;
}

char *flags2string(int flags)
{
    static char buffer[32]; // only has to hold "nocore nosync shared"

    buffer[0] = 0;

#ifdef MAP_NOCORE
    if(flags & MAP_NOCORE)
        strcat(buffer, "nocore ");
    else
#endif
        strcat(buffer, "core ");

#ifdef MAP_NOSYNC
    if(flags & MAP_NOSYNC)
        strcat(buffer, "nosync ");
    else
#endif
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

// Note that making these static globals means that if you need to use multiple shared tables in a single
// program, they all have to be defined in the same speedtable C Extension! This should probably be fixed.
static int autoshare = 0;

static char *share_base = NULL;

void setShareBase(char *new_base)
{
        if(!share_base)
                share_base = new_base;
}

int doCreateOrAttach(Tcl_Interp *interp, char *sharename, char *filename, size_t size, int flags, shm_t **sharePtr)
{
    shm_t     *share;
    int        creator = 1;
    int        new_share = 1;

    if(size == ATTACH_ONLY) {
        creator = 0;
        size = 0;
    }

    if(strcmp(sharename, "#auto") == 0) {
        static char namebuf[32];
        sprintf(namebuf, "share%d", ++autoshare);
        sharename = namebuf;
    }

    share = map_file(filename, share_base, size, flags, creator);
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

    if(share_base == (char *)-1)
        share_base = (char *)share + size;
    else if((char *)share == share_base)
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
    int          cmdIndex  = -1;
    char        *sharename = NULL;
    shm_t       *share     = NULL;

    static CONST char *commands[] = {"create", "attach", "list", "detach", "names", "get", "multiget", "set", "info", "pools", "pool", "free", (char *)NULL};
    enum commands {CMD_CREATE, CMD_ATTACH, CMD_LIST, CMD_DETACH, CMD_NAMES, CMD_GET, CMD_MULTIGET, CMD_SET, CMD_INFO, CMD_POOLS, CMD_POOL, CMD_FREE };

    static CONST struct {
        int need_share;         // if a missing share is an error
        int nargs;              // >0 number args, <0 -minimum number
        char *args;             // String for Tcl_WrongNumArgs
    } template[] = {
        {0, -5, "filename size ?flags?"},  // CMD_CREATE
        {0,  4, "filename"}, // CMD_ATTACH
        {0, -2, "?share?"}, // CMD_LIST
        {1,  3, ""}, // CMD_DETACH
        {1, -3, "names"},  // CMD_NAMES
        {1, 4, "name"}, // CMD_GET
        {1, -4, "name ?name?..."}, // CMD_MULTIGET
        {1, -5, "name value ?name value?..."}, // CMD_SET
        {1,  3, ""}, // CMD_INFO
        {1,  3, ""}, // CMD_POOLS
        {1,  6, "size blocks/chunk max_chunks"}, // CMD_POOL
        {1,  -3, "?quick?"} // CMD_FREE
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

    // Find the share option now. It's not necessarily an error (yet) if it doesn't exist (in fact for
    // the create/attach option it's an error if it DOES exist).
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
            int        flags = DEFAULT_FLAGS;

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

        // list pools
        case CMD_POOLS: {
            poolhead_t *head;
            char tmp[32];
            pool_freelist_t *free;
            int avail;

            if((head = share->garbage_pool)) {

                avail = head->chunks ? head->chunks->avail : 0;
                for(free = head->freelist; free; free=free->next)
                    avail++;

                // garbage pool size is virtually zero.
                Tcl_AppendElement(interp, "0");
                sprintf(tmp, "%d", head->nblocks);
                Tcl_AppendElement(interp, tmp);
                sprintf(tmp, "%d", head->numchunks);
                Tcl_AppendElement(interp, tmp);
                sprintf(tmp, "%d", avail);
                Tcl_AppendElement(interp, tmp);

            }

            for(head = share->pools; head; head=head->next) {

                avail = head->chunks ? head->chunks->avail : 0;
                for(free = head->freelist; free; free=free->next)
                    avail++;

                sprintf(tmp, "%d", head->blocksize);
                Tcl_AppendElement(interp, tmp);
                sprintf(tmp, "%d", head->nblocks);
                Tcl_AppendElement(interp, tmp);
                sprintf(tmp, "%d", head->numchunks);
                Tcl_AppendElement(interp, tmp);
                sprintf(tmp, "%d", avail);
                Tcl_AppendElement(interp, tmp);

            }
            return TCL_OK;
        }

        // add a pool
        case CMD_POOL: {
            int nblocks;
            int blocksize;
            int maxchunks;
            if (Tcl_GetIntFromObj(interp, objv[3], &nblocks) == TCL_ERROR)
                return TCL_ERROR;
            if (Tcl_GetIntFromObj(interp, objv[4], &blocksize) == TCL_ERROR)
                return TCL_ERROR;
            if (Tcl_GetIntFromObj(interp, objv[5], &maxchunks) == TCL_ERROR)
                return TCL_ERROR;
            if(!shmaddpool(share, nblocks, blocksize, maxchunks)) {
                TclShmError(interp, "add pool");
                return TCL_ERROR;
            }
            return TCL_OK;
        }

        // Return miscellaneous info about the share as a name-value list
        case CMD_INFO: {
            Tcl_Obj *list = Tcl_NewObj();

// APPend STRING, INTeger, or BOOLean.
#define APPSTRING(i,l,s) Tcl_ListObjAppendElement(i,l,Tcl_NewStringObj(s,-1))
#define APPINT(i,l,n) Tcl_ListObjAppendElement(i,l,Tcl_NewIntObj(n))
#define APPWIDEINT(i,l,n) Tcl_ListObjAppendElement(i,l,Tcl_NewWideIntObj(n))
#define APPBOOL(i,l,n) Tcl_ListObjAppendElement(i,l,Tcl_NewBooleanObj(n))

            if( TCL_OK != APPSTRING(interp, list, "size")
             || TCL_OK != APPWIDEINT(interp, list, share->size)
             || TCL_OK != APPSTRING(interp, list, "flags")
             || TCL_OK != APPSTRING(interp, list, flags2string(share->flags))
             || TCL_OK != APPSTRING(interp, list, "name")
             || TCL_OK != APPSTRING(interp, list, share->name)
             || TCL_OK != APPSTRING(interp, list, "creator")
             || TCL_OK != APPBOOL(interp, list, share->creator)
             || TCL_OK != APPSTRING(interp, list, "filename")
             || TCL_OK != APPSTRING(interp, list, share->filename)
             || TCL_OK != APPSTRING(interp, list, "base")
             || TCL_OK != APPINT(interp, list, (long)share->map)
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
            char *name = Tcl_GetString(objv[3]);
            char *s = get_symbol(share, name, SYM_TYPE_STRING);
            if(!s) {
                Tcl_ResetResult(interp);
                Tcl_AppendResult(interp, "Unknown name ",name," in ",sharename, NULL);
                return TCL_ERROR;
            }
            Tcl_SetResult(interp, s, TCL_VOLATILE);
            return TCL_OK;
        }

        case CMD_MULTIGET: {
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

        case CMD_FREE: {
            // TODO: this could be a compile-time selection.
	    // TODO: actually test if objv[3] == 'quick'
            size_t memfree = shmfreemem(share, objc<=3);

            if (sizeof(size_t) > sizeof(int)) {
                Tcl_SetObjResult(interp, Tcl_NewWideIntObj(memfree));
            } else {
                Tcl_SetObjResult(interp, Tcl_NewIntObj(memfree));
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

#ifdef SHARED_GUARD
static void shmhexdump(unsigned char* start, size_t length)
{
        int i;
        fprintf(stderr, "\n0x%lX", (long)start);
        for(i = 0; i < length; i++) {
                fprintf(stderr, " %02x", start[i]);
        }
        fprintf(stderr, "\n0x%lX", (long)start);
        for(i = 0; i < length; i++) {
                if(start[i] < 0x7F && start[i] > 0x1F) {
                        fprintf(stderr, "  %c", start[i]);
                } else {
                        fprintf(stderr, "   ");
                }
        }
        fprintf(stderr, "\n");
}

char *shmalloc_guard(shm_t *map, size_t size LOGPARAMS)
{
    unsigned char *memory = (unsigned char *)shmalloc_raw(map, size+GUARD_SIZE * 2 + CELLSIZE);
    if(memory) {
#ifdef SHARED_LOG
        if(logfp) {
            fprintf(logfp, "%s:%d alloc %ld @ 0x%lx\n", File, Line, (long)size, (long)(memory+GUARD_SIZE + CELLSIZE));
            fflush(logfp);
        }
#endif
        int i;

        for(i = 0; i < GUARD_SIZE; i++)
            *memory++ = 0xA5;

        ((cell_t *)memory)[0] = size;
        memory += CELLSIZE;

        for(i = 0; i < GUARD_SIZE; i++)
            memory[size + i] = 0xA5;
    }
#ifdef SHARED_LOG
    else
        if(logfp) {
            fprintf(logfp, "%s:%d alloc %ld FAILED\n", File, Line, (long)size);
            fflush(logfp);
        }
#endif
    return (char *)memory;
}

void shmfree_guard(shm_t *map, char *block LOGPARAMS)
{
    unsigned char *memory = (unsigned char *)block - CELLSIZE - GUARD_SIZE;
    int size;
#ifdef SHARED_LOG
    if(logfp) {
        fprintf(logfp, "%s:%d free @ 0x%lx\n", File, Line, (long)block);
        fflush(logfp);
    }
#endif

    int i;

    for(i = 0; i < GUARD_SIZE; i++)
        if(memory[i] != 0xA5) {
            shmhexdump(memory, GUARD_SIZE * 2);
            shmpanic("Bad low guard!");
        }
    size = ((cell_t *)block)[-1];

    for(i = 0; i < GUARD_SIZE; i++)
        if(memory[i+size+CELLSIZE+GUARD_SIZE] != 0xA5) {
            shmhexdump(memory + size + CELLSIZE + GUARD_SIZE, GUARD_SIZE * 2);
            shmpanic("Bad high guard!");
        }

    shmfree_raw(map, (char *)memory);
}

int shmdealloc_guard(shm_t *shm, char *data LOGPARAMS)
{
    unsigned char *memory = (unsigned char *)data - CELLSIZE - GUARD_SIZE;
    int size;
#ifdef SHARED_LOG
    if(logfp) {
        fprintf(logfp, "%s:%d dealloc @ 0x%lx\n", File, Line, (long)data);
        fflush(logfp);
    }
#endif

    int i;

    for(i = 0; i < GUARD_SIZE; i++)
        if(memory[i] != 0xA5) {
            shmhexdump(memory, GUARD_SIZE * 2);
            shmpanic("Bad low guard!");
        }
    size = ((cell_t *)data)[-1];

    for(i = 0; i < GUARD_SIZE; i++)
        if(memory[i+size+CELLSIZE+GUARD_SIZE] != 0xA5) {
            shmhexdump(memory + size + CELLSIZE + GUARD_SIZE, GUARD_SIZE * 2);
            shmpanic("Bad high guard!");
        }

    return shmdealloc_raw(shm, (char *)memory);
}
#endif
