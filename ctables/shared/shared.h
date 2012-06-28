/*
 * $Id$
 */

#ifndef SHM_SHARED_H
#define SHM_SHARED_H

// debug
// #define SHM_DEBUG_TRACE
// #define SHARED_GUARD
// #define SHARED_LOG "/var/tmp/speedtable_shared_log.txt"

#ifdef SHM_DEBUG_TRACE
#define IFDEBUG(x) x				/* Debug code included*/
#ifdef SHM_DEBUG_TRACE_FILE
FILE *SHM_DEBUG_FP;
#else
#define SHM_DEBUG_FP stderr
#endif
#else
#define IFDEBUG(x)				/* Debug code elided */
#endif

#define compile_time_assert(cond, msg)  char msg[(cond) ? 1 : 0]

#include <limits.h>
#include <stddef.h>

// Atomic word size, "cell_t".
#if (LONG_MAX == 4294967296L) /* 32 bit long */
typedef size_t cell_t;
#define cellabs(t) abs(t)
compile_time_assert(sizeof(size_t) == sizeof(int), SIZE_T_should_be_int);
compile_time_assert(sizeof(size_t) == 4, SIZE_T_should_be_32_bits);
#else /* 64 bit long */
typedef size_t cell_t;
#define cellabs(t) llabs(t)
compile_time_assert(sizeof(size_t) == sizeof(long long), SIZE_T_should_be_int);
compile_time_assert(sizeof(size_t) == 8, SIZE_T_should_be_32_bits);
#endif

#define CELLSIZE (sizeof (cell_t))

// Marker for the beginning of the list
#define MAP_MAGIC (((((('B' << 8) | 'O') << 8) | 'F') << 8) | 'H')
#define CHUNK_MAGIC (((((('C' << 8) | 'h') << 8) | 'n') << 8) | 'K')
#define POOL_MAGIC (((((('P' << 8) | 'o') << 8) | 'o') << 8) | 'L')
#define FREE_MAGIC (((((('F' << 8) | 'r') << 8) | 'e') << 8) | 'E')
#define BUSY_MAGIC (((((('B' << 8) | 'u') << 8) | 's') << 8) | 'Y')
#define SENTINAL_MAGIC (((((('S' << 8) | 'n') << 8) | 't') << 8) | 'L')

// Booleans
#define TRUE 1
#define FALSE 0

// If defining a TCL extension, using TCL
#ifdef SHARED_TCL_EXTENSION
# ifndef WITH_TCL
#  define WITH_TCL
# endif
#endif

// TUNING

// How big a buffer of nulls to use when zeroing a file
#define NULBUFSIZE (1024L * 1024L)

// allocate a new reader block every READERS_PER_BLOCK readers
#define READERS_PER_BLOCK 64

// How many garbage entries to allocate at a time.
#define GARBAGE_POOL_SIZE 1024

// How long to leave garbage uncollected after it falls below the horizon
// (measured in lock cycles)
//#define TWILIGHT_ZONE 1024
#define TWILIGHT_ZONE 64

// How often to check for GC (1 in every LAZY_GC write cycles
#define LAZY_GC 10

// Sentinel for a reader that isn't holding any garbage
#define LOST_HORIZON 0

// internal errors
int shared_errno;
char *shared_errmsg[];
enum shared_error_e {
	SH_ERROR_0,
	SH_NEW_FILE,
	SH_PRIVATE_MEMORY,
	SH_MAP_FILE,
	SH_OPEN_FILE,
	SH_NO_MAP,
	SH_ALREADY_MAPPED,
	SH_TOO_SMALL,
	SH_MAP_FULL,
	SH_ADDRESS_MISMATCH,
};
void shared_perror(char *text);

// shared memory that is no longer needed but can't be freed until the
// last reader that was "live" when it was in use has released it
typedef struct _garbage {
    struct _garbage	*next;
    cell_t	         cycle;		// read cycle it's waiting on
    char		*memory;	// address of block in shared mem
					// (free memory pointer, not raw block pointer)
} garbage;

// Pool control block
//
// Pools have much lower overhead for small blocks, because you don't need
// to merge blocks
struct _shm_t;		// forward

typedef struct _pool_freelist_t {
    struct _pool_freelist_t *next;
} pool_freelist_t;

typedef struct _chunk_t {
    cell_t              magic;          // magic number (CHUNK_MAGIC)
    struct _chunk_t	*next;		// next pool chunk
    char		*start;		// start of pool shared memory
    int		 	 avail;		// number of elements unallocated
    char		*brk;		// start of unallocated space
} chunk_t;

// Pool header block
//
typedef struct _poolhead_t {
    cell_t               magic;         // magic number (POOL_MAGIC)
    struct _poolhead_t	*next;
    struct _chunk_t	*chunks;
    struct _shm_t	*share;
    int			 nblocks;
    int			 blocksize;
    int			 numchunks;
    int			 maxchunks;
    pool_freelist_t	*freelist;
} poolhead_t;

// Symbol table, to pass addresses of internal structures to readers
typedef struct _symbol {
    volatile struct _symbol *next;
    volatile char	    *addr;
    int			     type;
    char		     name[];
} symbol;

// Reader control block, containing READERS_PER_BLOCK reader records
typedef struct _reader {
    cell_t		 pid;
    cell_t		 cycle;
} reader;

typedef struct _rblock {
    struct _rblock 	*next;		// offset of next reader block
    cell_t		 count;		// number of live readers in block
    reader		 readers[READERS_PER_BLOCK];
} reader_block;

// shm_t->map points to this structure, at the front of the mapped file.
typedef struct _mapheader {
    cell_t           magic;		// Magic number, "initialised" (MAP_MAGIC)
    cell_t           headersize;	// Size of this header
    cell_t           mapsize;		// Size of this map
    char	    *addr;		// Address mapped to
    volatile symbol *namelist;		// Internal symbol table
    cell_t           cycle;		// incremented every write
    reader_block    *readers;		// advisory locks for readers
} mapheader;

// Freelist entry
typedef struct _freeblock {
    cell_t                        magic;   // Magic number (FREE_MAGIC)
    ssize_t			  size;    // always a positive number for free blocks.
    volatile struct _freeblock   *next;
    volatile struct _freeblock   *prev;
} freeblock;

// Busy block
typedef struct {
    cell_t                        magic;    // Magic number (BUSY_MAGIC)
    ssize_t			  size;     // always a negative number for busy blocks.
    char			  data[];
} busyblock;

// Object in shared memory for the object list.
// File is unmapped when the last object used by this process is released
//
// Every object has a name in the shared memory symbol table.
typedef struct _object_t {
    struct _object_t  *next;
    char               name[];
} object_t;

typedef struct _shm_t {
    struct _shm_t	*next;
    volatile mapheader	*map;
    size_t		 size;
    int			 flags;
    int			 fd;
    int                  creator;
    char	        *name;
    char		*filename;
    int                  attach_count;
    object_t		*objects;
// server-only fields:
    poolhead_t		*pools;
    volatile freeblock	*freelist;
    size_t		 free_space;
    garbage		*garbage;
    poolhead_t		*garbage_pool;
    cell_t		 horizon;
// client-only fields:
    volatile reader	*self;
} shm_t;

int open_new(char *file, size_t size);
shm_t *map_file(char *file, char *addr, size_t default_size, int flags, int create);
int unmap_file(shm_t *shm);
void shminitmap(shm_t *shm);
int shmcheckmap(volatile mapheader *map);
poolhead_t *makepool(size_t blocksize, int nblocks, int maxchunks, shm_t *share);
int shmaddpool(shm_t *shm, size_t blocksize, int nblocks, int maxchunks);
char *palloc(poolhead_t *head, size_t size);
void freepools(poolhead_t *head, int also_free_shared);
void remove_from_freelist(shm_t *shm, volatile freeblock *block);
void insert_in_freelist(shm_t *shm, volatile freeblock *block);
char *_shmalloc(shm_t *map, size_t size);
char *shmalloc_raw(shm_t *map, size_t size);
void shmfree_raw(shm_t *map, char *block);
int shmdepool(poolhead_t *head, char *block);
void setfree(volatile freeblock *block, size_t size, int is_free);
int shmdealloc_raw(shm_t *shm, char *data);
int write_lock(shm_t *shm);
void write_unlock(shm_t *shm);
volatile reader *pid2reader(volatile mapheader *map, int pid);
int read_lock(shm_t *shm);
void read_unlock(shm_t *shm);
void garbage_collect(shm_t *shm);
cell_t oldest_reader_cycle(shm_t *shm);
void shmpanic(char *message);
int add_symbol(shm_t *shm, char *name, char *value, int type);
int set_symbol(shm_t *shm, char *name, char *value, int type);
char *get_symbol(shm_t *shm, char *name, int wanted);
int shmattachpid(shm_t *info, int pid);
int use_name(shm_t *share, char *symbol);
void release_name(shm_t *share, char *symbol);
int parse_size(char *s, size_t *ptr);
int parse_flags(char *s);
char *flags2string(int flags);
size_t shmfreemem(shm_t *shm, int check);

#define SYM_TYPE_STRING 1
#define SYM_TYPE_DATA 0
#define SYM_TYPE_ANY -1

#ifdef WITH_TCL
#define ATTACH_ONLY ((size_t)-1)

void setShareBase(char *new_base);
int TclGetSizeFromObj(Tcl_Interp *interp, Tcl_Obj *obj, size_t *ptr);
void TclShmError(Tcl_Interp *interp, char *name);
int doCreateOrAttach(Tcl_Interp *interp, char *sharename, char *filename, size_t size, int flags, shm_t **sharePtr);
int doDetach(Tcl_Interp *interp, shm_t *share);
int shareCmd (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[]);
#endif

// shift between the data inside a variable sized block, and the block itself
#define data2block(dataptr) ((freeblock *)( ((char *)(dataptr)) - offsetof(busyblock, data)) )
#define block2data(block) (((busyblock *)(block))->data)

#define prevsize(block) (((ssize_t *)block)[-1])
#define nextblock(block) ((freeblock *)(((char *)block) + cellabs( (ssize_t) ((freeblock*)(block))->size)) )
#define nextsize(block) (nextblock(block)->size)
#define prevblock(block) ((freeblock *)(((char *)block) - cellabs( (ssize_t) prevsize(block))) )

#define is_prev_sentinal(block) (prevsize(block) == SENTINAL_MAGIC)
#define is_next_sentinal(block) (*((cell_t*)nextblock(block)) == SENTINAL_MAGIC)



#endif

#ifdef SHARED_GUARD
# define GUARD_SIZE 8
# ifdef SHARED_LOG
#  define shmalloc(m,s) shmalloc_guard(m,s,__FILE__,__LINE__)
#  define shmfree(m,a) shmfree_guard(m,a,__FILE__,__LINE__)
#  define shmdealloc(m,a) shmdealloc_guard(m,a,__FILE__,__LINE__)
#  define LOGPARAMS , char *File, int Line
# else
#  define shmalloc shmalloc_guard
#  define shmfree shmfree_guard
#  define shmdealloc shmdealloc_guard
#  define LOGPARAMS
# endif
  char *shmalloc_guard(shm_t *map, size_t size LOGPARAMS);
  void shmfree_guard(shm_t *map, char *block LOGPARAMS);
  int shmdealloc_guard(shm_t *shm, char *data LOGPARAMS);
#else
# define shmalloc shmalloc_raw
# define shmfree shmfree_raw
# define shmdealloc shmdealloc_raw
#endif
