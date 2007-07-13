/*
 * $Id$
 */

#define MAP_MAGIC (((((('B' << 8) | 'O') << 8) | 'F') << 8) | 'H')
#define NULBUFSIZE (1024L * 1024L)
#define TRUE 1
#define FALSE 0
#define READERS_PER_BLOCK 64

// shared memory that is no longer needed but can't be freed until the
// last reader that was "live" when it was in use has released it
typedef struct _unfreelist {
    struct _unfreelist	*next;
    uint32_t	         cycle;		// read cycle it's waiting on
    char		*block;		// address of block in shared mem
} unfreelist;

// Pool control block
typedef struct _pool {
    struct _pool	*next;		// next pool
    char		*start;		// start of pool
    int			 blocks;	// end of pool (pointer past end)
    int		 	 blocksize;	// size of each pool element
    int		 	 avail;		// number of chunks unallocated
    char		*brk;		// start of never-allocated space
    char		*freelist;      // first freed element
} pool;
// Reader control block, containing READERS_PER_BLOCK reader records
// When a reader subscribes, it's handed the offset of its record
typedef struct _rblock {
    struct _rblock 	*next;		// offset of next reader block
    uint32_t             count;		// number of live readers in block
    struct {
        uint32_t     pid;		// process ID of reader (or 0 if free)
        uint32_t     cycle;		// write cycle if currently reading
    } readers[READERS_PER_BLOCK];
} reader_block;

// mapinfo->map points to this structure, at the front of the mapped file.
typedef struct _mapheader {
    uint32_t         magic;		// Magic number, "initialised"
    uint32_t         headersize;	// Size of this header
    uint32_t         mapsize;		// Size of this map
    char	    *addr;		// Address mapped to
    uint32_t         write_lock;
    uint32_t         cycle;		// incremented every write
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
    unfreelist		*unfree;
    pool		*unfreepool;
} mapinfo;

int open_new(char *file, size_t size);
mapinfo *map_file(char *file, char *addr, size_t default_size);
int unmap_file(mapheader *map);
void shminitmap(volatile mapinfo *mapinfo);
pool *makepool(char *memory, size_t blocksize, int blocks);
int shmaddpool(mapinfo *map, size_t blocksize, int blocks);
char *palloc(pool *pool);
char *_shmalloc(mapinfo *map, size_t size);
char *shmalloc(mapinfo *map, size_t size);
void shmfree(mapinfo *map, char *block);
int shmdepool(mapinfo *mapinfo, char *block);
void setfree(uint32_t *block, size_t size, int is_free);
int shmdealloc(mapinfo *mapinfo, uint32_t *block);

#define free2block(free) (&((uint32_t *)free)[-1])
#define block2free(block) ((freeblock *)&(block)[1])

#define prevsize(block) ((block)[-1])
#define nextblock(block) ((uint32_t *)(((char *)block) + abs(*(block))))
#define nextsize(block) (*nextblock(block))
#define prevblock(block) ((uint32_t *)(((char *)block) - abs(prevsize(block))))

