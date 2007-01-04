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
struct ctable_linkedListNodeStruct {
    struct ctable_baseRow *next;
    struct ctable_baseRow **prev;
    struct ctable_baseRow **head;
};

struct ctable_baseRow {
    ctable_HashEntry *hashEntry;
    struct ctable_linkedListNodeStruct _ll_nodes[];
};

#include "jsw_slib.h"

// 
// macros for traversing ctable lists
// 
// in the safe version you can safely unlink the node you're currently "on"
//

#define CTABLE_LIST_FOREACH(list, var, i) \
    for ((var) = list; (var); (var) = (var)->_ll_nodes[i].next)

#define CTABLE_LIST_FOREACH_SAFE(ctable, var, tvar, i) \
    for ((var) = list; \
        (var) && ((tvar) = (var)->ll_nodes[i].next, 1); \
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

typedef int (*fieldCompareFunction_t) (const struct ctable_baseRow *row1, const struct ctable_baseRow *row2);

// ctable sort struct - this controls everything about a sort
struct ctableSortStruct {
    int *fields;
    int *directions;
    int nFields;
};

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
struct ctableSearchComponentStruct {
    void                    *clientData;
    void                    *row1;
    void                    *row2;
    fieldCompareFunction_t   compareFunction;
    int                      fieldID;
    int                      comparisonType;
};

// ctable search struct - this controls everything about a search
struct ctableSearchStruct {
    struct ctableTable                  *ctable;
    struct ctableSearchComponentStruct  *components;
    char                                *pattern;
    int                                 *retrieveFields;

    Tcl_Obj                             *codeBody;
    Tcl_Obj                             *varNameObj;
    Tcl_Obj                             *keyVarNameObj;

    // setting up these for the field_comp routines to go after the
    // rows we want in skiplists
    void                                 *row1;
    void                                 *row2;

    int                                  nComponents;
    int                                  countOnly;
    int                                  countMax;
    int                                  offset;
    int                                  limit;

    struct ctableSortStruct              sortControl;

    int                                  nRetrieveFields;

    int                                  noKeys;
    int                                  useArrayGet;
    int                                  useArrayGetWithNulls;
    int                                  useGet;

    Tcl_Channel                          tabsepChannel;
    int                                  writingTabsep;
    int                                  writingTabsepIncludeFieldNames;

    // count of matches during a search
    int                                  matchCount;

    // 0 if brute force search, 1 if we're skipping via skip list and range
    int                                  tailoredWalk;

    // offsetLimit is calculated from offset and limit
    int                                  offsetLimit;

    // we use sort table to accumulate matching rows for sorting when
    // searching with sorting
    struct ctable_baseRow              **sortTable;
};

struct ctableFieldInfo {
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
};

struct ctableCreatorTable {
    ctable_HashTable     *registeredProcTablePtr;
    long unsigned int     nextAutoCounter;

    CONST char          **fieldNames;
    Tcl_Obj             **nameObjList;
    int                  *fieldList;
    enum ctable_types    *fieldTypes;
    int                  *fieldsThatNeedQuoting;

    struct ctableFieldInfo **fields;

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

    int (*search_compare) (Tcl_Interp *interp, struct ctableSearchStruct *searchControl, void *pointer, int tailoredWalk);
    int (*sort_compare) (void *clientData, const void *pointer1, const void *pointer2);
};

struct ctableTable {
    struct ctableCreatorTable           *creatorTable;
    ctable_HashTable                    *keyTablePtr;

    jsw_skip_t                         **skipLists;
    struct ctable_baseRow               *ll_head;

    int                                  nLinkedLists;
    int                                  autoRowNumber;
    Tcl_Command                          commandInfo;
    long                                 count;
};

extern int
ctable_CreateIndex (Tcl_Interp *interp, struct ctableTable *ctable, int fieldNum, int depth);

#endif
