/*
 * $Id$
 */

#define NULBUFSIZE (1024L * 1024L)

// shared memory that is no longer needed but can't be freed until the
// last reader that was "live" when it was in use has released it
typedef struct _unfree {
    struct _unfree  *next;
    uint32_t         cycle;		// read cycle it's waiting on
    uint32_t         offset;            // offset of block in shared mem
} unfree;
    
typedef struct _mapinfo {
    struct _mapinfo *next;
    char	    *map;
    size_t	     size;
    int		     fd;
} mapinfo;

// Pool control block, containing POOLS_PER_BLOCK pool records
typedef struct _pool_block {
    uint32_t         next;		// offset of next pools list (if any)
    uint32_t         count;		// number of allocated pools in block
    struct {
	uint32_t     start;		// offset of the start of the pool
	uint32_t     end;
	uint32_t     size;              // size of each pool chunk
        uint32_t     avail;		// number of chunks unallocated
        uint32_t     brk;		// start of never-allocated space
	uint32_t     free;	        // first freed element
    } pools[POOLS_PER_BLOCK];
} pool_block;

// Reader control block, containing READERS_PER_BLOCK reader records
// When a reader subscribes, it's handed the offset of its block
typedef struct _reader_block {
    uint32_t         next;		// offset of next reader block
    uint32_t         count;		// number of live readers in block
    struct {
        uint32_t     pid;		// process ID of reader
        uint32_t     cycle;		// write cycle if current read
    } readers[READERS_PER_BLOCK];
} reader_block;

// mapinfo.map points to this structure, at the front of the mapped file.
typedef struct _mapheader {
    uint32_t         magic;		// Magic number, "initialised"
    uint32_t         size;		// Size of this map
    uint32_t         free_list;		// offset of first arbitrary free list
    pool_block       pools;		// First POOLS_PER_BLOCK pools
    uint32_t         write_lock;
    uint32_t         cycle;		// increamented every write, copied
					// into "readers" by readers
    reader_block     readers;
} mapheader;

