/*
 * $Id$
 */

// Atomic word size, "cell_t".
typedef uint32_t cell_t;
#define CELLSIZE (sizeof (cell_t))

// Marker for the beginning of the list
#define MAP_MAGIC (((((('B' << 8) | 'O') << 8) | 'F') << 8) | 'H')
#define TRUE 1
#define FALSE 0

// TUNING

// How big a buffer of nulls to use when zeroing a file
#define NULBUFSIZE (1024L * 1024L)

// allocate a new reader block every READERS_PER_BLOCK readers
#define READERS_PER_BLOCK 64

// How many unfree entries to allocate at a time.
#define UN_POOL_SIZE 1024

// shared memory that is no longer needed but can't be freed until the
// last reader that was "live" when it was in use has released it
typedef struct _unfreeblock {
    struct _unfreeblock	*next;
    cell_t	         cycle;		// read cycle it's waiting on
    char		*block;		// address of block in shared mem
} unfreeblock;

// Pool control block
//
// Pools have much lower overhead for small blocks, because you don't need
// a freelist and you don't need to merge blocks
typedef struct _pool {
    struct _pool	*next;		// next pool
    char		*start;		// start of pool
    int			 blocks;	// number of elements in pool
    int		 	 blocksize;	// size of each pool element
    int		 	 avail;		// number of chunks unallocated
    char		*brk;		// start of never-allocated space
    char		*freelist;      // first freed element
} pool;
// Reader control block, containing READERS_PER_BLOCK reader records
// When a reader subscribes, it's handed the offset of its record
typedef struct _rblock {
    struct _rblock 	*next;		// offset of next reader block
    cell_t             count;		// number of live readers in block
    struct {
        cell_t     pid;		// process ID of reader (or 0 if free)
        cell_t     cycle;		// write cycle if currently reading
    } readers[READERS_PER_BLOCK];
} reader_block;

// mapinfo->map points to this structure, at the front of the mapped file.
typedef struct _mapheader {
    cell_t         magic;		// Magic number, "initialised"
    cell_t         headersize;	// Size of this header
    cell_t         mapsize;		// Size of this map
    char	    *addr;		// Address mapped to
    cell_t         write_lock;
    cell_t         cycle;		// incremented every write
    reader_block     readers;		// advisory locks for readers
} mapheader;

// Freelist entry
typedef struct _freeblock {
    struct _freeblock   *next;
    struct _freeblock   *prev;
} freeblock;

// Freelist control block
typedef struct _freelist {
    pool		*pools;
    freeblock		*list;
} freelist;

typedef struct _mapinfo {
    struct _mapinfo	*next;
    mapheader		*map;
    size_t		 size;
    int			 fd;
    freelist		*free;
    unfreeblock		*unfree;
    pool		*unfreepool;
} mapinfo;

int open_new(char *file, size_t size);
mapinfo *map_file(char *file, char *addr, size_t default_size);
int unmap_file(mapheader *map);
void shminitmap(mapinfo *mapinfo);
pool *initpool(char *memory, size_t blocksize, int blocks);
pool *ckallocpool(size_t blocksize, int blocks);
int shmaddpool(mapinfo *map, size_t blocksize, int blocks);
char *palloc(pool *pool, size_t size);
char *_shmalloc(mapinfo *map, size_t size);
char *shmalloc(mapinfo *map, size_t size);
void shmfree(mapinfo *map, char *block);
int shmdepool(mapinfo *mapinfo, char *block);
void setfree(cell_t *block, size_t size, int is_free);
int shmdealloc(mapinfo *mapinfo, char *data);

// shift between the data inside a variable sized block, and the block itself
#define data2block(data) (&((cell_t *)data)[-1])
#define block2data(block) ((char *)&(block)[1])

#define prevsize(block) ((block)[-1])
#define nextblock(block) ((cell_t *)(((char *)block) + abs(*(block))))
#define nextsize(block) (*nextblock(block))
#define prevblock(block) ((cell_t *)(((char *)block) - abs(prevsize(block))))

