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

using std::malloc;
using std::free;
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
  dup_f        dup;  /* User defined item copy function */
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

/* This function does not make a copy of the item */
static jsw_node_t *new_node ( void *item, size_t height )
{
  jsw_node_t *node = (jsw_node_t *)malloc ( sizeof *node );
  size_t i;

  if ( node == NULL )
    return NULL;

  node->next = (jsw_node_t **)malloc ( height * sizeof *node->next );

  if ( node->next == NULL ) {
    free ( node );
    return NULL;
  }

  node->item = item;
  node->height = height;

  for ( i = 0; i < height; i++ )
    node->next[i] = NULL;

  return node;
}

/* This function does not release an item's memory */
static void delete_node ( jsw_node_t *node )
{
  free ( node->next );
  free ( node );
}

/* Find an existing item, or the position before where it would be */
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

/* Allocate and initialize a new skip list */
jsw_skip_t *jsw_snew ( size_t max, cmp_f cmp, dup_f dup, rel_f rel )
{
  jsw_skip_t *skip = (jsw_skip_t *)malloc ( sizeof *skip );

  if ( skip == NULL )
    return NULL;

  skip->head = new_node ( NULL, ++max );

  if ( skip->head == NULL ) {
    free ( skip );
    return NULL;
  }

  skip->fix = (jsw_node_t **)malloc ( max * sizeof *skip->fix );

  if ( skip->fix == NULL ) {
    delete_node ( skip->head );
    free ( skip );
    return NULL;
  }

  skip->curl = NULL;
  skip->maxh = max;
  skip->curh = 0;
  skip->size = 0;
  skip->cmp = cmp;
  skip->dup = dup;
  skip->rel = rel;

  jsw_seed ( jsw_time_seed() );

  return skip;
}

void jsw_sdelete ( jsw_skip_t *skip )
{
  jsw_node_t *it = skip->head->next[0];
  jsw_node_t *save;

  while ( it != NULL ) {
    save = it->next[0];
    skip->rel ( it->item );
    delete_node ( it );
    it = save;
  }

  delete_node ( skip->head );
  free ( skip->fix );
  free ( skip );
}

void *jsw_sfind ( jsw_skip_t *skip, void *item )
{
  jsw_node_t *p = locate ( skip, item )->next[0];

  if ( p != NULL && skip->cmp ( item, p->item ) == 0 )
    return p;

  return NULL;
}

int jsw_sinsert ( jsw_skip_t *skip, void *item )
{
  void *p = locate ( skip, item )->item;

  if ( p != NULL && skip->cmp ( item, p ) == 0 )
    return 0;
  else {
    /* Try to allocate before making changes */
    size_t h = rlevel ( skip->maxh );
    void *dup = skip->dup ( item );
    jsw_node_t *it;

    if ( dup == NULL )
      return 0;

    it = new_node ( dup, h );

    if ( it == NULL ) {
      skip->rel ( dup );
      return 0;
    }

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

int jsw_serase ( jsw_skip_t *skip, void *item )
{
  jsw_node_t *p = locate ( skip, item )->next[0];

  if ( p == NULL || skip->cmp ( item, p->item ) != 0 )
    return 0;
  else {
    size_t i;

    /* Erase column */
    for ( i = 0; i < skip->curh; i++ ) {
      if ( skip->fix[i]->next[i] != p )
        break;

      skip->fix[i]->next[i] = p->next[i];
    }

    skip->rel ( p->item );
    delete_node ( p );

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

size_t jsw_ssize ( jsw_skip_t *skip )
{
  return skip->size;
}

void jsw_sreset ( jsw_skip_t *skip )
{
  skip->curl = skip->head->next[0];
}

void *jsw_sitem ( jsw_skip_t *skip )
{
  return skip->curl == NULL ? NULL : skip->curl->item;
}

int jsw_snext ( jsw_skip_t *skip )
{
  return ( skip->curl = skip->curl->next[0] ) != NULL;
}
