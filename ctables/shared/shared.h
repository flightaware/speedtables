/*
 * $Id$
 */

#define NULBUFSIZE (1024L * 1024L)

// shared memory that is no longer needed but can't be freed until the
// last reader that was "live" when it was in use has released it
typedef struct _unfreelist {
    struct _unfreelist	*next;
    struct {
	uint32_t	 cycle;		// read cycle it's waiting on
	char		*block;		// address of block in shared mem
    } blocks[UNFREE_CHUNK_SIZE];
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
    char		*map;
    size_t		 size;
    int			 fd;
    freelist		*free;
    unfreelist		*unfree;
} mapinfo;

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

