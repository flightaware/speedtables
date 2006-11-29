// $Id$

/*
  Classic skip list library

    > Created (Julienne Walker): April 11, 2004
    > Updated (Julienne Walker): August 19, 2005
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
  void             *item;   /* Data item with combined key */
  size_t            height; /* Column height of this node */
  struct jsw_node **next;   /* Dynamic array of next links */
} jsw_node_t;

struct jsw_skip {
  jsw_node_t  *head; /* Full height header node */
  jsw_node_t **fix;  /* Update array */
  jsw_node_t  *curl; /* Current link for traversal */
  size_t       maxh; /* Tallest possible column */
  size_t       curh; /* Tallest available column */
  size_t       size; /* Number of items at level 0 */
  cmp_f        cmp;  /* User defined item compare function */
  rel_f        rel;  /* User defined delete function */
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
// new_node - construct an empty new node, does not make a copy of the item
//
static jsw_node_t *new_node ( void *item, size_t height )
{
  jsw_node_t *node = (jsw_node_t *)ckalloc ( sizeof *node );
  size_t i;

  node->next = (jsw_node_t **)ckalloc ( height * sizeof *node->next );

  node->item = item;
  node->height = height;

  for ( i = 0; i < height; i++ )
    node->next[i] = NULL;

  return node;
}

//
// free_node - free a skip list node but not the item associated with it
//
static void free_node ( jsw_node_t *node )
{
  ckfree ( node->next );
  ckfree ( node );
}

//
// locate - find an existing item, or the position before where it would be
//
static jsw_node_t *locate ( jsw_skip_t *skip, void *item )
{
  jsw_node_t *p = skip->head;
  size_t i;

  for ( i = skip->curh; i < (size_t)-1; i-- ) {
    while ( p->next[i] != NULL ) {
      if ( skip->cmp ( item, p->next[i]->item ) <= 0 )
        break;

      p = p->next[i];
    }

    skip->fix[i] = p;
  }

  return p;
}

//
// jsw_snew - allocate and initialize a new skip list
//
jsw_skip_t *jsw_snew ( size_t max, cmp_f cmp, rel_f rel )
{
  jsw_skip_t *skip = (jsw_skip_t *)ckalloc ( sizeof *skip );

  skip->head = new_node ( NULL, ++max );

  skip->fix = (jsw_node_t **)ckalloc ( max * sizeof *skip->fix );

  skip->curl = NULL;
  skip->maxh = max;
  skip->curh = 0;
  skip->size = 0;
  skip->cmp = cmp;
  skip->rel = rel;

  jsw_seed ( jsw_time_seed() );

  return skip;
}

//
// jsw_sdelete - delete the entire skip list
//
void jsw_sdelete ( jsw_skip_t *skip )
{
  jsw_node_t *it = skip->head->next[0];
  jsw_node_t *save;

  while ( it != NULL ) {
    save = it->next[0];
    skip->rel ( it->item );
    free_node ( it );
    it = save;
  }

  free_node ( skip->head );
  ckfree ( skip->fix );
  ckfree ( skip );
}

//
// jsw_sfind - given a skip list and an item, return the corresponding
//             skip list node pointer or NULL if none is found.
//
void *jsw_sfind ( jsw_skip_t *skip, void *item )
{
  jsw_node_t *p = locate ( skip, item )->next[0];

  if ( p != NULL && skip->cmp ( item, p->item ) == 0 )
    return p;

  return NULL;
}

//
// jsw_sinsert - insert item into the skip list if it's not already there
//
// forces there to be no duplicate row by failing if a matching row is found
//
int jsw_sinsert ( jsw_skip_t *skip, void *item )
{
  void *p = locate ( skip, item )->item;

  // if we got something and it compares the same, it's already there
  if ( p != NULL && skip->cmp ( item, p ) == 0 )
    return 0;
  else {
    // it's new
    size_t h = rlevel ( skip->maxh );
    jsw_node_t *it;

    it = new_node ( item, h );

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

  return 1;
}

//
// jsw_sinsert_allow_dups - insert item into the skip list whether there's
                            already a matching item or not.
//
//
int jsw_sinsert_allow_dups ( jsw_skip_t *skip, void *item )
{
    locate ( skip, item );

    // we got something or we didn't, fix is primed, proceed

    size_t h = rlevel ( skip->maxh );
    jsw_node_t *it;

    it = new_node ( item, h );

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

  return 1;
}

//
// jsw_serase - locate an item in the skip list.  if it exists, delete it.
//
// return 1 if it deleted and 0 if no item matched
//
int jsw_serase ( jsw_skip_t *skip, void *item )
{
  jsw_node_t *p = locate ( skip, item )->next[0];

  if ( p == NULL || skip->cmp ( item, p->item ) != 0 )
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

    // release the item through the supplied callbak
    skip->rel ( p->item );

    // free the node
    free_node ( p );

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
// jsw_sitem - get item pointed to by the the current link or NULL if none
//
void *jsw_sitem ( jsw_skip_t *skip )
{
  return skip->curl == NULL ? NULL : skip->curl->item;
}

//
// jsw_snext - move the current link to the next item, returning 1 if there
//             is a next item and a 0 if there isn't
//
int jsw_snext ( jsw_skip_t *skip )
{
  return ( skip->curl = skip->curl->next[0] ) != NULL;
}
