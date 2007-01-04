/*
 * speedtables.h --
 *
 *	Based on hash tables from Tcl.
 *
 * Copyright (c) 1987-1994 The Regents of the University of California.
 * Copyright (c) 1993-1996 Lucent Technologies.
 * Copyright (c) 1994-1998 Sun Microsystems, Inc.
 * Copyright (c) 1998-2000 by Scriptics Corporation.
 * Copyright (c) 2002 by Kevin B. Kenny.  All rights reserved.
 *
 * See the file "license.terms" for information on usage and redistribution of
 * this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS: @(#) $Id$
 */

#ifndef _SPEEDTABLES_H
#define _SPEEDTABLES_H

/*
 * Forward declarations of ctable_HashTable and related types.
 */

typedef struct ctable_HashKeyType ctable_HashKeyType;
typedef struct ctable_HashTable ctable_HashTable;
typedef struct ctable_HashEntry ctable_HashEntry;

typedef unsigned int (ctable_HashKeyProc) _ANSI_ARGS_((ctable_HashTable *tablePtr,
	VOID *keyPtr));
typedef int (ctable_CompareHashKeysProc) _ANSI_ARGS_((VOID *keyPtr,
	ctable_HashEntry *hPtr));
typedef ctable_HashEntry *(ctable_AllocHashEntryProc) _ANSI_ARGS_((
	ctable_HashTable *tablePtr, VOID *keyPtr));
typedef void (ctable_FreeHashEntryProc) _ANSI_ARGS_((ctable_HashEntry *hPtr));

/*
 * Structure definition for an entry in a hash table. No-one outside Tcl
 * should access any of these fields directly; use the macros defined below.
 */

struct ctable_HashEntry {
    ctable_HashEntry *nextPtr;	/* Pointer to next entry in this hash bucket,
				 * or NULL for end of chain. */
    ctable_HashTable *tablePtr;	/* Pointer to table containing entry. */
    unsigned int hash;		/* Hash value. */
    ClientData clientData;	/* Application stores something here with
				 * ctable_SetHashValue. */
    union {			/* Key has one of these forms: */
	char *oneWordValue;	/* One-word value for key. */
	ctable_Obj *objPtr;	/* ctable_Obj * key value. */
	int words[1];		/* Multiple integer words for key. The actual
				 * size will be as large as necessary for this
				 * table's keys. */
	char string[4];		/* String for key. The actual size will be as
				 * large as needed to hold the key. */
    } key;			/* MUST BE LAST FIELD IN RECORD!! */
};

/*
 * Flags used in ctable_HashKeyType.
 *
 * CTABLE_HASH_KEY_RANDOMIZE_HASH -
 *				There are some things, pointers for example
 *				which don't hash well because they do not use
 *				the lower bits. If this flag is set then the
 *				hash table will attempt to rectify this by
 *				randomising the bits and then using the upper
 *				N bits as the index into the table.
 * CTABLE_HASH_KEY_SYSTEM_HASH -	If this flag is set then all memory internally
 *                              allocated for the hash table that is not for an
 *                              entry will use the system heap.
 */

#define CTABLE_HASH_KEY_RANDOMIZE_HASH 0x1
#define CTABLE_HASH_KEY_SYSTEM_HASH    0x2

/*
 * Structure definition for the methods associated with a hash table key type.
 */

#define CTABLE_HASH_KEY_TYPE_VERSION 1
struct ctable_HashKeyType {
    int version;		/* Version of the table. If this structure is
				 * extended in future then the version can be
				 * used to distinguish between different
				 * structures. */
    int flags;			/* Flags, see above for details. */
    ctable_HashKeyProc *hashKeyProc;
				/* Calculates a hash value for the key. If
				 * this is NULL then the pointer itself is
				 * used as a hash value. */
    ctable_CompareHashKeysProc *compareKeysProc;
				/* Compares two keys and returns zero if they
				 * do not match, and non-zero if they do. If
				 * this is NULL then the pointers are
				 * compared. */
    ctable_AllocHashEntryProc *allocEntryProc;
				/* Called to allocate memory for a new entry,
				 * i.e. if the key is a string then this could
				 * allocate a single block which contains
				 * enough space for both the entry and the
				 * string. Only the key field of the allocated
				 * ctable_HashEntry structure needs to be filled
				 * in. If something else needs to be done to
				 * the key, i.e. incrementing a reference
				 * count then that should be done by this
				 * function. If this is NULL then ctable_Alloc is
				 * used to allocate enough space for a
				 * ctable_HashEntry and the key pointer is
				 * assigned to key.oneWordValue. */
    ctable_FreeHashEntryProc *freeEntryProc;
				/* Called to free memory associated with an
				 * entry. If something else needs to be done
				 * to the key, i.e. decrementing a reference
				 * count then that should be done by this
				 * function. If this is NULL then ctable_Free is
				 * used to free the ctable_HashEntry. */
};

/*
 * Structure definition for a hash table.  Must be in speedtables.h so clients 
 * can allocate space for these structures, but clients should never access any
 * fields in this structure.
 */

#define CTABLE_SMALL_HASH_TABLE 4
struct ctable_HashTable {
    ctable_HashEntry **buckets;	/* Pointer to bucket array. Each element
				 * points to first entry in bucket's hash
				 * chain, or NULL. */
    ctable_HashEntry *staticBuckets[CTABLE_SMALL_HASH_TABLE];
				/* Bucket array used for small tables (to
				 * avoid mallocs and frees). */
    int numBuckets;		/* Total number of buckets allocated at
				 * **bucketPtr. */
    int numEntries;		/* Total number of entries present in
				 * table. */
    int rebuildSize;		/* Enlarge table when numEntries gets to be
				 * this large. */
    int downShift;		/* Shift count used in hashing function.
				 * Designed to use high-order bits of
				 * randomized keys. */
    int mask;			/* Mask value used in hashing function. */
    int keyType;		/* Type of keys used in this table. It's
				 * either CTABLE_CUSTOM_KEYS, CTABLE_STRING_KEYS,
				 * CTABLE_ONE_WORD_KEYS, or an integer giving the
				 * number of ints that is the size of the
				 * key. */
    ctable_HashKeyType *typePtr;	/* Type of the keys used in the
				 * ctable_HashTable. */
};

/*
 * Structure definition for information used to keep track of searches through
 * hash tables:
 */

typedef struct ctable_HashSearch {
    ctable_HashTable *tablePtr;	/* Table being searched. */
    int nextIndex;		/* Index of next bucket to be enumerated after
				 * present one. */
    ctable_HashEntry *nextEntryPtr;/* Next entry to be enumerated in the current
				 * bucket. */
} ctable_HashSearch;

/*
 * Acceptable key types for hash tables:
 *
 * CTABLE_STRING_KEYS:		The keys are strings, they are copied into the
 *				entry.
 * CTABLE_ONE_WORD_KEYS:		The keys are pointers, the pointer is stored
 *				in the entry.
 * CTABLE_CUSTOM_TYPE_KEYS:	The keys are arbitrary types which are copied
 *				into the entry.
 * CTABLE_CUSTOM_PTR_KEYS:		The keys are pointers to arbitrary types, the
 *				pointer is stored in the entry.
 *
 * While maintaining binary compatability the above have to be distinct values
 * as they are used to differentiate between old versions of the hash table
 * which don't have a typePtr and new ones which do. Once binary compatability
 * is discarded in favour of making more wide spread changes CTABLE_STRING_KEYS
 * can be the same as CTABLE_CUSTOM_TYPE_KEYS, and CTABLE_ONE_WORD_KEYS can be the
 * same as CTABLE_CUSTOM_PTR_KEYS because they simply determine how the key is
 * accessed from the entry and not the behaviour.
 */

#define CTABLE_STRING_KEYS	0
#define CTABLE_ONE_WORD_KEYS	1

#   define CTABLE_CUSTOM_TYPE_KEYS	CTABLE_STRING_KEYS
#   define CTABLE_CUSTOM_PTR_KEYS	CTABLE_ONE_WORD_KEYS

/*
 * Macros for clients to use to access fields of hash entries:
 */

#define ctable_GetHashValue(h) ((h)->clientData)
#define ctable_SetHashValue(h, value) ((h)->clientData = (ClientData) (value))
#   define ctable_GetHashKey(tablePtr, h) \
	((char *) (((tablePtr)->keyType == CTABLE_ONE_WORD_KEYS) \
		   ? (h)->key.oneWordValue \
		   : (h)->key.string))

/*
 * Macros to use for clients to use to invoke find and create functions for
 * hash tables:
 */

/*
 * Macro to use new extended version of ctable_InitHashTable.
 */
#   undef  ctable_InitHashTable
#   define ctable_InitHashTable(tablePtr, keyType) \
	ctable_InitHashTableEx((tablePtr), (keyType), NULL)
#   undef  ctable_FindHashEntry
#   define ctable_FindHashEntry(tablePtr, key) \
        ctable_CreateHashEntry((tablePtr), (key), NULL)


#endif /* _SPEEDTABLES_H */

/*
 * Local Variables:
 * mode: c
 * c-basic-offset: 4
 * fill-column: 78
 * End:
 */
