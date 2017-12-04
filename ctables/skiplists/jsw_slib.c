// $Id$

/*
  Classic skip list library

    > Created (Julienne Walker): April 11, 2004
    > Updated (Julienne Walker): August 19, 2005

    based on code released to the publicdata domain by Julienne Walker
*/
#include "jsw_rand.h"
#include "jsw_slib.h"
#ifdef WITH_SHARED_TABLES
#include "shared.h"
#endif

#ifdef __cplusplus
#include <climits>
#include <cstdlib>

using std::size_t;
#else
#include <limits.h>
#include <stdlib.h>
#endif

#define DUMPER 1

typedef struct jsw_node {
  ctable_BaseRow         *row;      /* Data row with combined key */
  size_t                  height;   /* Column height of this node */
  struct jsw_node        *next[];   /* Dynamic array of next links */
} jsw_node_t;

// dynamic shared elements
typedef struct jsw_pub {
  jsw_node_t  *head; /* Full height header node */
  size_t       curh; /* Tallest available column */
  size_t       size; /* Number of row at level 0 */
} jsw_pub_t;

// statically defined and private elements
struct jsw_skip {
  int          id; /* 0 for owner, pid for shared reader */
  jsw_pub_t   *publicdata; /* shared data */
  jsw_node_t  *curl; /* Current link for traversal */
  size_t       maxh; /* Tallest possible column */
  cmp_f        cmp;  /* User defined row compare function */
#ifdef WITH_SHARED_TABLES
  shm_t       *share; /* Shared memory this table belongs to */
#else
  void        *share;
#endif
  jsw_node_t **fix;  /* Update array */
};

/*
  Weighted random level with probability 1/2.
  (For better distribution, modify with 1/3)

  Implements a tuned bit stream algorithm.
*/
INLINE
static size_t rlevel ( size_t max )
{
  static size_t bits = 0;
  static size_t reset = 0;
  size_t h, found = 0;

  for ( h = 0; !found; h++ ) {
    if ( reset == 0 ) {
      bits = jsw_rand();
// printf("bits %lx\n", bits);

      // reset = sizeof ( size_t ) * CHAR_BIT - 1;
      reset = 31;

// printf("bits %lx, reset %d\n", (long)bits, (int)reset);
    }

    /*
      For 1/3 change to:

      found = bits % 3;
      bits = bits / 3;
    */
    found = bits & 1;
    bits = bits >> 1;
    --reset;
// printf("found %d bits %lx reset %d h %d\n", (int)found, (long)bits, (int)reset, (int)h);
  }
// printf("rlh %d\n", (int) h);

  if ( h >= max )
// printf("big h %d\n", (int) h);
    h = max - 1;

  return h;
}

//
// new_node - construct an empty new node, does not make a copy of the row
//
INLINE
static jsw_node_t *new_node ( ctable_BaseRow *row, size_t height, void *share )
{
  jsw_node_t *node;
  size_t i;

#ifdef WITH_SHARED_TABLES
  if(share) {
    node  = (jsw_node_t *)shmalloc ((shm_t*)share, sizeof (jsw_node_t) + height * sizeof (jsw_node_t *) );
    if(!node) {
      //if(DUMPER) shmdump(share);
      Tcl_Panic("Can't allocate shared memory for skiplist");
    }
  } else
#endif
    node  = (jsw_node_t *)ckalloc ( sizeof (jsw_node_t) + height * sizeof (jsw_node_t *) );

  node->row = row;

  node->height = height;

  for ( i = 0; i < height; i++ )
    node->next[i] = NULL;

  return node;
}

//
// free_node - free a skip list node but not the row associated with it
//
INLINE
static void free_node ( jsw_node_t *node, void *share )
{
#ifdef WITH_SHARED_TABLES
  if(share)
    shmfree((shm_t *)share, (char *)node);
  else
#endif
    ckfree ( (char *)node );
}

//
// locate - find an existing row, or the position before where it would be
//
INLINE
static jsw_node_t *locate ( jsw_skip_t *skip, ctable_BaseRow *row )
{
  jsw_node_t *p = skip->publicdata->head;
  cmp_f       cmp = skip->cmp;
  size_t i;
  jsw_node_t *next;

  for ( i = skip->publicdata->curh; i < (size_t)-1; i-- ) {
    while ( (next = p->next[i]) != NULL ) {
      if ( cmp ( row, next->row ) <= 0 ) {
        break;
      }

      p = next;
    }

    skip->fix[i] = p;
  }

  return p;
}

//
// jsw_private - return a private version of a skiplist in shared memory
//
jsw_skip_t *jsw_private ( jsw_skip_t *skip, size_t max, cmp_f cmp, void *share, int id )
{
  jsw_skip_t *new_skip = skip;

  if(id == 0) {
    // If this is a new skiplist, initialize skiplist structure
    skip->id = id;
    skip->fix = NULL;
    skip->curl = NULL;
  } else if(skip->id != id) {
    // If this isn't my skiplist, allocate new skiplist structure
    new_skip = (jsw_skip_t *)ckalloc(sizeof *skip);

    new_skip->curl = skip->curl;
    new_skip->id = id;
    new_skip->fix = NULL;
    new_skip->publicdata = skip->publicdata;

    skip = new_skip;
  }

  // initialise dynamic private data if necessary
  if (!skip->fix) {
    skip->fix = (jsw_node_t **)ckalloc ( max * sizeof *skip->fix );
  }

  // Fill in static private data
  skip->maxh = max;
#ifdef WITH_SHARED_TABLES
  skip->share = (shm_t*) share;
#else
  skip->share = share;
#endif
  skip->cmp = cmp;
  return skip;
}

//
// free private copy of skiplist only
//
void jsw_free_private_copy(jsw_skip_t *skip)
{
    if(skip->fix)
	ckfree((char *)skip->fix);
    ckfree((char *)skip);
}

//
// clone skiplist if needed
//
jsw_skip_t *jsw_private_copy(jsw_skip_t *skip, int id, cmp_f cmp)
{
    if(skip->id != id)
	return jsw_private(skip, skip->maxh, cmp?cmp:skip->cmp, skip->share, id);
    return NULL;
}

//
// jsw_sinit - initialize a skip list
//
void jsw_sinit ( jsw_skip_t *skip, size_t max, cmp_f cmp, void *share)
{
#ifdef WITH_SHARED_TABLES
  if(share) {
    skip->publicdata = (jsw_pub_t *)shmalloc ( (shm_t *)share, sizeof *skip->publicdata );
    if(!skip) {
      //if(DUMPER) shmdump(share);
      Tcl_Panic("Can't allocate shared memory for skiplist");
    }
  } else
#endif
    skip->publicdata = (jsw_pub_t *)ckalloc ( sizeof *skip->publicdata );

  skip->publicdata->head = new_node ( NULL, ++max, share );

  skip->publicdata->curh = 0;
  skip->publicdata->size = 0;

  // We're creating this skiplist, our "id" is zero
  // (now fills in skip->maxh, skip->curl)
  jsw_private(skip, max, cmp, share, 0);

  jsw_seed ( jsw_time_seed() );
}

//
// jsw_snew - allocate and initialize a new skip list
//
jsw_skip_t *jsw_snew ( size_t max, cmp_f cmp, void *share)
{
  jsw_skip_t *skip;

#ifdef WITH_SHARED_TABLES
  if(share) {
    skip = (jsw_skip_t *)shmalloc ( (shm_t *)share, sizeof *skip );
    if(!skip) {
      //if(DUMPER) shmdump(share);
      Tcl_Panic("Can't allocate shared memory for skiplist");
    }
  } else
#endif
    skip = (jsw_skip_t *)ckalloc ( sizeof *skip );

  jsw_sinit (skip, max, cmp, share);

  return skip;
}

//
// jsw_sdelete_skiplist - delete the entire skip list
//
// you have to delete your own row data
//
void jsw_sdelete_skiplist ( jsw_skip_t *skip, int final )
{
  jsw_node_t *it = skip->publicdata->head->next[0];
  jsw_node_t *save;

  while ( it != NULL ) {
    save = it->next[0];
#ifdef WITH_SHARED_TABLES
    if(!final || !skip->share)
#endif
      free_node ( it, skip->share );
    it = save;
  }

  free_node ( skip->publicdata->head, skip->share );

  ckfree ( (char *)skip->fix );

#ifdef WITH_SHARED_TABLES
  if(skip->share) {
    if(!final)
      shmfree(skip->share, (char *)skip);
  } else
#endif
    ckfree ( (char *)skip );
}

//
// jsw_sfind - given a skip list and a row, return the corresponding
//             skip list node pointer or NULL if none is found.
//
INLINE
void *jsw_sfind ( jsw_skip_t *skip, ctable_BaseRow *row )
{
  jsw_node_t *p = locate ( skip, row )->next[0];

  skip->curl = p;

  if ( p != NULL && skip->cmp ( row, p->row ) == 0 )
    return p;

  return NULL;
}

//
// jsw_sfind_equal_or_greater - given a skip list and a row, return the 
//     corresponding skip list node pointer that matches the specified
//     row or exceeds it.
//
INLINE
void *jsw_sfind_equal_or_greater ( jsw_skip_t *skip, ctable_BaseRow *row )
{
  jsw_node_t *p = locate ( skip, row )->next[0];
  cmp_f       cmp = skip->cmp;

//printf("find_equal_or_greater row %8lx, p %8lx ", (long unsigned int)row, (long unsigned int)p);

  while (p !=NULL && cmp (p->row, row) < 0) {
//printf("p->%8lx ", (long unsigned int)p);
      p = p->next[0];
  }

//printf(" *%d* ", cmp (p->row, row));
//printf("skip->curl %8lx\n", (long unsigned int)p);
  skip->curl = p;

  return p;
}

//
// jsw_findlast - find a row with the lexically highest key in the table
//
INLINE 
void *jsw_findlast ( jsw_skip_t *skip)
{
  jsw_node_t *p = skip->publicdata->head;
  size_t i;
  jsw_node_t *next;

  for ( i = skip->publicdata->curh; i < (size_t)-1; i-- ) {
    while ( (next = p->next[i]) != NULL ) {
      p = next;
    }
  }

  skip->curl = p;
  return p;
}

//
// jsw_sinsert - insert row into the skip list if it's not already there
//
// forces there to be no duplicate row by failing if a matching row is found
//
INLINE
int jsw_sinsert ( jsw_skip_t *skip, ctable_BaseRow *row )
{
  // void *p = locate ( skip, row )->row;
  jsw_node_t *p = locate ( skip, row )->next[0];
  cmp_f       cmp = skip->cmp;

  // if we got something and it compares the same, it's already there
  if ( p != NULL && cmp ( row, p->row ) == 0 ) {
    return 0;
  } else {
    // it's new
    size_t h = rlevel ( skip->maxh );
    jsw_node_t *it;

    it = new_node ( row, h, skip->share );

    /* Raise height if necessary */
    if ( h > skip->publicdata->curh ) {
// printf("raising the height from %d to %d, size %d\n", (int)skip->publicdata->curh, (int)h, (int)skip->publicdata->size);
      h = ++skip->publicdata->curh;
      skip->fix[h] = skip->publicdata->head;
    }

    /* Build skip links */
    while ( --h < (size_t)-1 ) {
      it->next[h] = skip->fix[h]->next[h];
      skip->fix[h]->next[h] = it;
    }
  }

  skip->publicdata->size++;
  return 1;
}

//
// jsw_sinsert_linked - insert row into the skip list if it's not already 
// there.  if it is already there, link this row into the skip list.
//
INLINE
int jsw_sinsert_linked ( jsw_skip_t *skip, ctable_BaseRow *row , int nodeIdx, int unique)
{
  // void *p = locate ( skip, row )->row;
  jsw_node_t *p = locate ( skip, row )->next[0];

  if ( p != NULL && skip->cmp ( row, p->row ) == 0 ) {
    // we found a matching skip list entry

    // if dups aren't allowed, don't do anything and return 0
    if (unique) {
        return 0;
    }

    // dups are allowed, insert this guy
    ctable_ListInsertHead (&p->row, row, nodeIdx);
  } else {
    // no matching skip list entry

    // insert the new node
    size_t h = rlevel ( skip->maxh );
    jsw_node_t *it;

// printf("h %d\n", (int)h);

    it = new_node ( row, h, skip->share );

    // Throw away the row we just inserted with new_node! Yes, we mean to do this.
    ctable_ListInit (&it->row, __FILE__, __LINE__);

    ctable_ListInsertHead (&it->row, row, nodeIdx);

    /* Raise height if necessary */
    if ( h > skip->publicdata->curh ) {
// printf("raising the height from %d to %d, size %d\n", (int)skip->publicdata->curh, (int)h, (int)skip->publicdata->size);
      h = ++skip->publicdata->curh;
      skip->fix[h] = skip->publicdata->head;
    }

    /* Build skip links */
    while ( --h < (size_t)-1 ) {
      it->next[h] = skip->fix[h]->next[h];
      skip->fix[h]->next[h] = it;
    }
  }

  skip->publicdata->size++;
  return 1;
}

//
// jsw_serase - locate an row in the skip list.  if it exists, delete it.
//
// return 1 if it deleted and 0 if no row matched
//
// you have to release the node externally to this
//
int jsw_serase ( jsw_skip_t *skip, ctable_BaseRow *row )
{
  jsw_node_t *p = locate ( skip, row )->next[0];

  if ( p == NULL || skip->cmp ( row, p->row ) != 0 )
    return 0;
  else {
    size_t i;

    // fix skip list pointers that point directly to me by traversing
    // the fix list of stuff from the locate
    for ( i = 0; i < skip->publicdata->curh; i++ ) {
      if ( skip->fix[i]->next[i] != p )
        break;

      skip->fix[i]->next[i] = p->next[i];
    }

    // free the node
    free_node ( p, skip->share );
    skip->publicdata->size--;

    /* Lower height if necessary */
    while ( skip->publicdata->curh > 0 ) {
      if ( skip->publicdata->head->next[skip->publicdata->curh - 1] != NULL )
        break;

      --skip->publicdata->curh;
    }
  }

  /* Erasure invalidates traversal markers */
  jsw_sreset ( skip );

  return 1;
}

void
jsw_dump_node (const char *s, jsw_skip_t *skip, jsw_node_t *p, int indexNumber) {
    int             height;
    int             i;
    ctable_BaseRow *walkRow;
    cmp_f           cmp = skip->cmp;

    height = p->height;
    printf("%8lx '%s' height %d\n    list ", (long unsigned int)p, s, height);

    if (indexNumber < 0) {
        printf ("(head)");
    } else {
	CTABLE_LIST_FOREACH (p->row, walkRow, indexNumber) {
	    printf("%8lx ", (long unsigned int)walkRow);
	    if ( cmp ( p->row, walkRow ) != 0 ) {
	        Tcl_Panic ("index hosed - value in dup list doesn't match others, p->row == 0x%08lx, walkRow == 0x%08lx", (long)p->row, (long)walkRow);
	    }
	}
    }
    printf("\n");
        
    for ( i = 0; i < height; i++ ) {
        printf ("%8lx ", (long unsigned int)p->next[i]);
    }
    printf("\n");
}

void
jsw_dump (const char *s, jsw_skip_t *skip, int indexNumber) {
    jsw_node_t *p = skip->curl;

    jsw_dump_node (s, skip, p, indexNumber);
}

void
jsw_dump_head (jsw_skip_t *skip) {
    jsw_node_t *p = skip->publicdata->head;

    jsw_dump_node ("HEAD", skip, p, -1);
}

//
// jsw_ssize - return the size of the skip table
//
size_t jsw_ssize ( jsw_skip_t *skip )
{
  return skip->publicdata->size;
}

//
// jsw_reset - invalidate traversal markers by resetting the current link
//             for traversal to the first element in the list
//
void jsw_sreset ( jsw_skip_t *skip )
{
  skip->curl = skip->publicdata->head->next[0];
}

//
// jsw_sreset_head - like jsw_sreset except points to head instead of
// what head points to so jsw_snext can be called in a while loop to traverse
//
void jsw_sreset_head ( jsw_skip_t *skip )
{
  skip->curl = skip->publicdata->head;
}

//
// jsw_srow - get row pointed to by the the current link or NULL if none
//
INLINE
ctable_BaseRow *jsw_srow ( jsw_skip_t *skip )
{
  return skip->curl == NULL ? NULL : skip->curl->row;
}

//
// jsw_snext - move the current link to the next row, returning 1 if there
//             is a next row and a 0 if there isn't
//
INLINE int
jsw_snext ( jsw_skip_t *skip )
{
  jsw_node_t *curl = skip->curl;
  jsw_node_t *next = curl->next[0];
  return ( skip->curl = next ) != NULL;
}

// vim: set ts=8 sw=4 sts=4 noet :
