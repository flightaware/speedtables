/*
 * ctable.h - include file for ctables
 *
 * $Id$
 *
 */

#ifndef CTABLE_H
#define CTABLE_H

#include <tcl.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/ethernet.h>

#ifdef HAVE_NETINET_ETHER_H
#include <netinet/ether.h>
#endif

#ifdef HAVE_SYS_LIMITS_H
#include <sys/limits.h>
#endif

#ifdef WITH_PGTCL
#include <libpq-fe.h>
#endif

#include "speedtables.h"

#ifdef WITH_SHARED_TABLES
#include "shared.c"

#define DEFAULT_SHARED_SIZE (1024*1024*4)
#define MIN_MIN_FREE (1024*128)
#define MAX_MIN_FREE (1024*1024*8)

// How often do we allow the shared memory search to restart
#define MAX_RESTARTS 1000

#endif

// types of quoting for tabsep fields
#define CTABLE_QUOTE_NONE 0
#define CTABLE_QUOTE_URI 1
#define CTABLE_QUOTE_STRICT_URI 2
#define CTABLE_QUOTE_ESCAPE 3
#define CTABLE_QUOTE_STRICT_ESCAPE 4

/*-
 *
 * LIST_* - link list routines from Berkeley
 *
 * Copyright (c) 1991, 1993
 *      The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *      @(#)queue.h     8.5 (Berkeley) 8/20/94
 * $FreeBSD: src/sys/sys/queue.h,v 1.72.2.3.2.1 2010/12/21 17:09:25 kensmith Exp $
 */

/*
 * bidirectionally linked list declarations, from BSD
 */
#define	LIST_HEAD(name, type)						\
struct name {								\
	struct type *lh_first;	/* first element */			\
}

#define	LIST_HEAD_INITIALIZER(head)					\
	{ NULL }

#define	LIST_ENTRY(type)						\
struct {								\
	struct type *le_next;	/* next element */			\
	struct type **le_prev;	/* address of previous next element */	\
}

/*
 * bidirectionally linked list functions, from BSD
 */

#define	LIST_EMPTY(head)	((head)->lh_first == NULL)

#define	LIST_FIRST(head)	((head)->lh_first)

#define	LIST_FOREACH(var, head, field)					\
	for ((var) = LIST_FIRST((head));				\
	    (var);							\
	    (var) = LIST_NEXT((var), field))

#define	LIST_FOREACH_SAFE(var, head, field, tvar)			\
	for ((var) = LIST_FIRST((head));				\
	    (var) && ((tvar) = LIST_NEXT((var), field), 1);		\
	    (var) = (tvar))

#define	LIST_INIT(head) do {						\
	LIST_FIRST((head)) = NULL;					\
} while (0)

#define	LIST_INSERT_HEAD(head, elm, field) do {				\
	if ((LIST_NEXT((elm), field) = LIST_FIRST((head))) != NULL)	\
		LIST_FIRST((head))->field.le_prev = &LIST_NEXT((elm), field);\
	LIST_FIRST((head)) = (elm);					\
	(elm)->field.le_prev = &LIST_FIRST((head));			\
} while (0)

#define	LIST_NEXT(elm, field)	((elm)->field.le_next)

#define	LIST_REMOVE(elm, field) do {					\
	if (LIST_NEXT((elm), field) != NULL)				\
		LIST_NEXT((elm), field)->field.le_prev = 		\
		    (elm)->field.le_prev;				\
	*(elm)->field.le_prev = LIST_NEXT((elm), field);		\
} while (0)



// these types must line up with ctableTypes in gentable.tcl
enum ctable_types {
    CTABLE_TYPE_BOOLEAN,
    CTABLE_TYPE_FIXEDSTRING,
    CTABLE_TYPE_VARSTRING,
    CTABLE_TYPE_CHAR,
    CTABLE_TYPE_MAC,
    CTABLE_TYPE_SHORT,
    CTABLE_TYPE_INT,
    CTABLE_TYPE_LONG,
    CTABLE_TYPE_WIDE,
    CTABLE_TYPE_FLOAT,
    CTABLE_TYPE_DOUBLE,
    CTABLE_TYPE_INET,
    CTABLE_TYPE_TCLOBJ,
    CTABLE_TYPE_KEY
};

// define ctable linked lists structures et al
typedef struct {
    struct ctable_baseRowStruct *next;
    struct ctable_baseRowStruct **prev;
    struct ctable_baseRowStruct **head;
} ctable_LinkedListNode;

// This must start off as a copy of the start of the generated ctable
typedef struct ctable_baseRowStruct {
    // hashEntry absolutely must be the first thing defined in the base row
    ctable_HashEntry     hashEntry;
#ifdef WITH_SHARED_TABLES
    cell_t		_row_cycle;
#endif
    // _ll_nodes absolutely must be the last thing defined in the base row
    ctable_LinkedListNode _ll_nodes[];
} ctable_BaseRow;

#include "jsw_slib.h"

// 
// macros for traversing ctable lists
// 
// in the safe version you can safely unlink the node you're currently "on"
//

#define CTABLE_LIST_FOREACH(list, var, i) \
    for ((var) = list; (var); (var) = (var)->_ll_nodes[i].next)

#define CTABLE_LIST_FOREACH_SAFE(list, var, tvar, i) \
    for ((var) = list; \
        (var) && ((tvar) = (var)->_ll_nodes[i].next); \
         var = tvar)

// define ctable search comparison types
// these terms must line up with the definition of searchTerms
//  in function ctable_ParseSearch
//  and the skip table in file ctable_search.c
// 
#define CTABLE_COMP_FALSE 0
#define CTABLE_COMP_TRUE 1
#define CTABLE_COMP_NULL 2
#define CTABLE_COMP_NOTNULL 3
#define CTABLE_COMP_LT 4
#define CTABLE_COMP_LE 5
#define CTABLE_COMP_EQ 6
#define CTABLE_COMP_NE 7
#define CTABLE_COMP_GE 8
#define CTABLE_COMP_GT 9
#define CTABLE_COMP_MATCH 10
#define CTABLE_COMP_NOTMATCH 11
#define CTABLE_COMP_MATCH_CASE 12
#define CTABLE_COMP_NOTMATCH_CASE 13
#define CTABLE_COMP_RANGE 14
#define CTABLE_COMP_IN 15

// These must line up with the CTABLE_COMP terms above
#define CTABLE_SEARCH_TERMS {"false", "true", "null", "notnull", "<", "<=", "=", "!=", ">=", ">", "match", "notmatch", "match_case", "notmatch_case", "range", "in", (char *)NULL}


// when setting, incr'ing, read_tabsepping, etc, we can control at the
// C level whether we want normal index behavior (if the field is
// indexed and it changes, it will be removed from the index under
// the old value and inserted under the new.
//
// if new is set, it will be inserted but not removed, this is used
// when creating new entries.
//
// if private is set, no index changes will be performed.  This is for
// setting up structures for comparisons and the like, i.e. stuff that
// should not be a row in the ctable.
//
// CTABLE_INDEX_FASTDELETE is only used by _delete_all_rows and passed to
// _delete.  if fastdelete is set, then the keys have been pre-deleted but
// otherwise it should be treated as normal
//
// CTABLE_INDEX_DESTROY_SHARED is only used by _delete_all_rows and passed to
// _delete.  if destroy is set, then nothing in shared memory is deleted
// because shared memory will be deleted anyway
//
// do not change, new and normal and 0 and 1 also expected from find_or_create
#define CTABLE_INDEX_DESTROY_SHARED -4
#define CTABLE_INDEX_FASTDELETE -2
#define CTABLE_INDEX_PRIVATE -1
#define CTABLE_INDEX_NORMAL 0
#define CTABLE_INDEX_NEW 1

// Forward reference to avoid a warning
struct ctableTable;
typedef int (*filterFunction_t)(Tcl_Interp *interp, struct ctableTable *ctable, void *vRow, Tcl_Obj *filter, int sequence);
typedef int (*fieldCompareFunction_t) (const ctable_BaseRow *row1, const ctable_BaseRow *row2);

// ctable sort struct - this controls everything about a sort
typedef struct {
    int *fields;
    int *directions;
    int nFields;
} CTableSort;

#define CTABLE_STRING_MATCH_ANCHORED 0
#define CTABLE_STRING_MATCH_UNANCHORED 1
#define CTABLE_STRING_MATCH_PATTERN 2

struct ctableSearchMatchStruct {
    // boyer-moore stuff
    int            *skip;
    unsigned char  *needle;
    int             occ[UCHAR_MAX+1];
    int             nlen;

    // universal stuff
    int             type;
    int             nocase;
};

// ctable search component struct - one for each "-compare" expression in a
// ctable search
typedef struct {
    void                    *clientData;
    void                    *row1;
    void                    *row2;
    void		    *row3;
    fieldCompareFunction_t   compareFunction;
    Tcl_Obj                **inListObj;
    void		   **inListRows;
    int                      inCount;
    int                      fieldID;
    int                      comparisonType;
} CTableSearchComponent;

// ctable search filter struct - one for each "-filter" expression in a
// ctable search
typedef struct {
    filterFunction_t  filterFunction;
    Tcl_Obj	     *filterObject;
} CTableSearchFilter;

#define CTABLE_SEARCH_ACTION_NONE 0
#define CTABLE_SEARCH_ACTION_GET 1
#define CTABLE_SEARCH_ACTION_ARRAY_GET 2
#define CTABLE_SEARCH_ACTION_ARRAY_GET_WITH_NULLS 3
#define CTABLE_SEARCH_ACTION_ARRAY 4
#define CTABLE_SEARCH_ACTION_ARRAY_WITH_NULLS 5
#define CTABLE_SEARCH_ACTION_WRITE_TABSEP 6
#define CTABLE_SEARCH_ACTION_TRANSACTION_ONLY 7
#define CTABLE_SEARCH_ACTION_CODE 8

// transactions are run after the operation is complete, so they don't modify
// a field that's being searched on
#define CTABLE_SEARCH_TRAN_NONE 0
#define CTABLE_SEARCH_TRAN_DELETE 1
#define CTABLE_SEARCH_TRAN_UPDATE 2

// Buffering types
#define CTABLE_BUFFER_DEFAULT -1
#define CTABLE_BUFFER_PROVISIONAL -2
#define CTABLE_BUFFER_NONE 0
#define CTABLE_BUFFER_DEFER 1

// Special "field" values for Search with skiplists
#define CTABLE_SEARCH_INDEX_NONE -1
#define CTABLE_SEARCH_INDEX_ANY -2

// If poll code is provided, the poll code will be run after this many rows
#define CTABLE_DEFAULT_POLL_INTERVAL 1024

// ctable search struct - this controls everything about a search
typedef struct {
    struct ctableTable                  *ctable;
    CTableSearchComponent               *components;
    CTableSearchFilter			*filters;
    char                                *pattern;
    int                                 *retrieveFields;

    Tcl_Obj                             *codeBody;
    Tcl_Obj                             *rowVarNameObj;
    Tcl_Obj                             *keyVarNameObj;

    int					 tranType;
    Tcl_Obj				*tranData;

    int                                  action;

    int					 bufferResults;

    int                                  nComponents;
    int					 nFilters;
    int                                  countMax;
    int                                  offset;
    int                                  limit;

    CTableSort                           sortControl;

    int                                  nRetrieveFields;

    int                                  noKeys;

    int					 pollInterval;
    Tcl_Obj				*pollCodeBody;
    int					 nextPoll;

    Tcl_Channel                          tabsepChannel;
    int                                  writingTabsepIncludeFieldNames;
    char				*sepstr;

    // count of matches during a search
    int                                  matchCount;

    // field that the search was requested to be indexed on.
    int					 reqIndexField;

    // -1 if brute force search, otherwise the component index that has
    // already been taken care of
    int                                  alreadySearched;

    // offsetLimit is calculated from offset and limit
    int                                  offsetLimit;

    // we use tran table to accumulate matching rows for sorting when
    // searching with sorting, and for completing a transaction after searching
    ctable_BaseRow                     **tranTable;

    // how to quote quotable strings and reptresent nulls in write_tabsep
    int					 quoteType;
    char				*nullString;

    // Unique search ID for memoization
    int					 sequence;
} CTableSearch;

typedef struct {
    CONST char              *name;
    Tcl_Obj                 *nameObj;
    char                   **propKeys;
    char                   **propValues;
    fieldCompareFunction_t   compareFunction;
    int                      number;
    int                      needsQuoting;
    int                      indexNumber;
    int                      unique;
    int			     canBeNull;
    enum ctable_types        type;
} ctable_FieldInfo;

typedef struct ctableCreatorTable {
    Tcl_HashTable     *registeredProcTablePtr;
    long unsigned int     nextAutoCounter;

    CONST char          **fieldNames;
    Tcl_Obj             **nameObjList;
    Tcl_Obj		**keyObjList;
    int                  *fieldList;
    int			 *publicFieldList;
    enum ctable_types    *fieldTypes;
    int                  *fieldsThatNeedQuoting;
    int			  keyField;

    ctable_FieldInfo    **fields;

    int                nFields;
    int		       nPublicFields;
    int                nLinkedLists;

    CONST char		   **filterNames;
    CONST filterFunction_t  *filterFunctions;
    int			     nFilters;

    void *(*make_empty_row) (struct ctableTable *ctable);
    void *(*find_row) (struct ctableTable *ctable, char *key);

    int (*set) (Tcl_Interp *interp, struct ctableTable *ctable, Tcl_Obj *dataObj, void *row, int field, int indexCtl);
    int (*set_null) (Tcl_Interp *interp, struct ctableTable *ctable, void *row, int field, int indexCtl);

    Tcl_Obj *(*get) (Tcl_Interp *interp, void *row, int field);
    CONST char *(*get_string) (const void *pointer, int field, int *lengthPtr, Tcl_Obj *utilityObj);

    Tcl_Obj *(*gen_list) (Tcl_Interp *interp, void *pointer);
    Tcl_Obj *(*gen_keyvalue_list) (Tcl_Interp *interp, void *pointer);
    Tcl_Obj *(*gen_nonnull_keyvalue_list) (Tcl_Interp *interp, void *pointer);
    int (*lappend_field) (Tcl_Interp *interp, Tcl_Obj *destListObj, void *p, int field);
    int (*lappend_field_and_name) (Tcl_Interp *interp, Tcl_Obj *destListObj, void *p, int field);
    int (*lappend_nonnull_field_and_name) (Tcl_Interp *interp, Tcl_Obj *destListObj, void *p, int field);
    void (*dstring_append_get_tabsep) (CONST char *key, void *pointer, int *fieldNums, int nFields, Tcl_DString *dsPtr, int noKey, char *sepstr, int quoteType, char *nullString);

    int (*array_set) (Tcl_Interp *interp, Tcl_Obj *arrayNameObj, void *row, int field);
    int (*array_set_with_nulls) (Tcl_Interp *interp, Tcl_Obj *arrayNameObj, void *row, int field);

    int (*search_compare) (Tcl_Interp *interp, CTableSearch *searchControl, void *pointer);
    int (*sort_compare) (void *clientData, const void *pointer1, const void *pointer2);

    void (*delete) (struct ctableTable *ctable, void *row, int indexCtl);

    int (*command) (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[]);

#ifdef SANITY_CHECKS
    void (*sanity_check_pointer)(struct ctableTable *ctable, void *ptr, int indexCtl, char *where);
#endif
    LIST_HEAD(instances, ctableTable) instances;
} ctable_CreatorTable;

typedef struct ctableTable {
    ctable_CreatorTable                 *creator;
    ctable_HashTable                    *keyTablePtr;

    jsw_skip_t                         **skipLists;
    ctable_BaseRow                      *ll_head;

    int                                  autoRowNumber;
    int                                  destroying;
    int					 searching;
    char				*nullKeyValue;
#ifdef WITH_SHARED_TABLES
    int					 was_locked;
    char				*emptyString;
    char			       **defaultStrings;

    int					 share_type;
    int					 share_panic;
    char				*share_name;
    char				*share_file;
    shm_t                               *share;
    size_t				 share_min_free;
// reader-only
    volatile struct ctableTable		*share_ctable;
    volatile reader			*my_reader;
#endif
    Tcl_Command                          commandInfo;
    long                                 count;
    LIST_ENTRY(ctableTable)              instance;
} CTable;

CTABLE_INTERNAL int
ctable_CreateIndex (Tcl_Interp *interp, CTable *ctable, int fieldNum, int depth);

// Helpers
#define is_hidden_obj(obj) (Tcl_GetString(obj)[0] == '_')
#define is_hidden_name(fieldNames,field) ((fieldNames)[field][0] == '_')
#define is_hidden_field(table,field) is_hidden_name((table)->fieldNames,field)
#define is_key_field(table,field,noKeys) ((noKeys) == 0 && strcmp("_key",(table)->fieldNames[field]) == 0)

// Values for share_type
#ifdef WITH_SHARED_TABLES
# define CTABLE_SHARED_NONE 0
# define CTABLE_SHARED_MASTER 1
# define CTABLE_SHARED_READER 2
#endif

#endif
