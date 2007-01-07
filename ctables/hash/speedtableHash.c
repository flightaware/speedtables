/*
 * speedtableHash.c --
 *
 *	Ctables implementation of in-memory hash tables, adapted from Tcl
 *
 * Copyright (c) 1991-1993 The Regents of the University of California.
 * Copyright (c) 1994 Sun Microsystems, Inc.
 *
 * See the file "license.terms" for information on usage and redistribution of
 * this file, and for a DISCLAIMER OF ALL WARRANTIES.
 *
 * RCS: @(#) $Id$
 */

//#include "tclInt.h"
#include <tcl.h>

/*
 * When there are this many entries per bucket, on average, rebuild the hash
 * table to make it larger.
 */

#define REBUILD_MULTIPLIER	3

/*
 * The following macro takes a preliminary integer hash value and produces an
 * index into a hash tables bucket list. The idea is to make it so that
 * preliminary values that are arbitrarily similar will end up in different
 * buckets. The hash function was taken from a random-number generator.
 */

#define RANDOM_INDEX(tablePtr, i) \
    (((((long) (i))*1103515245) >> (tablePtr)->downShift) & (tablePtr)->mask)

/*
 * Prototypes for the array hash key methods.
 */

static ctable_HashEntry *	AllocArrayEntry(ctable_HashTable *tablePtr, VOID *keyPtr);
static int		CompareArrayKeys(VOID *keyPtr, ctable_HashEntry *hPtr);
static unsigned int	HashArrayKey(ctable_HashTable *tablePtr, VOID *keyPtr);

/*
 * Prototypes for the string hash key methods.
 */

static ctable_HashEntry *	AllocStringEntry(ctable_HashTable *tablePtr,
			    VOID *keyPtr);
static int		CompareStringKeys(VOID *keyPtr, ctable_HashEntry *hPtr);
static unsigned int	HashStringKey(ctable_HashTable *tablePtr, VOID *keyPtr);

/*
 * Function prototypes for static functions in this file:
 */

static void		RebuildTable(ctable_HashTable *tablePtr);

ctable_HashKeyType ctableArrayHashKeyType = {
    CTABLE_HASH_KEY_TYPE_VERSION,	/* version */
    CTABLE_HASH_KEY_RANDOMIZE_HASH,	/* flags */
    HashArrayKey,			/* hashKeyProc */
    CompareArrayKeys,			/* compareKeysProc */
    AllocArrayEntry,			/* allocEntryProc */
    NULL				/* freeEntryProc */
};

ctable_HashKeyType ctableOneWordHashKeyType = {
    CTABLE_HASH_KEY_TYPE_VERSION,	/* version */
    0,					/* flags */
    NULL, /* HashOneWordKey, */		/* hashProc */
    NULL, /* CompareOneWordKey, */	/* compareProc */
    NULL, /* AllocOneWordKey, */	/* allocEntryProc */
    NULL  /* FreeOneWordKey, */		/* freeEntryProc */
};

ctable_HashKeyType ctableStringHashKeyType = {
    CTABLE_HASH_KEY_TYPE_VERSION,	/* version */
    0,					/* flags */
    HashStringKey,			/* hashKeyProc */
    CompareStringKeys,			/* compareKeysProc */
    AllocStringEntry,			/* allocEntryProc */
    NULL				/* freeEntryProc */
};

/*
 *----------------------------------------------------------------------
 *
 * ctable_InitHashTable --
 *
 *	Given storage for a hash table, set up the fields to prepare the hash
 *	table for use.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	TablePtr is now ready to be passed to ctable_FindHashEntry and
 *	ctable_CreateHashEntry.
 *
 *----------------------------------------------------------------------
 */

#undef ctable_InitHashTable
void
ctable_InitHashTable(
    register ctable_HashTable *tablePtr,
				/* Pointer to table record, which is supplied
				 * by the caller. */
    int keyType)		/* Type of keys to use in table:
				 * CTABLE_STRING_KEYS, CTABLE_ONE_WORD_KEYS, 
				 * or an integer >= 2. */
{
    /*
     * Use a special value to inform the extended version that it must not
     * access any of the new fields in the ctable_HashTable. If an extension is
     * rebuilt then any calls to this function will be redirected to the
     * extended version by a macro.
     */

    ctable_InitCustomHashTable(tablePtr, keyType, (ctable_HashKeyType *) -1);
}

/*
 *----------------------------------------------------------------------
 *
 * ctable_InitCustomHashTable --
 *
 *	Given storage for a hash table, set up the fields to prepare the hash
 *	table for use. This is an extended version of ctable_InitHashTable which
 *	supports user defined keys.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	TablePtr is now ready to be passed to ctable_FindHashEntry and
 *	ctable_CreateHashEntry.
 *
 *----------------------------------------------------------------------
 */

void
ctable_InitCustomHashTable(
    register ctable_HashTable *tablePtr,
				/* Pointer to table record, which is supplied
				 * by the caller. */
    int keyType,		/* Type of keys to use in table:
				 * CTABLE_STRING_KEYS, CTABLE_ONE_WORD_KEYS,
				 * CTABLE_CUSTOM_TYPE_KEYS, 
				 * CTABLE_CUSTOM_PTR_KEYS,
				 * or an integer >= 2. */
    ctable_HashKeyType *typePtr) /* Pointer to structure which defines the
				 * behaviour of this table. */
{
    int i;

#if (CTABLE_SMALL_HASH_TABLE != 16)
    Tcl_Panic("ctable_InitCustomHashTable: CTABLE_SMALL_HASH_TABLE is %d, not 16",
	    CTABLE_SMALL_HASH_TABLE);
#endif

    tablePtr->buckets = tablePtr->staticBuckets;

    for (i = 0; i < CTABLE_SMALL_HASH_TABLE; i++) {
        tablePtr->staticBuckets[i] = 0;
    }

    tablePtr->numBuckets = CTABLE_SMALL_HASH_TABLE;
    tablePtr->numEntries = 0;
    tablePtr->rebuildSize = CTABLE_SMALL_HASH_TABLE*REBUILD_MULTIPLIER;
    tablePtr->downShift = 26;
    tablePtr->mask = 15;
    tablePtr->keyType = keyType;
    if (typePtr == NULL) {
	/*
	 * Use the key type to decide which key type is needed.
	 */

	if (keyType == CTABLE_STRING_KEYS) {
	    typePtr = &ctableStringHashKeyType;
	} else if (keyType == CTABLE_ONE_WORD_KEYS) {
	    typePtr = &ctableOneWordHashKeyType;
	} else if (keyType == CTABLE_CUSTOM_TYPE_KEYS) {
	    Tcl_Panic ("No type structure specified for CTABLE_CUSTOM_TYPE_KEYS");
	} else if (keyType == CTABLE_CUSTOM_PTR_KEYS) {
	    Tcl_Panic ("No type structure specified for CTABLE_CUSTOM_PTR_KEYS");
	} else {
	    typePtr = &ctableArrayHashKeyType;
	}
    } else if (typePtr == (ctable_HashKeyType *) -1) {
	/*
	 * If the caller has not been rebuilt then we cannot continue as the
	 * hash table is not an extended version.
	 */

	Tcl_Panic("Hash table is not compatible");
    }
    tablePtr->typePtr = typePtr;
}

/*
 *----------------------------------------------------------------------
 *
 * ctable_FindHashEntry --
 *
 *	Given a hash table find the entry with a matching key.
 *
 * Results:
 *	The return value is a token for the matching entry in the hash table,
 *	or NULL if there was no matching entry.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */
#if 0
ctable_HashEntry *
ctable_FindHashEntry(
    ctable_HashTable *tablePtr,	/* Table in which to lookup entry. */
    CONST char *key)		/* Key to use to find matching entry. */
{

    return ctable_CreateHashEntry(tablePtr, key, NULL);
}
#endif


/*
 *----------------------------------------------------------------------
 *
 * ctable_CreateHashEntry --
 *
 *	Given a hash table with string keys, and a string key, find the entry
 *	with a matching key. If there is no matching entry, then create a new
 *	entry that does match.
 *
 * Results:
 *	The return value is a pointer to the matching entry. If this is a
 *	newly-created entry, then *newPtr will be set to a non-zero value;
 *	otherwise *newPtr will be set to 0. If this is a new entry the value
 *	stored in the entry will initially be 0.
 *
 * Side effects:
 *	A new entry may be added to the hash table.
 *
 *----------------------------------------------------------------------
 */

ctable_HashEntry *
ctable_CreateHashEntry(
    ctable_HashTable *tablePtr,	/* Table in which to lookup entry. */
    CONST char *key,		/* Key to use to find or create matching
				 * entry. */
    int *newPtr)		/* Store info here telling whether a new entry
				 * was created. */
{
    register ctable_HashEntry *hPtr;
    ctable_HashKeyType *typePtr;
    unsigned int hash;
    int index;

    typePtr = tablePtr->typePtr;
    if (typePtr == NULL) {
	Tcl_Panic("called %s on deleted table", "ctable_CreateHashEntry");
	return NULL;
    }

    if (typePtr->hashKeyProc) {
	hash = typePtr->hashKeyProc (tablePtr, (VOID *) key);
	if (typePtr->flags & CTABLE_HASH_KEY_RANDOMIZE_HASH) {
	    index = RANDOM_INDEX (tablePtr, hash);
	} else {
	    index = hash & tablePtr->mask;
	}
    } else {
	hash = (unsigned int)(key);
	index = RANDOM_INDEX (tablePtr, hash);
    }

    /*
     * Search all of the entries in the appropriate bucket.
     */

    if (typePtr->compareKeysProc) {
	ctable_CompareHashKeysProc *compareKeysProc = typePtr->compareKeysProc;
	for (hPtr = tablePtr->buckets[index]; hPtr != NULL;
		hPtr = hPtr->nextPtr) {
	    if (hash != (unsigned int)(hPtr->hash)) {
		continue;
	    }
	    if (!compareKeysProc ((VOID *) key, hPtr)) {
		if (newPtr)
		    *newPtr = 0;
		return hPtr;
	    }
	}
    } else {
	for (hPtr = tablePtr->buckets[index]; hPtr != NULL;
		hPtr = hPtr->nextPtr) {
	    if (hash != (unsigned int)(hPtr->hash)) {
		continue;
	    }
	    if (key == hPtr->key.oneWordValue) {
		if (newPtr)
		    *newPtr = 0;
		return hPtr;
	    }
	}
    }

    if (!newPtr)
	return NULL;


    /*
     * Entry not found. Add a new one to the bucket.
     */

    *newPtr = 1;
    if (typePtr->allocEntryProc) {
	hPtr = typePtr->allocEntryProc (tablePtr, (VOID *) key);
    } else {
	hPtr = (ctable_HashEntry *) ckalloc((unsigned) sizeof(ctable_HashEntry));
	hPtr->key.oneWordValue = (char *) key;
    }

    hPtr->tablePtr = tablePtr;
    hPtr->hash = hash;
    hPtr->nextPtr = tablePtr->buckets[index];
    tablePtr->buckets[index] = hPtr;
    hPtr->clientData = 0;
    tablePtr->numEntries++;

    /*
     * If the table has exceeded a decent size, rebuild it with many more
     * buckets.
     */

    if (tablePtr->numEntries >= tablePtr->rebuildSize) {
	RebuildTable(tablePtr);
    }
    return hPtr;
}

/*
 *----------------------------------------------------------------------
 *
 * ctable_DeleteHashEntry --
 *
 *	Remove a single entry from a hash table.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	The entry given by entryPtr is deleted from its table and should never
 *	again be used by the caller. It is up to the caller to free the
 *	clientData field of the entry, if that is relevant.
 *
 *----------------------------------------------------------------------
 */

void
ctable_DeleteHashEntry(
    ctable_HashEntry *entryPtr)
{
    register ctable_HashEntry *prevPtr;
    ctable_HashKeyType *typePtr;
    ctable_HashTable *tablePtr;
    ctable_HashEntry **bucketPtr;
    int index;

    tablePtr = entryPtr->tablePtr;
    typePtr = tablePtr->typePtr;

    if (typePtr->hashKeyProc == NULL
	    || typePtr->flags & CTABLE_HASH_KEY_RANDOMIZE_HASH) {
	index = RANDOM_INDEX (tablePtr, entryPtr->hash);
    } else {
	index = (int)(entryPtr->hash) & tablePtr->mask;
    }

    bucketPtr = &(tablePtr->buckets[index]);

    if (*bucketPtr == entryPtr) {
	*bucketPtr = entryPtr->nextPtr;
    } else {
	for (prevPtr = *bucketPtr; ; prevPtr = prevPtr->nextPtr) {
	    if (prevPtr == NULL) {
		Tcl_Panic("malformed bucket chain in ctable_DeleteHashEntry");
	    }
	    if (prevPtr->nextPtr == entryPtr) {
		prevPtr->nextPtr = entryPtr->nextPtr;
		break;
	    }
	}
    }

    tablePtr->numEntries--;
    if (typePtr->freeEntryProc) {
	typePtr->freeEntryProc (entryPtr);
    } else {
	ckfree((char *) entryPtr);
    }
}

/*
 *----------------------------------------------------------------------
 *
 * ctable_DeleteHashTable --
 *
 *	Free up everything associated with a hash table except for the record
 *	for the table itself.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	The hash table is no longer useable.
 *
 *----------------------------------------------------------------------
 */

void
ctable_DeleteHashTable(
    register ctable_HashTable *tablePtr)	/* Table to delete. */
{
    register ctable_HashEntry *hPtr, *nextPtr;
    ctable_HashKeyType *typePtr;
    int i;

    typePtr = tablePtr->typePtr;

    /*
     * Free up all the entries in the table.
     */

    for (i = 0; i < tablePtr->numBuckets; i++) {
	hPtr = tablePtr->buckets[i];
	while (hPtr != NULL) {
	    nextPtr = hPtr->nextPtr;
	    if (typePtr->freeEntryProc) {
		typePtr->freeEntryProc (hPtr);
	    } else {
		ckfree((char *) hPtr);
	    }
	    hPtr = nextPtr;
	}
    }

    /*
     * Free up the bucket array, if it was dynamically allocated.
     */

    if (tablePtr->buckets != tablePtr->staticBuckets) {
	ckfree((char *) tablePtr->buckets);
    }

    /*
     * Arrange for panics if the table is used again without
     * re-initialization.
     */

    tablePtr->typePtr = NULL;
}

/*
 *----------------------------------------------------------------------
 *
 * ctable_FirstHashEntry --
 *
 *	Locate the first entry in a hash table and set up a record that can be
 *	used to step through all the remaining entries of the table.
 *
 * Results:
 *	The return value is a pointer to the first entry in tablePtr, or NULL
 *	if tablePtr has no entries in it. The memory at *searchPtr is
 *	initialized so that subsequent calls to ctable_NextHashEntry will return
 *	all of the entries in the table, one at a time.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

ctable_HashEntry *
ctable_FirstHashEntry(
    ctable_HashTable *tablePtr,	/* Table to search. */
    ctable_HashSearch *searchPtr)	/* Place to store information about progress
				 * through the table. */
{
    searchPtr->tablePtr = tablePtr;
    searchPtr->nextIndex = 0;
    searchPtr->nextEntryPtr = NULL;
    return ctable_NextHashEntry(searchPtr);
}

/*
 *----------------------------------------------------------------------
 *
 * ctable_NextHashEntry --
 *
 *	Once a hash table enumeration has been initiated by calling
 *	ctable_FirstHashEntry, this function may be called to return successive
 *	elements of the table.
 *
 * Results:
 *	The return value is the next entry in the hash table being enumerated,
 *	or NULL if the end of the table is reached.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

ctable_HashEntry *
ctable_NextHashEntry(
    register ctable_HashSearch *searchPtr)
				/* Place to store information about progress
				 * through the table. Must have been
				 * initialized by calling
				 * ctable_FirstHashEntry. */
{
    ctable_HashEntry *hPtr;
    ctable_HashTable *tablePtr = searchPtr->tablePtr;

    while (searchPtr->nextEntryPtr == NULL) {
	if (searchPtr->nextIndex >= tablePtr->numBuckets) {
	    return NULL;
	}
	searchPtr->nextEntryPtr =
		tablePtr->buckets[searchPtr->nextIndex];
	searchPtr->nextIndex++;
    }
    hPtr = searchPtr->nextEntryPtr;
    searchPtr->nextEntryPtr = hPtr->nextPtr;
    return hPtr;
}

/*
 *----------------------------------------------------------------------
 *
 * ctable_HashStats --
 *
 *	Return statistics describing the layout of the hash table in its hash
 *	buckets.
 *
 * Results:
 *	The return value is a malloc-ed string containing information about
 *	tablePtr. It is the caller's responsibility to free this string.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

CONST char *
ctable_HashStats(
    ctable_HashTable *tablePtr)	/* Table for which to produce stats. */
{
#define NUM_COUNTERS 10
    int count[NUM_COUNTERS], overflow, i, j;
    double average, tmp;
    register ctable_HashEntry *hPtr;
    char *result, *p;
    ctable_HashKeyType *typePtr;

    typePtr = tablePtr->typePtr;
    if (typePtr == NULL) {
	Tcl_Panic("called %s on deleted table", "ctable_HashStats");
	return NULL;
    }

    /*
     * Compute a histogram of bucket usage.
     */

    for (i = 0; i < NUM_COUNTERS; i++) {
	count[i] = 0;
    }
    overflow = 0;
    average = 0.0;
    for (i = 0; i < tablePtr->numBuckets; i++) {
	j = 0;
	for (hPtr = tablePtr->buckets[i]; hPtr != NULL; hPtr = hPtr->nextPtr) {
	    j++;
	}
	if (j < NUM_COUNTERS) {
	    count[j]++;
	} else {
	    overflow++;
	}
	tmp = j;
	if (tablePtr->numEntries != 0) {
	    average += (tmp+1.0)*(tmp/tablePtr->numEntries)/2.0;
	}
    }

    /*
     * Print out the histogram and a few other pieces of information.
     */

    result = (char *) ckalloc((unsigned) (NUM_COUNTERS*60) + 300);
    sprintf(result, "%d entries in table, %d buckets\n",
	    tablePtr->numEntries, tablePtr->numBuckets);
    p = result + strlen(result);
    for (i = 0; i < NUM_COUNTERS; i++) {
	sprintf(p, "number of buckets with %d entries: %d\n",
		i, count[i]);
	p += strlen(p);
    }
    sprintf(p, "number of buckets with %d or more entries: %d\n",
	    NUM_COUNTERS, overflow);
    p += strlen(p);
    sprintf(p, "average search distance for entry: %.1f", average);
    return result;
}

/*
 *----------------------------------------------------------------------
 *
 * AllocArrayEntry --
 *
 *	Allocate space for a ctable_HashEntry containing the array key.
 *
 * Results:
 *	The return value is a pointer to the created entry.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

static ctable_HashEntry *
AllocArrayEntry(
    ctable_HashTable *tablePtr,	/* Hash table. */
    VOID *keyPtr)		/* Key to store in the hash table entry. */
{
    int *array = (int *) keyPtr;
    register int *iPtr1, *iPtr2;
    ctable_HashEntry *hPtr;
    int count;
    unsigned int size;

    count = tablePtr->keyType;

    size = sizeof(ctable_HashEntry) + (count*sizeof(int)) - sizeof(hPtr->key);
    if (size < sizeof(ctable_HashEntry)) {
	size = sizeof(ctable_HashEntry);
    }
    hPtr = (ctable_HashEntry *) ckalloc(size);

    for (iPtr1 = array, iPtr2 = hPtr->key.words;
	    count > 0; count--, iPtr1++, iPtr2++) {
	*iPtr2 = *iPtr1;
    }

    return hPtr;
}

/*
 *----------------------------------------------------------------------
 *
 * CompareArrayKeys --
 *
 *	Compares two array keys.
 *
 * Results:
 *	The return value is 0 if they are are the same, -1 if the new
 *      key is less than the existing key and 1 if the new key is
 *      greater than the existing key.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

static int
CompareArrayKeys(
    VOID *keyPtr,		/* New key to compare. */
    ctable_HashEntry *hPtr)	/* Existing key to compare. */
{
    register CONST int *iPtr1 = (CONST int *) keyPtr;
    register CONST int *iPtr2 = (CONST int *) hPtr->key.words;
    ctable_HashTable *tablePtr = hPtr->tablePtr;
    int count;

    for (count = tablePtr->keyType; ; count--, iPtr1++, iPtr2++) {
	if (count == 0) {
	    return 0;
	}
	if (*iPtr1 != *iPtr2) {
	    if (*iPtr1 < *iPtr2) {
	        return -1;
	    } else {
	        return 1;
	    }
	    break;
	}
    }
    Tcl_Panic ("didn't think it could reach this point in CompareArrayKeys");
    return 0;
}

/*
 *----------------------------------------------------------------------
 *
 * HashArrayKey --
 *
 *	Compute a one-word summary of an array, which can be used to generate
 *	a hash index.
 *
 * Results:
 *	The return value is a one-word summary of the information in
 *	string.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

static unsigned int
HashArrayKey(
    ctable_HashTable *tablePtr,	/* Hash table. */
    VOID *keyPtr)		/* Key from which to compute hash value. */
{
    register CONST int *array = (CONST int *) keyPtr;
    register unsigned int result;
    int count;

    for (result = 0, count = tablePtr->keyType; count > 0;
	    count--, array++) {
	result += *array;
    }
    return result;
}

/*
 *----------------------------------------------------------------------
 *
 * AllocStringEntry --
 *
 *	Allocate space for a ctable_HashEntry containing the string key.
 *
 * Results:
 *	The return value is a pointer to the created entry.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

static ctable_HashEntry *
AllocStringEntry(
    ctable_HashTable *tablePtr,	/* Hash table. */
    VOID *keyPtr)		/* Key to store in the hash table entry. */
{
    CONST char *string = (CONST char *) keyPtr;
    ctable_HashEntry *hPtr;
    unsigned int size;

    size = sizeof(ctable_HashEntry) + strlen(string) + 1 - sizeof(hPtr->key);
    if (size < sizeof(ctable_HashEntry)) {
	size = sizeof(ctable_HashEntry);
    }
    hPtr = (ctable_HashEntry *) ckalloc(size);
    strcpy(hPtr->key.string, string);

    return hPtr;
}

/*
 *----------------------------------------------------------------------
 *
 * CompareStringKeys --
 *
 *	Compares two string keys.
 *
 * Results:
 *	The return value is 0 if they are the same, and -1 if the new key
 *      is less than the existing key and 1 if the new key is greater
 *      than the existing key.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

static int
CompareStringKeys(
    VOID *keyPtr,		/* New key to compare. */
    ctable_HashEntry *hPtr)	/* Existing key to compare. */
{
    register CONST char *p1 = (CONST char *) keyPtr;
    register CONST char *p2 = (CONST char *) hPtr->key.string;

#ifdef CTABLE_COMPARE_HASHES_WITH_STRCMP
    return strcmp(p1, p2);
#else
    for (;; p1++, p2++) {
	if (*p1 != *p2) {
	    if (*p1 < *p2) {
	        return -1;
	    } else {
	        return 1;
	    }
	    break;
	}
	if (*p1 == '\0') {
	    return 0;
	}
    }
    Tcl_Panic ("code failure in CompareStringKeys - should not be here");
    return 0;
#endif /* CTABLE_COMPARE_HASHES_WITH_STRCMP */
}

/*
 *----------------------------------------------------------------------
 *
 * HashStringKey --
 *
 *	Compute a one-word summary of a text string, which can be used to
 *	generate a hash index.
 *
 * Results:
 *	The return value is a one-word summary of the information in string.
 *
 * Side effects:
 *	None.
 *
 *----------------------------------------------------------------------
 */

static unsigned int
HashStringKey(
    ctable_HashTable *tablePtr,	/* Hash table. */
    VOID *keyPtr)		/* Key from which to compute hash value. */
{
    register CONST char *string = (CONST char *) keyPtr;
    register unsigned int result;
    register int c;

    /*
     * I tried a zillion different hash functions and asked many other people
     * for advice. Many people had their own favorite functions, all
     * different, but no-one had much idea why they were good ones. I chose
     * the one below (multiply by 9 and add new character) because of the
     * following reasons:
     *
     * 1. Multiplying by 10 is perfect for keys that are decimal strings, and
     *	  multiplying by 9 is just about as good.
     * 2. Times-9 is (shift-left-3) plus (old). This means that each
     *	  character's bits hang around in the low-order bits of the hash value
     *	  for ever, plus they spread fairly rapidly up to the high-order bits
     *	  to fill out the hash value. This seems works well both for decimal
     *	  and non-decimal strings, but isn't strong against maliciously-chosen
     *	  keys.
     */

    result = 0;

    for (c=*string++ ; c ; c=*string++) {
	result += (result<<3) + c;
    }
    return result;
}

/*
 *----------------------------------------------------------------------
 *
 * RebuildTable --
 *
 *	This function is invoked when the ratio of entries to hash buckets
 *	becomes too large. It creates a new table with a larger bucket array
 *	and moves all of the entries into the new table.
 *
 * Results:
 *	None.
 *
 * Side effects:
 *	Memory gets reallocated and entries get re-hashed to new buckets.
 *
 *----------------------------------------------------------------------
 */

static void
RebuildTable(
    register ctable_HashTable *tablePtr)	/* Table to enlarge. */
{
    int oldSize, count, index;
    ctable_HashEntry **oldBuckets;
    register ctable_HashEntry **oldChainPtr, **newChainPtr;
    register ctable_HashEntry *hPtr;
    ctable_HashKeyType *typePtr;

    typePtr = tablePtr->typePtr;

    oldSize = tablePtr->numBuckets;
    oldBuckets = tablePtr->buckets;

    /*
     * Allocate and initialize the new bucket array, and set up hashing
     * constants for new array size.
     */

    tablePtr->numBuckets *= 16;
    tablePtr->buckets = (ctable_HashEntry **) ckalloc((unsigned)
	    (tablePtr->numBuckets * sizeof(ctable_HashEntry *)));
    for (count = tablePtr->numBuckets, newChainPtr = tablePtr->buckets;
	    count > 0; count--, newChainPtr++) {
	*newChainPtr = NULL;
    }
    tablePtr->rebuildSize *= 16;
    tablePtr->downShift -= 4;
    tablePtr->mask = (tablePtr->mask << 4) + 15;

    printf("rebuilding table from %d buckets to %d buckets\n", oldSize, tablePtr->numBuckets);

    /*
     * Rehash all of the existing entries into the new bucket array.
     */

    for (oldChainPtr = oldBuckets; oldSize > 0; oldSize--, oldChainPtr++) {
	for (hPtr = *oldChainPtr; hPtr != NULL; hPtr = *oldChainPtr) {
	    *oldChainPtr = hPtr->nextPtr;
	    if (typePtr->hashKeyProc == NULL
		    || typePtr->flags & CTABLE_HASH_KEY_RANDOMIZE_HASH) {
		index = RANDOM_INDEX (tablePtr, hPtr->hash);
	    } else {
		index = (unsigned int)(hPtr->hash) & tablePtr->mask;
	    }
	    hPtr->nextPtr = tablePtr->buckets[index];
	    tablePtr->buckets[index] = hPtr;
	}
    }

    /*
     * Free up the old bucket array, if it was dynamically allocated.
     */

    if (oldBuckets != tablePtr->staticBuckets) {
	ckfree((char *) oldBuckets);
    }

    printf("done\n");
}

/*
 * Local Variables:
 * mode: c
 * c-basic-offset: 4
 * fill-column: 78
 * End:
 */
