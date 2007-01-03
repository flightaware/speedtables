// $Id$

#ifndef JSW_SLIB_H
#define JSW_SLIB_H

/*
  Classic skip list library

    > Created (Julienne Walker): April 11, 2004
    > Updated (Julienne Walker): August 19, 2005

  This code is in the public domain. Anyone may
  use it or change it in any way that they see
  fit. The author assumes no responsibility for 
  damages incurred through use of the original
  code or any variations thereof.

  It is requested, but not required, that due
  credit is given to the original author and
  anyone who has modified the code through
  a header comment, such as this one.
*/
#ifdef __cplusplus
#include <cstddef>

using std::size_t;

extern "C" {
#else
#include <stddef.h>
#endif

typedef struct jsw_skip jsw_skip_t;

/* Application specific key comparison function */
typedef int   (*cmp_f) ( const struct ctable_baseRow *row1, const struct ctable_baseRow *row2 );

/*
  Create a new skip list with a max height of max

  Returns: An empty skip list, or NULL on failure
*/
jsw_skip_t *jsw_snew ( size_t max, cmp_f cmp);

/* Release all memory used by the skip list */
void        jsw_sdelete_skiplist ( jsw_skip_t *skip );

/*
  Find a row with the selected key

  Returns: The row, or NULL if not found
*/
void       *jsw_sfind ( jsw_skip_t *skip, struct ctable_baseRow *row );

/*
  Insert a row with the selected key

  Returns: non-zero for success, zero for failure
*/
int         jsw_sinsert ( jsw_skip_t *skip, struct ctable_baseRow *row );

/*
  Insert a row with the selected key

  Returns: non-zero for success, zero for failure
*/
int jsw_sinsert_linked ( jsw_skip_t *skip, struct ctable_baseRow *row, int nodeIdx, int unique );

/*
  Remove a row with the selected key

  Returns: non-zero for success, zero for failure
*/
int         jsw_serase ( jsw_skip_t *skip, struct ctable_baseRow *row );

/* Current number of rows at height 0 */
size_t      jsw_ssize ( jsw_skip_t *skip );

/* Reset the traversal markers to the beginning */
void        jsw_sreset ( jsw_skip_t *skip );

/*
  Get the current row

  Returns the row, or NULL if end-of-list
*/
struct ctable_baseRow       *jsw_srow ( jsw_skip_t *skip );

/*
  Traverse forward by one key

  Returns 0 if end-of-list, 1 otherwise
*/
int         jsw_snext ( jsw_skip_t *skip );

#ifdef __cplusplus
}
#endif

#endif
