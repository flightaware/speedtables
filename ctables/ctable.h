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
#include "queue.h"

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

// ctable search component struct - one for each search expression in a
// ctable search
struct ctableSearchComponentStruct {
    int             fieldID;
    int             comparisonType;
    Tcl_Obj        *comparedToObject;
};

// ctable search struct - this controls everything about a search
struct ctableSearchStruct {
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
    Tcl_Channel                          tabsepChannel;
    int                                  writingTabsep;
};

// ctable sort struct - this controls everything about a sort
struct ctableSortStruct {
    int nFields;
    int *fields;
};

