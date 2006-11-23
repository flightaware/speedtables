/*
 *
 *
 *
 *
 * $Id$
 *
 */
#include <tcl.h>

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

struct ctableSearchComponentStruct {
    int             fieldID;
    int             comparisonType;
    Tcl_Obj        *comparedToObject;
};

struct ctableSearchStruct {
    int                                  nComponents;
    struct ctableSearchComponentStruct **components;
    int                                  countOnly;
    int                                  countMax;
    int                                  start;
    int                                  offset;
    int                                  nSortFields;
    char                                *pattern;
};

static int
ctable_ParseSearch (Tcl_Interp *interp, Tcl_Obj *componentListObj, CONST char **fieldNames, struct ctableSearchStruct *search) {
    Tcl_Obj    **componentList;
    int          componentIdx;
    int          componentListCount;

    Tcl_Obj    **termList;
    int          term;
    int          termListCount;

    int          field;

    int          sortCount;

    struct ctableSearchComponentStruct **components;
    struct ctableSearchComponentStruct  *component;
    
    // these terms must line up with the CTABLE_COMP_* defines
    static CONST char *searchTerms[] = {"false", "true", "null" "notnull", "<", "<=", "=", "!=", ">=", ">", (char *)NULL};

    if (Tcl_ListObjGetElements (interp, componentListObj, &componentListCount, &componentList) == TCL_ERROR) {
        return TCL_ERROR;
    }

    if (componentListCount == 0) {
        search->components = NULL;
	return TCL_OK;
    }

    search->nComponents = componentListCount;

    components = (struct ctableSearchComponentStruct **)ckalloc (componentListCount * sizeof (struct ctableSearchComponentStruct));

    search->components = components;

    for (componentIdx = 0; componentIdx < componentListCount; componentIdx++) {
        int term;

	if (Tcl_ListObjGetElements (interp, componentList[componentIdx], &termListCount, &termList) == TCL_ERROR) {
	  err:
	    ckfree ((char *)search);
	    ckfree ((char *)components);
	    return TCL_ERROR;
	}

	if (termListCount < 2 || termListCount > 3) {
	    // would be cool to support regexps here too
	    Tcl_WrongNumArgs (interp, 0, termList, "term field ?value?");
	    goto err;
	}

	if (Tcl_GetIndexFromObj (interp, termList[0], searchTerms, "term", TCL_EXACT, &term) != TCL_OK) {
	    goto err;
	}

	if (Tcl_GetIndexFromObj (interp, termList[1], fieldNames, "field", TCL_EXACT, &field) != TCL_OK) {
	    goto err;
	}

	component = components[componentIdx];

	component->comparisonType = term;
	component->fieldID = field;

	if (field == CTABLE_COMP_FALSE || field == CTABLE_COMP_TRUE || field == CTABLE_COMP_NULL || field == CTABLE_COMP_NOTNULL) {
	    component->comparedToObject = NULL;
	}  else {
	    component->comparedToObject = termList[2];
	}
    }

    return TCL_OK;
}


//
// ctable_PerformSearch - 
//
//
//
static int
ctable_PerformSearch (Tcl_Interp *interp, Tcl_HashTable *keyTablePtr, struct ctableSearchStruct *search, int *search_compare (Tcl_Interp *interp, void *clientData, const void *hashEntryPtr), int count) {
    Tcl_Obj    **componentList;
    int          componentIdx;
    int          componentListCount;

    Tcl_Obj    **termList;
    int          term;
    int          termListCount;

    int          field;
    int          maxMatches = 0;

    Tcl_HashEntry **hashSortTable = NULL;

    if (count == 0) {
        return TCL_OK;
    }

    if (search->limit > 0) {
	maxMatches = search->limit;
    } else {
	maxMatches = count;
    }

    if ((search->nSortFields > 0) && (!countOnly)) {
	hashSortTable = (Tcl_HashEntry **)ckalloc (sizeof (Tcl_HashEntry *) * maxMatches);
    }

    /* Build up a table of ptrs to hash entries of rows of the table.
     * Optional match pattern on the primary key means we may end up
     * with fewer than the total number.
    */
    for (hashEntry = Tcl_FirstHashEntry (tbl_ptr->keyTablePtr, &hashSearch); hashEntry != (Tcl_HashEntry *) NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {

	key = Tcl_GetHashKey (tbl_ptr->keyTablePtr, hashEntry);

	if ((search->pattern != (char *) NULL) && (!Tcl_StringCaseMatch (key, search->pattern, 1))) continue;

	compareResult = (*searchcompare) (interp, search, hashEntry);
	if (compareResult == TCL_CONTINUE) {
	    continue;
	}

	if (compareResult == TCL_ERROR) {
	    if (hashSortTable != NULL) {
		ckfree (hashSortTable);
	    }
	    return TCL_ERROR;
	}

	/* It's a Match */

        if (hashSortTable != NULL) {
	    assert (sortCount < count);
	    // printf ("filling sort table %d -> hash entry %lx (%s)\n", sortCount, (long unsigned int)hashEntry, key);
	    hashSortTable[sortCount++] = hashEntry;
	}

    }
}


      case OPT_SEARCH: {
	  Tcl_HashSearch  hashSearch;
	  char           *pattern = (char *) NULL;
	  char           *key;
	  int             codeIndex = 4;
	  Tcl_HashEntry **hashSortTable;
	  int             sortCount = 0;
	  int             sortIndex;
	  int             fieldsObjc;
	  int             i;
	  Tcl_Obj       **fieldsObjv;
	  struct ctableSortStruct sortControl;

	  if ((objc < 5) || (objc > 6)) {
	      Tcl_WrongNumArgs (interp, 2, objv, "fieldList varName ?pattern? codeBody");
	      return TCL_ERROR;
	  }

	  if (objc == 6) {
	      pattern = Tcl_GetString (objv[4]);
	      codeIndex = 5;
	  }

	  if (Tcl_ListObjGetElements (interp, objv[2], &fieldsObjc, &fieldsObjv) == TCL_ERROR) {
	      return TCL_ERROR;
	  }

	  sortControl.nFields = fieldsObjc;
	  sortControl.fields = (int *)ckalloc (sizeof (int) * fieldsObjc);
	  for (i = 0; i < fieldsObjc; i++) {
	      if (Tcl_GetIndexFromObj (interp, fieldsObjv[i], ${table}_fields, "field", TCL_EXACT, &sortControl.fields[i]) != TCL_OK) {
	          ckfree ((void *)sortControl.fields);
		  return TCL_ERROR;
	      }
	  }

	  hashSortTable = (Tcl_HashEntry **)ckalloc (sizeof (Tcl_HashEntry *) * tbl_ptr->count);

          /* Build up a table of ptrs to hash entries of rows of the table.
	   * Optional match pattern on the primary key means we may end up
	   * with fewer than the total number.
	   */
	  for (hashEntry = Tcl_FirstHashEntry (tbl_ptr->keyTablePtr, &hashSearch); hashEntry != (Tcl_HashEntry *) NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {
	      key = Tcl_GetHashKey (tbl_ptr->keyTablePtr, hashEntry);
	      if ((pattern != (char *) NULL) && (!Tcl_StringCaseMatch (key, pattern, 1))) continue;

	      assert (sortCount < tbl_ptr->count);
// printf ("filling sort table %d -> hash entry %lx (%s)\n", sortCount, (long unsigned int)hashEntry, key);
	      hashSortTable[sortCount++] = hashEntry;
	}

	qsort_r (hashSortTable, sortCount, sizeof (Tcl_HashEntry *), &sortControl, ${table}_sort_compare);

	for (sortIndex = 0; sortIndex < sortCount; sortIndex++) {
	      key = Tcl_GetHashKey (tbl_ptr->keyTablePtr, hashSortTable[sortIndex]);

	      if (Tcl_ObjSetVar2 (interp, objv[3], (Tcl_Obj *)NULL, Tcl_NewStringObj (key, -1), TCL_LEAVE_ERR_MSG) == (Tcl_Obj *) NULL) {
	        search_err:
	          ckfree ((void *)hashSortTable);
		  ckfree ((void *)sortControl.fields);
	          return TCL_ERROR;
	      }

	      switch (Tcl_EvalObjEx (interp, objv[codeIndex], 0)) {
	        case TCL_ERROR:
		  Tcl_AppendResult (interp, " while processing foreach code body", (char *) NULL);
		  goto search_err;

		case TCL_OK:
		case TCL_CONTINUE:
		  break;

		case TCL_BREAK:
		case TCL_RETURN:
		  goto search_err;
	      }
	  }
	  ckfree ((void *)hashSortTable);
	  ckfree ((void *)sortControl.fields);
	  return TCL_OK;
      }
