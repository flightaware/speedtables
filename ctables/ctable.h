/*
 * ctable.h - include file for ctables
 *
 * $Id$
 *
 */

#include <tcl.h>
#include <assert.h>
#include <string.h>
#include <stdlib.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/ethernet.h>

#ifdef WITH_PGTCL
#include <libpq-fe.h>
#endif

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

// ctable sort struct - this controls everything about a sort
struct ctableSortStruct {
    int nFields;
    int *fields;
};

// ctable search component struct - one for each search expression in a
// ctable search
struct ctableSearchComponentStruct {
    int             fieldID;
    int             comparisonType;
    Tcl_Obj        *comparedToObject;
};

// ctable search struct - this controls everything about a search
struct ctableSearchStruct {
    struct ctableTable                  *ctable;
    int                                  nComponents;
    struct ctableSearchComponentStruct **components;

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
    int                                  useArraySet;
    int                                  useListSet;

    Tcl_Channel                          tabsepChannel;
    int                                  writingTabsep;
};

struct ctableCreatorTable {
    Tcl_HashTable     *registeredProcTablePtr;
    long unsigned int  nextAutoCounter;
    CONST char       **fieldNames;
    Tcl_Obj          **nameObjList;
    int (*search_compare) (Tcl_Interp *interp, struct ctableSearchStruct *searchControl, Tcl_HashEntry *hashEntryPtr);
    int (*sort_compare) (void *clientData, const void *hashEntryPtr1, const void *hashEntryPtr2);
    Tcl_Obj *(*get_field_obj) (Tcl_Interp *interp, void *pointer, int field);
    void (*dstring_append_get_tabsep) (char *key, void *pointer, int *fieldNums, int nFields, Tcl_DString *dsPtr, int noKey);
    Tcl_Obj *(*gen_list) (Tcl_Interp *interp, void *pointer);
    Tcl_Obj *(*gen_keyvalue_list) (Tcl_Interp *interp, void *pointer);
};

struct ctableTable {
    struct ctableCreatorTable *creatorTable;
    Tcl_HashTable             *keyTablePtr;
    Tcl_Command                commandInfo;
    long                       count;
};


// extern int ctable_SetupAndPerformSearch (Tcl_Interp *interp, Tcl_Obj *CONST objv[], int objc, struct ctableTable *ctable);

