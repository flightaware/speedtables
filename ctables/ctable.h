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

#ifndef CTABLE_NO_SYS_LIMITS
#include <sys/limits.h>
#endif

#ifdef WITH_PGTCL
#include <libpq-fe.h>
#endif

#include "speedtables.h"

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
    CTABLE_TYPE_TCLOBJ
};

// define ctable linked lists structures et al
typedef struct {
    struct ctable_baseRowStruct *next;
    struct ctable_baseRowStruct **prev;
    struct ctable_baseRowStruct **head;
} ctable_LinkedListNode;

typedef struct ctable_baseRowStruct {
    // hashEntry absolutely must be the first thing defined in the base row
    ctable_HashEntry     hashEntry;

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
//  in function ctable_ParseSearch in file ctable_search.c
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
// do not change, new and normal and 0 and 1 also expected from find_or_create
#define CTABLE_INDEX_PRIVATE -1
#define CTABLE_INDEX_NORMAL 0
#define CTABLE_INDEX_NEW 1

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

// ctable search component struct - one for each search expression in a
// ctable search
typedef struct {
    void                    *clientData;
    void                    *row1;
    void                    *row2;
    fieldCompareFunction_t   compareFunction;
    Tcl_Obj                **inListObj;
    int                      inCount;
    int                      fieldID;
    int                      comparisonType;
} CTableSearchComponent;

#define CTABLE_SEARCH_ACTION_NONE 0
#define CTABLE_SEARCH_ACTION_GET 1
#define CTABLE_SEARCH_ACTION_ARRAY_GET 2
#define CTABLE_SEARCH_ACTION_ARRAY_GET_WITH_NULLS 3
#define CTABLE_SEARCH_ACTION_ARRAY 4
#define CTABLE_SEARCH_ACTION_ARRAY_WITH_NULLS 5
#define CTABLE_SEARCH_ACTION_WRITE_TABSEP 6
#define CTABLE_SEARCH_ACTION_COUNT_ONLY 7

// ctable search struct - this controls everything about a search
typedef struct {
    struct ctableTable                  *ctable;
    CTableSearchComponent               *components;
    char                                *pattern;
    int                                 *retrieveFields;

    Tcl_Obj                             *codeBody;
    Tcl_Obj                             *varNameObj;
    Tcl_Obj                             *keyVarNameObj;

    // setting up these for the field_comp routines to go after the
    // rows we want in skiplists
    void                                 *row1;
    void                                 *row2;

    int                                  endAction;

    int                                  nComponents;
    int                                  countMax;
    int                                  offset;
    int                                  limit;

    CTableSort                           sortControl;

    int                                  nRetrieveFields;

    int                                  noKeys;

    Tcl_Channel                          tabsepChannel;
    int                                  writingTabsepIncludeFieldNames;

    // count of matches during a search
    int                                  matchCount;

    // 0 if brute force search, 1 if we're skipping via skip list and range
    int                                  tailoredWalk;

    // offsetLimit is calculated from offset and limit
    int                                  offsetLimit;

    // we use sort table to accumulate matching rows for sorting when
    // searching with sorting
    ctable_BaseRow                     **sortTable;
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
    enum ctable_types        type;
} ctable_FieldInfo;

typedef struct ctableCreatorTable {
    Tcl_HashTable     *registeredProcTablePtr;
    long unsigned int     nextAutoCounter;

    CONST char          **fieldNames;
    Tcl_Obj             **nameObjList;
    Tcl_Obj		**keyObjList;
    int                  *fieldList;
    enum ctable_types    *fieldTypes;
    int                  *fieldsThatNeedQuoting;

    ctable_FieldInfo    **fields;

    int                nFields;
    int                nLinkedLists;

    void *(*make_empty_row) ();
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
    void (*dstring_append_get_tabsep) (char *key, void *pointer, int *fieldNums, int nFields, Tcl_DString *dsPtr, int noKey);

    int (*array_set) (Tcl_Interp *interp, Tcl_Obj *arrayNameObj, void *row, int field);
    int (*array_set_with_nulls) (Tcl_Interp *interp, Tcl_Obj *arrayNameObj, void *row, int field);

    int (*search_compare) (Tcl_Interp *interp, CTableSearch *searchControl, void *pointer, int tailoredWalk);
    int (*sort_compare) (void *clientData, const void *pointer1, const void *pointer2);
    void (*delete) (struct ctableTable *ctable, void *row, int indexCtl);

    int (*command) (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[]);
} ctable_CreatorTable;

typedef struct ctableTable {
    ctable_CreatorTable                 *creator;
    ctable_HashTable                    *keyTablePtr;

    jsw_skip_t                         **skipLists;
    ctable_BaseRow                      *ll_head;

    int                                  autoRowNumber;
    Tcl_Command                          commandInfo;
    long                                 count;
} CTable;

extern int
ctable_CreateIndex (Tcl_Interp *interp, CTable *ctable, int fieldNum, int depth);

#endif
