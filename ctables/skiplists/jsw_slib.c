// $Id$

/*
  Classic skip list library

    > Created (Julienne Walker): April 11, 2004
    > Updated (Julienne Walker): August 19, 2005

    based on code released to the public domain by Julienne Walker
*/
#include "jsw_rand.h"
#include "jsw_slib.h"

#ifdef __cplusplus
#include <climits>
#include <cstdlib>

using std::size_t;
#else
#include <limits.h>
#include <stdlib.h>
#endif

typedef struct jsw_node {
  struct ctable_baseRow  *row;   /* Data row with combined key */
  size_t            height; /* Column height of this node */
  struct jsw_node **next;   /* Dynamic array of next links */
} jsw_node_t;

struct jsw_skip {
  jsw_node_t  *head; /* Full height header node */
  jsw_node_t **fix;  /* Update array */
  jsw_node_t  *curl; /* Current link for traversal */
  size_t       maxh; /* Tallest possible column */
  size_t       curh; /* Tallest available column */
  size_t       size; /* Number of row at level 0 */
  cmp_f        cmp;  /* User defined row compare function */
};

/*
  Weighted random level with probability 1/2.
  (For better distribution, modify with 1/3)

  Implements a tuned bit stream algorithm.
*/
static size_t rlevel ( size_t max )
{
  static size_t bits = 0;
  static size_t reset = 0;
  size_t h, found = 0;

  for ( h = 0; !found; h++ ) {
    if ( reset == 0 ) {
      bits = jsw_rand();
      reset = sizeof ( size_t ) * CHAR_BIT - 1;
    }

    /*
      For 1/3 change to:

      found = bits % 3;
      bits = bits / 3;
    */
    found = bits & 1;
    bits = bits >> 1;
    --reset;
  }

  if ( h >= max )
    h = max - 1;

  return h;
}

//
// new_node - construct an empty new node, does not make a copy of the row
//
static jsw_node_t *new_node ( struct ctable_baseRow *row, size_t height )
{
  jsw_node_t *node = (jsw_node_t *)ckalloc ( sizeof *node );
  size_t i;

  node->next = (jsw_node_t **)ckalloc ( height * sizeof *node->next );

  node->row = row;
  node->height = height;

  for ( i = 0; i < height; i++ )
    node->next[i] = NULL;

  return node;
}

//
// free_node - free a skip list node but not the row associated with it
//
static void free_node ( jsw_node_t *node )
{
  ckfree ( (void *)node->next );
  ckfree ( (void *)node );
}

//
// locate - find an existing row, or the position before where it would be
//
static jsw_node_t *locate ( jsw_skip_t *skip, struct ctable_baseRow *row )
{
  jsw_node_t *p = skip->head;
  size_t i;

  for ( i = skip->curh; i < (size_t)-1; i-- ) {
    while ( p->next[i] != NULL ) {
      if ( skip->cmp ( row, p->next[i]->row ) <= 0 ) {
        break;
      }

      p = p->next[i];
    }

    skip->fix[i] = p;
  }

  skip->curl = p;
  return p;
}

//
// jsw_sinit - initialize a skip list
//
void jsw_sinit ( jsw_skip_t *skip, size_t max, cmp_f cmp)
{
  skip->head = new_node ( NULL, ++max );

  skip->fix = (jsw_node_t **)ckalloc ( max * sizeof *skip->fix );

  skip->curl = NULL;
  skip->maxh = max;
  skip->curh = 0;
  skip->size = 0;
  skip->cmp = cmp;

  jsw_seed ( jsw_time_seed() );
}

//
// jsw_snew - allocate and initialize a new skip list
//
jsw_skip_t *jsw_snew ( size_t max, cmp_f cmp)
{
  jsw_skip_t *skip = (jsw_skip_t *)ckalloc ( sizeof *skip );

  jsw_sinit (skip, max, cmp);

  return skip;
}


//
// jsw_sdelete_skiplist - delete the entire skip list
//
// you have to delete your own row data
//
void jsw_sdelete_skiplist ( jsw_skip_t *skip )
{
  jsw_node_t *it = skip->head->next[0];
  jsw_node_t *save;

  while ( it != NULL ) {
    save = it->next[0];
    free_node ( it );
    it = save;
  }

  free_node ( skip->head );
  ckfree ( (void *)skip->fix );
  ckfree ( (void *)skip );
}

//
// jsw_sfind - given a skip list and a row, return the corresponding
//             skip list node pointer or NULL if none is found.
//
void *jsw_sfind ( jsw_skip_t *skip, struct ctable_baseRow *row )
{
  jsw_node_t *p = locate ( skip, row )->next[0];

  if ( p != NULL && skip->cmp ( row, p->row ) == 0 )
    return p;

  return NULL;
}

//
// jsw_sinsert - insert row into the skip list if it's not already there
//
// forces there to be no duplicate row by failing if a matching row is found
//
int jsw_sinsert ( jsw_skip_t *skip, struct ctable_baseRow *row )
{
  // void *p = locate ( skip, row )->row;
  jsw_node_t *p = locate ( skip, row )->next[0];

  // if we got something and it compares the same, it's already there
  if ( p != NULL && skip->cmp ( row, p->row ) == 0 )
    return 0;
  else {
    // it's new
    size_t h = rlevel ( skip->maxh );
    jsw_node_t *it;

    it = new_node ( row, h );

    /* Raise height if necessary */
    if ( h > skip->curh ) {
      h = ++skip->curh;
      skip->fix[h] = skip->head;
    }

    /* Build skip links */
    while ( --h < (size_t)-1 ) {
      it->next[h] = skip->fix[h]->next[h];
      skip->fix[h]->next[h] = it;
    }
  }

  skip->size++;
  return 1;
}

//
// jsw_sinsert_linked - insert row into the skip list if it's not already 
// there.  if it is already there, link this row into the skip list.
//
// you have to be sure it's not already in there
//
// currently can only succeed
//
int jsw_sinsert_linked ( jsw_skip_t *skip, struct ctable_baseRow *row , int nodeIdx)
{
  // void *p = locate ( skip, row )->row;
  jsw_node_t *p = locate ( skip, row )->next[0];

  if ( p != NULL && skip->cmp ( row, p->row ) == 0 ) {
    // matching skip list entry, insert this row into its linked list
    ctable_ListInsertHead (&p->row, row, nodeIdx);
  } else {
    // no matching skip list entry, create one and link
    size_t h = rlevel ( skip->maxh );
    jsw_node_t *it;

    it = new_node ( row, h );

    /* Raise height if necessary */
    if ( h > skip->curh ) {
      h = ++skip->curh;
      skip->fix[h] = skip->head;
    }

    /* Build skip links */
    while ( --h < (size_t)-1 ) {
      it->next[h] = skip->fix[h]->next[h];
      skip->fix[h]->next[h] = it;
    }
  }

  skip->size++;
  return 1;
}

//
// jsw_serase - locate an row in the skip list.  if it exists, delete it.
//
// return 1 if it deleted and 0 if no row matched
//
// you have to release the node externally to this
//
int jsw_serase ( jsw_skip_t *skip, struct ctable_baseRow *row )
{
  jsw_node_t *p = locate ( skip, row )->next[0];

  if ( p == NULL || skip->cmp ( row, p->row ) != 0 )
    return 0;
  else {
    size_t i;

    // fix skip list pointers that point directly to me by traversing
    // the fix list of stuff from the locate
    for ( i = 0; i < skip->curh; i++ ) {
      if ( skip->fix[i]->next[i] != p )
        break;

      skip->fix[i]->next[i] = p->next[i];
    }

    // free the node
    free_node ( p );
    skip->size--;

    /* Lower height if necessary */
    while ( skip->curh > 0 ) {
      if ( skip->head->next[skip->curh - 1] != NULL )
        break;

      --skip->curh;
    }
  }

  /* Erasure invalidates traversal markers */
  jsw_sreset ( skip );

  return 1;
}

void
jsw_dump_node (const char *s, jsw_node_t *p) {
    int         height;
    int         i;

    height = p->height;
    printf("%8lx '%s' height %d\n", (long unsigned int)p, s, height);
    for ( i = 0; i < height; i++ ) {
        printf ("%8lx ", (long unsigned int)p->next[i]);
    }
    printf("\n");
}

void
jsw_dump (const char *s, jsw_skip_t *skip) {
    jsw_node_t *p = skip->curl;

    jsw_dump_node (s, p);
}

void
jsw_dump_head (jsw_skip_t *skip) {
    jsw_node_t *p = skip->head;

    jsw_dump_node ("HEAD", p);
}

//
// jsw_ssize - return the size of the skip table
//
size_t jsw_ssize ( jsw_skip_t *skip )
{
  return skip->size;
}

//
// jsw_reset - invalidate traversal markers by resetting the current link
//             for traversal to the first element in the list
//
void jsw_sreset ( jsw_skip_t *skip )
{
  skip->curl = skip->head->next[0];
}

//
// jsw_srow - get row pointed to by the the current link or NULL if none
//
struct ctable_baseRow *jsw_srow ( jsw_skip_t *skip )
{
  return skip->curl == NULL ? NULL : skip->curl->row;
}

//
// jsw_snext - move the current link to the next row, returning 1 if there
//             is a next row and a 0 if there isn't
//
int jsw_snext ( jsw_skip_t *skip )
{
  return ( skip->curl = skip->curl->next[0] ) != NULL;
}
