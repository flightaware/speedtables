// A stripped down ctable.h
#define WITH_SHARED_TABLES 1
#define VOID void

// Dummy out types we're not going to use
typedef void *Tcl_Command;
typedef void *ctable_CreatorTable;

// forward of me, I know
struct ctable_LinkedListNode;
struct ctable_BaseRow;

// snarfed from ctable.h
#define	CT_LIST_ENTRY(type)						\
struct {								\
	struct type *le_next;	/* next element */			\
	struct type **le_prev;	/* address of previous next element */	\
}

#include "../skiplists/jsw_slib.h"
#include "../hash/speedtables.h"

// define ctable linked lists structures et al
struct ctable_LinkedListNode {
    struct ctable_BaseRow *next;
    struct ctable_BaseRow **prev;
    struct ctable_BaseRow **head;
};

// This must start off as a copy of the start of the generated ctable
struct ctable_BaseRow {
    // hashEntry absolutely must be the first thing defined in the base row
    ctable_HashEntry     hashEntry;
#ifdef WITH_SHARED_TABLES
    cell_t		_row_cycle;
#endif
    // _ll_nodes absolutely must be the last thing defined in the base row
    ctable_LinkedListNode _ll_nodes[0];
};

// Share contains a struct CTable pointed to by "share_ctable" in the
// original ctable

struct CTable {
    ctable_CreatorTable                 *creator; // not shared
    ctable_HashTable                    *keyTablePtr; // not shared

    jsw_skip_t                         **skipLists; // shared
    ctable_BaseRow                      *ll_head; // shared

    int                                  autoRowNumber;
    int                                  destroying;
    int					 searching;
    char				*nullKeyValue;
#ifdef WITH_SHARED_TABLES
    int					 was_locked;
    const char				*emptyString;
    const char			       **defaultStrings;

    int					 share_type;
    int					 share_panic;
    char				*share_name;
    char				*share_file;
    shm_t                               *share;
    size_t				 share_min_free;
// reader-only
    volatile struct CTable		*share_ctable;
    volatile reader_t			*my_reader;
#endif
    int					 performanceCallbackEnable:1;
    char				*performanceCallback;
    double				 performanceCallbackThreshold;

    Tcl_Command                          commandInfo;
    long                                 count;
    CT_LIST_ENTRY(CTable)                   instance;
};

#ifdef WITH_SHARED_TABLES
# define CTABLE_SHARED_NONE 0
# define CTABLE_SHARED_MASTER 1
# define CTABLE_SHARED_READER 2
#endif


void dump_speedtable_info (struct CTable *t);
