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
    Tcl_HashEntry *hashEntry;
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
#define CTABLE_COMP_MATCH_CASE 11
#define CTABLE_COMP_RANGE 12

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
    int nFields;
    int *fields;
    int *directions;
};

#define CTABLE_STRING_MATCH_ANCHORED 0
#define CTABLE_STRING_MATCH_UNANCHORED 1
#define CTABLE_STRING_MATCH_PATTERN 2

struct ctableSearchMatchStruct {
    int             type;
    int             nocase;

    // boyer-moore stuff
    int            *skip;
    int             occ[UCHAR_MAX+1];
    int             nlen;
    unsigned char  *needle;
};

// ctable search component struct - one for each search expression in a
// ctable search
struct ctableSearchComponentStruct {
    int             fieldID;
    int             comparisonType;
    Tcl_Obj        *comparedToObject;
    char           *comparedToString;
    int             comparedToStringLength;
    void           *clientData;
    void           *row1;
    void           *row2;
};

// ctable search struct - this controls everything about a search
struct ctableSearchStruct {
    struct ctableTable                  *ctable;
    int                                  nComponents;
    struct ctableSearchComponentStruct  *components;

    int                                  countOnly;
    int                                  countMax;
    int                                  offset;
    int                                  limit;

    char                                *pattern;

    struct ctableSortStruct              sortControl;

    int                                 *retrieveFields;
    int                                  nRetrieveFields;

    int                                  noKeys;
    Tcl_Obj                             *codeBody;
    Tcl_Obj                             *varNameObj;
    Tcl_Obj                             *keyVarNameObj;
    int                                  useArrayGet;
    int                                  useArrayGetWithNulls;
    int                                  useGet;

    Tcl_Channel                          tabsepChannel;
    int                                  writingTabsep;
    int                                  writingTabsepIncludeFieldNames;

    // setting up these for the field_comp routines to go after the
    // rows we want in skiplists
    void                                 *row1;
    void                                 *row2;
};

struct ctableFieldInfo {
    CONST char              *name;
    Tcl_Obj                 *nameObj;
    int                      number;
    enum ctable_types        type;
    int                      needsQuoting;
    fieldCompareFunction_t   compareFunction;
    int                      indexNumber;
};

struct ctableCreatorTable {
    Tcl_HashTable     *registeredProcTablePtr;
    long unsigned int  nextAutoCounter;

    int                nFields;
    int                nLinkedLists;

    CONST char       **fieldNames;
    Tcl_Obj          **nameObjList;
    int               *fieldList;
    enum ctable_types *fieldTypes;
    int               *fieldsThatNeedQuoting;

    struct ctableFieldInfo **fields;

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
    int (*sort_compare) (void *clientData, const void *hashEntryPtr1, const void *hashEntryPtr2);
};

struct ctableTable {
    struct ctableCreatorTable           *creatorTable;
    Tcl_HashTable                       *keyTablePtr;
    Tcl_Command                          commandInfo;
    long                                 count;

    jsw_skip_t                         **skipLists;
    struct ctable_baseRow               *ll_head;
    int                                  nLinkedLists;
};


// extern int ctable_SetupAndPerformSearch (Tcl_Interp *interp, Tcl_Obj *CONST objv[], int objc, struct ctableTable *ctable);

extern int
ctable_CreateIndex (Tcl_Interp *interp, struct ctableTable *ctable, int fieldNum, int depth);

#endif
