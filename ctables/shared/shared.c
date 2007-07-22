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

static mapinfo *mapinfo_list;

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

    p = (mapinfo *)malloc(sizeof (*p));
    if(!p) {
	shared_errno = SH_PRIVATE_MEMORY;
	munmap(map, size);
	close(fd);
	return NULL;
    }

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
    char	*map;
    size_t	 size;
    int		 fd;

    // remove from list
    if(!mapinfo_list) {
	shared_errno = -SH_NO_MAP;
	return 0;
    } else if(mapinfo_list == info) {
	mapinfo_list = info->next;
    } else {
	mapinfo *p = mapinfo_list;

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
    free(info);

    munmap(map, size);
    close(fd);

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

	free(p);

	munmap(map, size);
	close(fd);
    }
}

int shmcheckmap(volatile mapheader *map)
{
    if(map->magic != MAP_MAGIC) return 0;
    if(map->headersize != sizeof *map) return 0;
    return 1;
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
    map->namelist = NULL;

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

    setfree((freeblock *)block, freesize, FALSE);

    //  One block containing a 0, upper sentinel.
    *((cell_t *)(((char *)block) + freesize)) = 0;

    // Finally, initialize the free list by freeing it.
    shmdealloc(mapinfo, (char *)&block[1]);
}

pool *initpool(char *memory, size_t blocksize, int blocks)
{
    pool *new = (pool *)malloc(sizeof *new);
    if(!new) {
	shared_errno = SH_PRIVATE_MEMORY;
	return NULL;
    }
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
    char *memory;
    pool *pool;

    // align size
    if(blocksize % CELLSIZE)
	blocksize += CELLSIZE - blocksize % CELLSIZE;
    
    memory = _shmalloc(mapinfo, blocksize*blocks);
    if(!memory) return 0;

    pool = initpool(memory, blocksize, blocks);
    pool->next = mapinfo->pools;
    mapinfo->pools = pool;
    return 1;
}

pool *mallocpool(size_t blocksize, int blocks)
{
    char *memory;

    // align size
    if(blocksize % CELLSIZE)
	blocksize += CELLSIZE - blocksize % CELLSIZE;

    memory = (char *)malloc(blocksize * blocks);
    if(!memory) {
	shared_errno = SH_PRIVATE_MEMORY;
	return NULL;
    }
    return initpool(memory, blocksize, blocks);
}

char *palloc(pool *pool, size_t wanted)
{
    char *block;

    // align size
    if(wanted % CELLSIZE)
	wanted += CELLSIZE - wanted % CELLSIZE;

    while(pool && (pool->avail <= 0 || pool->blocksize != wanted))
	pool = pool->next;

    if(pool == NULL)
	return NULL;

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
	    shmpanic("Corrupt free list");
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

char *_shmalloc(mapinfo *mapinfo, size_t nbytes)
{
    volatile freeblock *block = mapinfo->freelist;
    size_t 		needed = nbytes + 2 * CELLSIZE;

    // align size
    if(nbytes % CELLSIZE)
	nbytes += CELLSIZE - nbytes % CELLSIZE;

    while(block) {
	int space = block->size;

	if(space < 0)
	    shmpanic("trying to allocate non-free block");

	if(space > needed) {
	    int remnant = space - needed;


	    remove_from_freelist(mapinfo, block);

	    // See if the remaining chunk is big enough to be worth using
	    if(remnant < sizeof (freeblock) + 2 * CELLSIZE) {
		needed = space;
	    } else {
		freeblock *new_block = (freeblock *)(((char *)block) + needed);

		// add it into the free list
		setfree(new_block, remnant, TRUE);
		insert_in_freelist(mapinfo, new_block);
	    }

	    setfree(block, needed, FALSE);
	    return block2data(block);
	}

	block = block->next;
    }

    return NULL;
}

char *shmalloc(mapinfo *mapinfo, size_t size)
{
    char *block;

    // align size
    if(size % CELLSIZE)
	size += CELLSIZE - size % CELLSIZE;

    if(!(block = palloc(mapinfo->pools, size)))
	block = _shmalloc(mapinfo, size);
    return block;
}

void shmfree(mapinfo *mapinfo, char *block)
{
    pool *pool = mapinfo->garbage_pool;
    garbage *entry = (garbage *)palloc(pool, GARBAGE_POOL_SIZE);

    if(!entry) {
	pool = mallocpool(sizeof (garbage), GARBAGE_POOL_SIZE);
	if(!pool)
	    shmpanic("Can't allocate memory for garbage pool");

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
void setfree(volatile freeblock *block, size_t size, int is_free)
{
    volatile cell_t *cell = (cell_t *)block;
    *cell = is_free ? size : -size;
    cell = (cell_t *) &((char *)cell)[size]; // point to next block;
    cell--; // step back one word;
    *cell = is_free ? size : -size;
}

// attempt to free a block
// first, try to free it into a pool as an unstructured block
// then, thread it on the free list
// TODO: coalesce the free list

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

int shmdealloc(mapinfo *mapinfo, char *memory)
{
    size_t size;
    freeblock *block;

    // Try and free it back into a pool.
    if(shmdepool(mapinfo->pools, memory)) return 1;

    // step back to block header
    block = data2block(memory);

    size = block->size;

    // negative size means it's allocated, positive it's free
    if(((int)size) > 0)
	shmpanic("freeing freed block");

    size = -size;
    setfree(block, size, TRUE);

    // contents of free block is a freelist entry, create it
    block->next = block->prev = NULL;

    // merge previous freed blocks
    while(prevsize(block) > 0) {
	freeblock *prev = prevblock(block);

	// increase the size of the previous block to include this block
	size += prevsize(block);
	setfree(prev, size, TRUE);

	// *become* the previous block
	block = prev;

	// remove it from the free list
	remove_from_freelist(mapinfo, block);
    }

    // merge following free blocks
    while(((int)nextsize(block)) > 0) {
	freeblock *next = nextblock(block);

	// remove next from the free list
	remove_from_freelist(mapinfo, next);

	// increase the size of this block to include it
	size += nextsize(block);
	setfree(block, size, TRUE);
    }

    insert_in_freelist(mapinfo, block);
    return 1;
}

int write_lock(mapinfo *mapinfo)
{
    volatile mapheader *map = mapinfo->map;

    while(++map->cycle == LOST_HORIZON)
	continue;

    return map->cycle;
}

void write_unlock(mapinfo *mapinfo)
{
#ifdef LAZY_GC
    static garbage_strike = 0;
    if(++garbage_strike < LAZY_GC) return;
    garbage_strike = 0;
#endif
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
	    shmdepool(pool, (char *)garbp);
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

int add_symbol(mapinfo *mapinfo, char *name, char *value, int type)
{
    int i;
    int namelen = strlen(name);
    volatile mapheader *map = mapinfo->map;
    volatile symbol *s;
    int len = sizeof(symbol) + namelen + 1;
    if(type == SYM_TYPE_STRING)
	len += strlen(value) + 1;

    s = (symbol *)shmalloc(mapinfo, len);

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

// Get a symbol back.
char *get_symbol(mapinfo *mapinfo, char *name, int wanted)
{
    volatile mapheader *map = mapinfo->map;
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

#ifdef WITH_TCL
int TclGetSizeFromObj(Tcl_Interp *interp, Tcl_Obj *obj, int *ptr)
{
    char *s = Tcl_GetString(obj);
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
    if(*s) {
	Tcl_ResetResult(interp);
	Tcl_AppendResult(interp, "Bad size, must be an integer optionally followed by 'k', 'm', or 'g': ", Tcl_GetString(obj), NULL);
	return TCL_ERROR;
    }

    *ptr = size;
    return TCL_OK;
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

static named_share *sharelist;
static int autoshare = 0;

int doCreateOrAttach(Tcl_Interp *interp, char *sharename, char *filename, size_t size, named_share **sharePtr)
{
    named_share    *share;
    mapinfo   *info;
    int	       creator = 1;

    if(size == ATTACH_ONLY) {
	creator = 0;
	size = 0;
    }

    info = map_file(filename, NULL, size);
    if(!info) {
	TclShmError(interp, filename);
	return TCL_ERROR;
    }
    if(creator) {
	shminitmap(info);
    } else if(!shmcheckmap(info->map)) {
	Tcl_AppendResult(interp, "Not a valid share: ", filename, NULL);
	unmap_file(info);
        return TCL_ERROR;
    }

    if(strcmp(sharename, "#auto") == 0) {
	static char namebuf[32];
	sprintf(namebuf, "share%d", ++autoshare);
	sharename = namebuf;
    }

    share = (named_share *)ckalloc(sizeof (named_share) + strlen(sharename) + 1);

    strcpy(share->name, sharename);
    share->next = sharelist;
    share->mapinfo = info;
    share->creator = size != 0;
    sharelist = share;

    if(sharePtr)
	*sharePtr = share;
    else
        Tcl_AppendResult(interp, sharename, NULL);

    return TCL_OK;
}

int doDetach(Tcl_Interp *interp, named_share *share)
{
    if(sharelist) {
        if(sharelist->next == share) {
	    sharelist = sharelist->next;
        } else {
            named_share *p = sharelist;
    
            while(p && p->next != share)
		p = p->next;
    
	    if(p)
	        p->next = share->next;
        }
    }

    if(!unmap_file(share->mapinfo)) {
	TclShmError(interp, share->name);
	return TCL_ERROR;
    }
    ckfree((char *)share);
     
    return TCL_OK;
}
#endif

#ifdef SHARED_TCL_EXTENSION
int shareCmd (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])
{
    int   	 cmdIndex;
    char	*sharename;
    named_share	*share;

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

    share = sharelist;
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
	        volatile symbol *sym = share->mapinfo->map->namelist;
	        while(sym) {
		    Tcl_AppendElement(interp, (char *)sym->name);
		    sym = sym->next;
	        }
	    } else {
		int i;
		for (i = 3; i < objc; i++) {
		    char *name = Tcl_GetString(objv[i]);
		    if(get_symbol(share->mapinfo, name, SYM_TYPE_ANY))
			Tcl_AppendElement(interp, name);
		}
	    }
	    return TCL_OK;
	}
	case CMD_GET: {
	    int   i;
	    for (i = 3; i < objc; i++) {
		char *name = Tcl_GetString(objv[i]);
		char *s = get_symbol(share->mapinfo, name, SYM_TYPE_STRING);
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
		if(get_symbol(share->mapinfo, name, TYPE_ANY))
		    set_symbol(share->mapinfo, name, Tcl_GetString(objv[i+1]), TYPE_STRING);
		else
		    add_symbol(share->mapinfo, name, Tcl_GetString(objv[i+1]), SYM_TYPE_STRING);
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
