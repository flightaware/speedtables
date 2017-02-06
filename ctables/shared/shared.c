/*
 * speedtables shared memory support
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




// Data that must be shared between multiple speedtables C extensions
//
// NB we used Tcl's interpreter-associated property lists to create, find and
// share the data.  Ideally we would have that C code in a shared library that
// the shared libraries we make invoke.
//
// NB this should be global to the program.  right now we support only one
// Tcl interpreter because of our approach of using assoc data.
//
struct speedtablesAssocData {
    int      autoshare;
    char    *share_base;
    shm_t   *share_list;
};

static struct speedtablesAssocData *assocData = NULL;
#define ASSOC_DATA_KEY "speedtables"


#ifndef WITH_TCL
char *ckalloc(size_t size)
{
    char *p = (char*) malloc(size);
    if(!p)
        shmpanic("Out of memory!");
    return p;
}
# define ckfree(p) free(p)
#endif

static char last_shmem_error[256] = { '\0' };
void set_last_shmem_error(const char *message) {
    strncpy(last_shmem_error, message, sizeof(last_shmem_error));
}

const char *get_last_shmem_error() {
    return last_shmem_error;
}

// Callable by master or slaves.
void shared_perror(const char *text) {
    if(last_shmem_error[0] != '\0') {
        fprintf(stderr, "%s: %s\n", text, last_shmem_error);
    } else {
        perror(text);
    }
}


#ifdef WITH_TCL
// linkup_assoc_data - attach the bits of data that multiple speedtables
// C shared libraries need to share.
// Callable by master or slaves.
static void
linkup_assoc_data (Tcl_Interp *interp)
{
    if (assocData != NULL) {
      //IFDEBUG(fprintf(SHM_DEBUG_FP, "previously found assocData at %lX\n", (long unsigned int)assocData);)
        return;
    }

    // locate the associated data 
    assocData = (struct speedtablesAssocData *)Tcl_GetAssocData (interp, ASSOC_DATA_KEY, NULL);
    if (assocData != NULL) {
        //IFDEBUG(fprintf(SHM_DEBUG_FP, "found assocData at %lX\n", (long unsigned int)assocData);)
        return;
    }

    assocData = (struct speedtablesAssocData *)ckalloc (sizeof (struct speedtablesAssocData));
    assocData->autoshare = 0;
    assocData->share_base = NULL;
    assocData->share_list = NULL;

    //IFDEBUG(fprintf(SHM_DEBUG_FP, "on interp %lX, constructed assocData at %lX\n", (long unsigned int) interp, (long unsigned int)assocData);)
    Tcl_SetAssocData (interp, ASSOC_DATA_KEY, NULL, (ClientData)assocData);
}
#endif


// map_file - map a file at addr. If the file doesn't exist, create it first
// with size default_size. Return share or NULL on failure.
//
// If the file has already been mapped, return the share associated with the
// file. The file check is purely by name, if multiple different names are
// used by the same process for the same file the result is undefined.
//
// If the file is already mapped, but at a different address, this is an error
//
// Callable by master or slaves.
//
shm_t *map_file(const char *file, char *addr, size_t default_size, int flags, int create)
{
    shm_t *p = assocData->share_list;


    // Look for an already mapped share
    while(p) {
        //IFDEBUG(fprintf (SHM_DEBUG_FP, "map_file: checking '%s' against '%s'\n", file, p->filename);)
        if(file && p->filename && strcmp(p->filename, file) == 0) {
            if((addr != NULL && addr != (char *)p->map)) {
		//IFDEBUG(fprintf (SHM_DEBUG_FP, "map_file: map address mismatch between %lX and %lX, mapping to the latter\n", (long unsigned int)addr, (long unsigned int)p->map);)
            }
            if(default_size && default_size > p->size) {
		//IFDEBUG(fprintf (SHM_DEBUG_FP, "map_file: requested size %ld bigger than segment size %ld\n", (long)default_size, (long)p->size);)
                return NULL;
            }
	    //IFDEBUG(fprintf (SHM_DEBUG_FP, "map_file: resolved '%s' to same map at %lX\n", file, (long unsigned int)p);)
	    p->attach_count++;
            return p;
        }
        p = p->next;
    }

    managed_mapped_file *mmf;
    mapheader_t *mh;
    try {
        //fprintf(stderr, "want to %s to %s at %p\n", (create != 0 ? "create" : "attach"), file, addr);

        if (create != 0) {
	    mmf = new managed_mapped_file(open_or_create, file, default_size, (void*)addr);
	} else {
            mmf = new managed_mapped_file(open_only, file, (void*)addr);
	}

	//fprintf(stderr, "created managed_mapped_file\n");

	mh = mmf->find_or_construct<mapheader_t>("mapheader")();
    } catch (interprocess_exception &Ex) {
        snprintf(last_shmem_error, sizeof(last_shmem_error), "caught error while initialized managed_mapped_file: %s\n", Ex.what());
        return NULL;
    }

    p = (shm_t*)ckalloc(sizeof(shm_t));
    p->filename = (char *) ckalloc(strlen(file)+1);
    strcpy(p->filename, file);

    // Completely initialise all fields!
    p->map = mh;
    p->managed_shm = mmf;
    p->share_base = addr;
    p->size = default_size;
    p->flags = flags;
    p->fd = -1;
    p->name = NULL;
    p->creator = 0;
    p->garbage = NULL;
    p->horizon = LOST_HORIZON;
    p->self = NULL;
    p->objects = NULL;
    p->attach_count = 1;

    // Hook in this new structure.
    p->next = assocData->share_list;
    assocData->share_list = p;

    return p;
}

// unmap_file - Unmap the open and mapped associated with the memory mapped
// for share. Return 0 on error, -1 if the map is still busy, 1 if it's
// been umapped.
// Callable by master or slaves.
int unmap_file(shm_t   *share)
{
    volatile reader_t   *r;

    // If there's anyone still using the share, it's a no-op
    if(share->objects) {
        return -1;
    }

    // if we have multiple attachments and this isn't the last one, we're done
    if (--share->attach_count > 0) {
        return 1;
    }

    // remove from list
    if(!assocData->share_list) {
        return 0;
    } else if(assocData->share_list == share) {
        assocData->share_list = share->next;
    } else {
        shm_t   *p = assocData->share_list;

        while(p && p->next != share) {
            p = p->next;
	}

        if(!p) {
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


    if (share->garbage != NULL) {
      delete share->garbage;
    }
    ckfree(share->filename);
    delete share->managed_shm;

    ckfree((char*)share);

    return 1;
}

// unmap_all - Unmap all mapped files.
// Callable by master or slaves.
void unmap_all(void)
{
    while(assocData->share_list) {
        shm_t *p    = assocData->share_list;
        shm_t *next = p->next;

	unmap_file(p);

	assocData->share_list = next;
    }
}


// Initialize a map file for use.
// Should only be called by the master.
void shminitmap(shm_t   *shm)
{
    volatile mapheader_t  *map = shm->map;

    // COMPLETELY initialise map.
    map->magic = MAP_MAGIC;
    map->headersize = sizeof(mapheader_t);
    map->mapsize = shm->size;
    map->addr = shm->share_base;
    map->namelist = NULL;
    map->cycle = LOST_HORIZON;
    memset((void*)map->readers, 0, sizeof(reader_t) * MAX_SHMEM_READERS);

    // freshly mapped, so this stuff is void
    shm->garbage = new deque<garbage_t>();
    shm->horizon = LOST_HORIZON;

    // Remember that we own this.
    shm->creator = 1;

}



// Return estimate of free memory available.  Does not include memory waiting to be garbage collected.
// Callable only by master.
size_t shmfreemem(shm_t *shm, int /*check*/)
{
    return shm->managed_shm->get_free_memory();
}

// Allocate some memory from the shared-memory heap.
// May return NULL if the allocation failed.
// Callable only by master.
void *_shmalloc(shm_t   *shm, size_t nbytes)
{
    return shm->managed_shm->allocate(nbytes, std::nothrow);
}

// Allocate some memory from the shared-memory heap.
// May return NULL if the allocation failed.
// Callable only by master.
void *shmalloc_raw(shm_t   *shm, size_t nbytes)
{
    return shm->managed_shm->allocate(nbytes, std::nothrow);
}

// Add a block of memory into the garbage pool to be deleted later.
// Callable only by master.
void shmfree_raw(shm_t *shm, void *memory)
{
    garbage_t entry;

    entry.cycle = shm->map->cycle;
    entry.memory = (char*)memory;

    assert(shm->garbage != NULL && "master is missing garbage queue");

    // newer deletions are always added to the end, so that the oldest are at the front.
    shm->garbage->push_back(entry);
}


// Free a block immediately.
// Callable only by master.
int shmdealloc_raw(shm_t *shm, void *memory)
{
    shm->managed_shm->deallocate(memory);
    return 1;
}

// Called by the master before making an update to shared-memory.
// Increments the cycle number and returns the new cycle number.
int write_lock(shm_t   *shm)
{
    volatile mapheader_t *map = shm->map;

    while(++map->cycle == LOST_HORIZON) {
        continue;
    }

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
    if(new_horizon == LOST_HORIZON) {
        new_horizon = shm->map->cycle;
    }

    age = new_horizon - shm->horizon;

    if(age > TWILIGHT_ZONE) {
        shm->horizon = new_horizon;
        garbage_collect(shm);
    }
}


// Find the reader structure associated with a reader's pid.
// Callable by slaves.
// Returns NULL if no match found.
volatile reader_t *pid2reader(volatile mapheader_t *map, int pid)
{
    for (unsigned i = 0; i < MAX_SHMEM_READERS; i++) {
        if(map->readers[i].pid == (cell_t)pid) {
	    return &map->readers[i];
        }
    }
    return NULL;
}


// Add client (pid) to the list of readers.
// Callable by master.
// Returns 1 on success, 0 on failure.
int shmattachpid(shm_t   *share, int pid)
{
    volatile mapheader_t *map = share->map;

    if(!pid) return 0;         // invalid pid
    if(pid2reader(map, pid)) return 1;    // success, already added.

    for (unsigned i = 0; i < MAX_SHMEM_READERS; i++) {
        if (map->readers[i].pid == 0) {
	    map->readers[i].pid = (cell_t)pid;
	    map->readers[i].cycle = LOST_HORIZON;
	    return 1;     // successfully added.
	}
    }

    return 0;     // no space for any more readers.
}

// Called by a reader to start a read transaction on the current state of memory.
// Callable by slaves.
// Returns the cycle number that is locked, or LOST_HORIZON (0) on error.
int read_lock(shm_t   *shm)
{
    volatile mapheader_t *map = shm->map;
    volatile reader_t *self = shm->self;

    if(!self) {
        shm->self = self = pid2reader(map, getpid());
    }
    if(!self) {
        fprintf(stderr, "%d: Can't find reader slot!\n", getpid());
        return LOST_HORIZON;
    }
    return self->cycle = map->cycle;
}

// Called by a reader to end a read transaction on the current state of memory.
// Callable by slaves.
void read_unlock(shm_t   *shm)
{
    volatile reader_t *self = shm->self;

    if(!self)
        return;

    self->cycle = LOST_HORIZON;
}

// Go through each garbage block and, if it's not in use by any readers, return it to the free list.
// Callable only by master.
void garbage_collect(shm_t   *shm)
{
    cell_t       horizon = shm->horizon;
    int          collected = 0;

    if(horizon != LOST_HORIZON) {
        horizon -= TWILIGHT_ZONE;
        if(horizon == LOST_HORIZON)
            horizon--;
    }

    assert(shm->garbage != NULL && "master is missing garbage queue");

    while(!shm->garbage->empty()) {
	garbage_t &garbp = shm->garbage->front();

        int delta = horizon - garbp.cycle;
        if(horizon == LOST_HORIZON || garbp.cycle == LOST_HORIZON || delta > 0) {
            shmdealloc_raw(shm, garbp.memory);
	    shm->garbage->pop_front();
            collected++;
        } else {
            // stop when we find one that is still pending, since it is ordered by cycle.
	    break;
        }
    }

//IFDEBUG(fprintf(SHM_DEBUG_FP, "garbage_collect(shm): cycle 0x%08lx, horizon 0x%08lx, collected %d, skipped %d\n", (long)shm->map->cycle, (long)shm->horizon, collected, shm->garbage->size());)
}

// Find the cycle number for the oldest reader.
// Callable only by master.
cell_t oldest_reader_cycle(shm_t   *shm)
{
    volatile mapheader_t *map  = shm->map;
    cell_t new_cycle = LOST_HORIZON;
    cell_t map_cycle = map->cycle;
    cell_t rdr_cycle = LOST_HORIZON;
    int oldest_age = 0;
    int age;

    for(unsigned i = 0; i < MAX_SHMEM_READERS; i++) {
        if(map->readers[i].pid) {
	    if (kill(map->readers[i].pid, 0) == -1) {
	        // Found a pid belonging to a dead process.  Remove it.
	        //IFDEBUG(fprintf(SHM_DEBUG_FP, "oldest_reader_cycle: found dead reader pid %d, removing\n", (int) map->readers[i].pid);)
	        map->readers[i].pid = 0;
	        map->readers[i].cycle = LOST_HORIZON;
	        continue;
	    }

	    rdr_cycle = map->readers[i].cycle;

	    if(rdr_cycle == LOST_HORIZON)
	        continue;

	    age = map_cycle - rdr_cycle;

	    if(new_cycle == LOST_HORIZON || age >= oldest_age) {
	        oldest_age = age;
		new_cycle = rdr_cycle;
	    }
	}
    }
    return new_cycle;
}


#ifdef WITH_SHMEM_SYMBOL_LIST
// Add a symbol to the internal namelist. This will allow the master to
// pass things like the address of a ctable to the reader without having
// more addresses than necessary involved.
//
// Constraint - these entries are never deallocated (though they may be
// removed from the list) and the list is never updated with an incomplete
// entry, so no locking is necessary.

int add_symbol(shm_t   *shm, CONST char *name, char *value, int type)
{
    int namelen = strlen(name);
    volatile mapheader_t *map = shm->map;
    volatile symbol_t *s;
    int len = sizeof(symbol_t) + namelen + 1;
    if(type == SYM_TYPE_STRING)
        len += strlen(value) + 1;

    s = (symbol_t *)shmalloc_raw(shm, len);
    if(!s) return 0;

    memcpy((void*)(s->name), name, namelen + 1);

    if(type == SYM_TYPE_STRING) {
        s->addr = &s->name[namelen+1];
        len = strlen(value);
        memcpy((void*)(s->addr), value, len + 1);
    } else {
        // take ownership of the pointer.
        s->addr = value;
    }

    s->type = type;

    s->next = map->namelist;
    //fprintf(stderr, "add_symbol(%d) is saving %s at %p\n", (int)getpid(), name, s);
    map->namelist = s;

    return 1;
}

// Change the value of a symbol. Note that old values of symbols are never
// freed, because we don't know what they're used for and we don't want to
// lock the garbage collector for long-term symbol use. It's up to the
// caller to determine if the value can be freed and to do it.
int set_symbol(shm_t *shm, CONST char *name, char *value, int type)
{
    volatile mapheader_t *map = shm->map;
    volatile symbol_t *s = map->namelist;
    while(s) {
        if(strcmp(name, (char *)s->name) == 0) {
            if(type != SYM_TYPE_ANY && type != s->type) {
                return 0;
            }
            if(type == SYM_TYPE_STRING) {
	        char *copy = (char*) shmalloc_raw(shm, strlen(value));
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
char *get_symbol(shm_t *shm, CONST char *name, int wanted)
{
    volatile mapheader_t *map = shm->map;
    volatile symbol_t *s = map->namelist;
    while(s) {
        if(strcmp(name, (const char*) s->name) == 0) {
            if(wanted != SYM_TYPE_ANY && wanted != s->type) {
                return NULL;
            }
	    //fprintf(stderr, "get_symbol(%d) found %s at %p\n", (int)getpid(), name, s);
            return (char *) s->addr;
        }
        s = s->next;
    }
    return (char*) NULL;
}
#endif // WITH_SHMEM_SYMBOL_LIST


// Attach to an object (represented by an arbitrary string) in the shared
// memory file.  Always returns 1.
int use_name(shm_t *share, const char *name)
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
void release_name(shm_t *share, const char *name)
{
    object_t *ob = share->objects;
    object_t *prev = NULL;
    while(ob) {
        if(strcmp(ob->name, name) == 0) {
            if(prev) prev->next = ob->next;
            else share->objects = ob->next;
            ckfree((char*)ob);
            return;
        }
        prev = ob;
        ob = ob->next;
    }
}

// Fatal error
void shmpanic(const char *s)
{
    fprintf(stderr, "PANIC: %s\n", s);
    abort();
}

// parse a string of type "nnnnK" or "mmmmG" to bytes;
int parse_size(const char *s, size_t *ptr)
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

// NOTE: modifies the supplied string while parsing it.
int parse_flags(char * /*s*/)
{
    int   flags = 0;     // we don't actually support any flags anymore, so we ignore the input.

    return flags;
}

// NOTE: returns a pointer to a static buffer.
const char *flags2string(int flags)
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

void TclShmError(Tcl_Interp *interp, const char *name)
{
  Tcl_AppendResult(interp, get_last_shmem_error(), NULL);
}

void setShareBase(Tcl_Interp *interp, char *new_base)
{
    if (assocData == NULL) {
        linkup_assoc_data(interp);
    }

    if(!assocData->share_base) {
        assocData->share_base = new_base;
    }
}

int doCreateOrAttach(Tcl_Interp *interp, const char *sharename, const char *filename, size_t size, int flags, shm_t **sharePtr)
{
    shm_t     *share;
    int        creator = 1;
    int        new_share = 1;

    if (assocData == NULL) {
        linkup_assoc_data(interp);
    }

    if (size == ATTACH_ONLY) {
        creator = 0;
        size = 0;
    }

    if (strcmp(sharename, "#auto") == 0) {
        static char namebuf[32];
        sprintf(namebuf, "share%d", ++assocData->autoshare);
        sharename = namebuf;
    }

    share = map_file(filename, assocData->share_base, size, flags, creator);
    if (!share) {
        TclShmError(interp, filename);
        return TCL_ERROR;
    }

    if (share->name) { // pre-existing share
        creator = 0;
        new_share = 0;
    }

    if (creator) {
        shminitmap(share);
	//fprintf(stderr, "successfully created new shared-memory\n");
    } else {
        //fprintf(stderr, "validating the provisionally attached shared-memory\n");
        if (share->map->magic != MAP_MAGIC) {
	    Tcl_AppendResult(interp, "Not a valid share (bad magic): ", filename, NULL);
	    unmap_file(share);
	    return TCL_ERROR;
	}
	if (share->map->addr != share->share_base) {
            Tcl_AppendResult(interp, "Did not attach to expected memory base (%p): ", share->map->addr, filename, NULL);
	    unmap_file(share);
	    return TCL_ERROR;
	}

	// TODO: this is ugly, but we didn't find out the actual size until after we attached.  This needs to be consolidated with the share_base discovery when attaching.
	share->size = share->map->mapsize;

	//fprintf(stderr, "successfully attached to shared-memory\n");
    }

    // assocData->share_base = (char *)share + size;
#if 0
    if (assocData->share_base == (char *)-1)
        assocData->share_base = (char *)share + size;
    else if ((char *)share == assocData->share_base)
        assocData->share_base = assocData->share_base + size;
#endif

    if (new_share) {
        share->name = (char *) ckalloc(strlen(sharename)+1);
        strcpy(share->name, sharename);
    }

    if (sharePtr)
        *sharePtr = share;
    else
        Tcl_AppendResult(interp, share->name, NULL);

    return TCL_OK;
}

int doDetach(Tcl_Interp *interp, shm_t *share)
{
    if(share->objects) {
        return TCL_OK;
    }

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

    static CONST char *commands[] = {"create", "attach", "list", "detach", "names", "get", "multiget", "set", "info", "free", (char *)NULL};
    enum commands {CMD_CREATE, CMD_ATTACH, CMD_LIST, CMD_DETACH, CMD_NAMES, CMD_GET, CMD_MULTIGET, CMD_SET, CMD_INFO, CMD_FREE };

    static CONST struct {
        int need_share;         // if a missing share is an error
        int nargs;              // >0 number args, <0 -minimum number
        const char *args;             // String for Tcl_WrongNumArgs
    } cmdtemplate[] = {
        {0, -5, "filename size ?flags?"},  // CMD_CREATE
        {0,  4, "filename"}, // CMD_ATTACH
        {0, -2, "?share?"}, // CMD_LIST
        {1,  3, ""}, // CMD_DETACH
        {1, -3, "names"},  // CMD_NAMES
        {1, 4, "name"}, // CMD_GET
        {1, -4, "name ?name?..."}, // CMD_MULTIGET
        {1, -5, "name value ?name value?..."}, // CMD_SET
        {1,  3, ""}, // CMD_INFO
        {1,  -3, "?quick?"} // CMD_FREE
    };

    if (Tcl_GetIndexFromObj (interp, objv[1], commands, "command", TCL_EXACT, &cmdIndex) != TCL_OK) {
        return TCL_ERROR;
    }

    if(
        (cmdtemplate[cmdIndex].nargs > 0 && objc != cmdtemplate[cmdIndex].nargs) ||
        (cmdtemplate[cmdIndex].nargs < 0 && objc < -cmdtemplate[cmdIndex].nargs)
    ) {
        int nargs = abs(cmdtemplate[cmdIndex].nargs);
        Tcl_WrongNumArgs (interp, (nargs > 3 ? nargs : 3), objv, cmdtemplate[cmdIndex].args);
        return TCL_ERROR;
    }

    // Find the share option now. It's not necessarily an error (yet) if it doesn't exist (in fact for
    // the create/attach option it's an error if it DOES exist).
    if(objc > 2) {
        sharename = Tcl_GetString(objv[2]);

        share = assocData->share_list;
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

    if(cmdtemplate[cmdIndex].need_share) {
        if(!share) {
            Tcl_AppendResult(interp, "No such share: ", sharename, NULL);
            return TCL_ERROR;
        }
    }

    switch (cmdIndex) {

        case CMD_CREATE: {
            char      *filename;
            size_t     size;
            int        flags = 0;

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
                Tcl_WrongNumArgs (interp, 3, objv, cmdtemplate[cmdIndex].args);
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
                share = assocData->share_list;
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

#ifdef WITH_SHMEM_SYMBOL_LIST
        // Return a list of names
        case CMD_NAMES: {
            if (objc == 3) { // No args, all names
                volatile symbol_t *sym = share->map->namelist;
                while(sym) {
		  Tcl_AppendElement(interp, (char *)(sym->name));
                    sym = sym->next;
                }
            } else { // Otherwise, just the names defined here
                for (int i = 3; i < objc; i++) {
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
            for (int i = 3; i < objc; i++) {
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

            if (!share->creator) {
                Tcl_AppendResult(interp, "Can not write to ",sharename,": Permission denied", NULL);
                return TCL_ERROR;
            }
            if (!(objc & 1)) {
                Tcl_AppendResult(interp, "Odd number of elements in name-value list.",NULL);
                return TCL_ERROR;
            }

            for (int i = 3; i < objc; i += 2) {
                char *name = Tcl_GetString(objv[i]);
                if(get_symbol(share, name, SYM_TYPE_ANY)) {
                    set_symbol(share, name, Tcl_GetString(objv[i+1]), SYM_TYPE_STRING);
		} else {
                    add_symbol(share, name, Tcl_GetString(objv[i+1]), SYM_TYPE_STRING);
		}
            }
            return TCL_OK;
        }
#endif // WITH_SHMEM_SYMBOL_LIST

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

// vim: set ts=8 sw=4 sts=4 noet :
