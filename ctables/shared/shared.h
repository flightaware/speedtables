/*
 * $Id$
 */

#ifndef SHM_SHARED_H
#define SHM_SHARED_H

#include <limits.h>
#include <stddef.h>
#include <boost/static_assert.hpp>
#include <boost/interprocess/managed_mapped_file.hpp>
#include <boost/interprocess/containers/vector.hpp>
#include <boost/interprocess/allocators/allocator.hpp>
#include <boost/container/deque.hpp>
using namespace boost::interprocess;
using namespace boost::container;


#define WITH_SHMEM_SYMBOL_LIST



// Atomic word size, "cell_t".
#if (LONG_MAX == 4294967296L) /* 32 bit long */
  typedef size_t cell_t;
  #define cellabs(t) abs(t)
  BOOST_STATIC_ASSERT_MSG(sizeof(size_t) == sizeof(int), "SIZE_T_should_be_int");
  BOOST_STATIC_ASSERT_MSG(sizeof(size_t) == 4, "SIZE_T_should_be_32_bits");
#else /* 64 bit long */
  typedef size_t cell_t;
  #define cellabs(t) llabs(t)
  BOOST_STATIC_ASSERT_MSG(sizeof(size_t) == sizeof(long long), "SIZE_T_should_be_long_long");
  BOOST_STATIC_ASSERT_MSG(sizeof(size_t) == 8, "SIZE_T_should_be_64_bits");
#endif

#define CELLSIZE (sizeof (cell_t))


// If defining a TCL extension, using TCL
#if defined(SHARED_TCL_EXTENSION) && !defined(WITH_TCL)
#  define WITH_TCL
#endif

#ifndef WITH_TCL
#define CONST const
#endif

// TUNING

// Maximum number of readers
#define MAX_SHMEM_READERS 1024


// How long to leave garbage uncollected after it falls below the horizon
// (measured in lock cycles)
//#define TWILIGHT_ZONE 1024
#define TWILIGHT_ZONE 64

// How often to check for GC (1 in every LAZY_GC write cycles)
#define LAZY_GC 1000

// Sentinel for a reader that isn't holding any garbage
#define LOST_HORIZON 0


// Marker for the beginning of the list
#define MAP_MAGIC (((((('B' << 8) | 'E') << 8) | 'E') << 8) | 'F')


// shared memory that is no longer needed but can't be freed until the
// last reader that was "live" when it was in use has released it
struct garbage_t {
    cell_t	         cycle;		// read cycle it's waiting on
    char		*memory;	// address of block in shared mem
					// (free memory pointer, not raw block pointer)
};


#ifdef WITH_SHMEM_SYMBOL_LIST
// Symbol table, to pass addresses of internal structures to readers
struct symbol_t {
    volatile symbol_t       *next;
    volatile char	    *addr;
    int			     type;
    char		     name[];
};
#else
typedef void symbol_t;
#endif


// Reader control block.
struct reader_t {
    cell_t		 pid;
    cell_t		 cycle;
};

// shm_t->map points to this structure, at the front of the mapped file.
struct mapheader_t {
    cell_t           magic;		// Magic number, "initialised" (MAP_MAGIC)
    cell_t           headersize;	// Size of this header
    cell_t           mapsize;		// Size of this map (not really used anymore)
    char	    *addr;		// Address mapped to (not really used anymore)
    volatile symbol_t *namelist;		// Internal symbol table
    cell_t           cycle;		// incremented every write
    reader_t    readers[MAX_SHMEM_READERS];	// advisory locks for readers
};


// Object in shared memory for the object list.
// File is unmapped when the last object used by this process is released
//
// Every object has a name in the shared memory symbol table.
struct object_t {
    object_t          *next;
    char               name[];
};

struct shm_t {
    shm_t	*next;

    managed_mapped_file *managed_shm;
    volatile mapheader_t *map;                 // points within shmem.
    char                 *share_base;           // points to front of shmem.
    size_t		 size;
    int			 flags;
    int			 fd;
    int                  creator;
    char	        *name;
    char		*filename;
    int                  attach_count;
    object_t		*objects;

// (master) server-only fields:
    deque<garbage_t>	*garbage;
    cell_t		 horizon;

// (reader) client-only fields:
    volatile reader_t	*self;        // points into shmem       
};


shm_t *map_file(const char *file, char *addr, size_t default_size, int flags, int create);
int unmap_file(shm_t *shm);
void shminitmap(shm_t *shm);
void *_shmalloc(shm_t *map, size_t size);
void *shmalloc_raw(shm_t *map, size_t size);
void shmfree_raw(shm_t *map, void *block);
int shmdealloc_raw(shm_t *shm, void *data);
int write_lock(shm_t *shm);
void write_unlock(shm_t *shm);
volatile reader_t *pid2reader(volatile mapheader_t *map, int pid);
int read_lock(shm_t *shm);
void read_unlock(shm_t *shm);
void garbage_collect(shm_t *shm);
cell_t oldest_reader_cycle(shm_t *shm);
void shared_perror(const char *text);
void shmpanic(const char *message);
#ifdef WITH_SHMEM_SYMBOL_LIST
int add_symbol(shm_t *shm, CONST char *name, char *value, int type);
int set_symbol(shm_t *shm, CONST char *name, char *value, int type);
char *get_symbol(shm_t *shm, CONST char *name, int wanted);
#endif
int use_name(shm_t *share, const char *symbol);
void release_name(shm_t *share, const char *symbol);
int shmattachpid(shm_t *info, int pid);
int parse_size(const char *s, size_t *ptr);
int parse_flags(const char *s);
const char *flags2string(int flags);
size_t shmfreemem(shm_t *shm, int check);
const char *get_last_shmem_error();

#define SYM_TYPE_STRING 1
#define SYM_TYPE_DATA 0
#define SYM_TYPE_ANY -1

#ifdef WITH_TCL
#define ATTACH_ONLY ((size_t)-1)

int Shared_Init(Tcl_Interp *interp);
void setShareBase(char *new_base);
int TclGetSizeFromObj(Tcl_Interp *interp, Tcl_Obj *obj, size_t *ptr);
void TclShmError(Tcl_Interp *interp, const char *name);
int doCreateOrAttach(Tcl_Interp *interp, const char *sharename, const char *filename, size_t size, int flags, shm_t **sharePtr);
int doDetach(Tcl_Interp *interp, shm_t *share);
int shareCmd (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[]);
#endif


# define shmalloc shmalloc_raw
# define shmfree shmfree_raw
# define shmdealloc shmdealloc_raw



#endif

