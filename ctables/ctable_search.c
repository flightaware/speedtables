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
    int                                  offset;
    int                                  limit;
    int                                  nSortFields;
    char                                *pattern;
    struct ctableSortStruct              sortControl;
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

    int          sortCount = 0;

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

    if ((search->nSortFields > 0) && (!countOnly)) {
	hashSortTable = (Tcl_HashEntry **)ckalloc (sizeof (Tcl_HashEntry *) * count);
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

        /* Are we not sorting? */
	if (hashSortTable == NULL) {
	    /* if we haven't met the start point, blow it off */
	    if (++matchCount < offset) continue;

	    if (matchCount >= limit) {
	        return TCL_OK;
	    }

	    /* match, handle action or tabsep write */
	} else {
	    /* We are sorting, grab it, we gotta sort before we can run
	     * against start and limit and stuff */
	    assert (sortCount < count);
	    // printf ("filling sort table %d -> hash entry %lx (%s)\n", sortCount, (long unsigned int)hashEntry, key);
	    hashSortTable[sortCount++] = hashEntry;

	    qsort_r (hashSortTable, sortCount, sizeof (Tcl_HashEntry *), &search->sortControl, ${table}_sort_compare);

	    for (sortIndex = 0; sortIndex < sortCount; sortIndex++) {
		  key = Tcl_GetHashKey (tbl_ptr->keyTablePtr, hashSortTable[sortIndex]);

		  if (Tcl_ObjSetVar2 (interp, objv[3], (Tcl_Obj *)NULL, Tcl_NewStringObj (key, -1), TCL_LEAVE_ERR_MSG) == (Tcl_Obj *) NULL) {
		    search_err:
		      ckfree ((void *)hashSortTable);
		      ckfree ((void *)search->sortControl.fields);
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
	}
    }
}

int
ctable_SetupSearch (Tcl_Interp *interp, Tcl_Obj **objv, int objc, struct ctableSearchStruct *search) {
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
    int             searchTerm = 0;

    static CONST char *searchOptions[] = {"-sort", "-fields", "-glob" "-regexp", "-compare", "-countOnly", "-offset", "-limit", "-code", "-write_tabsep", (char *)NULL};

    enum searchOptions {SEARCH_OPT_SORT, SEARCH_OPT_FIELDS, SEARCH_OPT_GLOB, SEARCH_OPT_REGEXP, SEARCH_OPT_COMPARE, SEARCH_OPT_COUNTONLY, SEARCH_OPT_OFFSET, SEARCH_OPT_LIMIT, SEARCH_OPT_CODE, SEARCH_OPT_WRITE_TABSEP};

    if (objc < 2) {
      wrong_args:
	Tcl_WrongNumArgs (interp, 2, objv, "?-sort {field1 {field2 desc}}? ?-fields fieldList? ?-glob pattern? ?-regexp pattern? ?-compare list? ?-contOnly 0|1? ?-offset offset? ?-limit limit? ?-code codeBody? ?-write_tabsep channel?");
	return TCL_ERROR;
    }

    for (i = 2; i < objc; ) {
	if (Tcl_GetIndexFromObj (interp, objv[i++], searchTerms, "search option", TCL_EXACT, &searchTerm) != TCL_OK) {
	    return TCL_ERROR;
	}

	//  all the arguments require one parameter
	if (i >= objc) {
	    goto wrong_args;
	}

	switch (searchTerm) {
	  case SEARCH_OPT_SORT: {
	    if (Tcl_ListObjGetElements (interp, objv[i++], &fieldsObjc, &fieldsObjv) == TCL_ERROR) {
	      return TCL_ERROR;
	    }

	    search->sortControl.nFields = fieldsObjc;
	    search->sortControl.fields = (int *)ckalloc (sizeof (int) * fieldsObjc);
	    for (i = 0; i < fieldsObjc; i++) {
		if (Tcl_GetIndexFromObj (interp, fieldsObjv[i], ${table}_fields, "field", TCL_EXACT, &search->sortControl.fields[i]) != TCL_OK) {
		    ckfree ((void *)search->sortControl.fields);
		    return TCL_ERROR;
		  }
	    }
	    break;
	  }

	  case SEARCH_OPT_FIELDS: {
	      // the fields they want us to retrieve
	  }

	  case SEARCH_OPT_INCLUDE_KEY: {
	      // set to 0 if you don't want the key included
	  }

	  case SEARCH_OPT_GLOB: {
	  }

	  case SEARCH_OPT_REGEXP: {
	  }

	  case SEARCH_OPT_COMPARE: {
	  }

	  case SEARCH_OPT_COUNTONLY: {
	  }

	  case SEARCH_OPT_OFFSET: {
	  }

	  case SEARCH_OPT_LIMIT: {
	  }

	  case SEARCH_OPT_CODE: {
	  }

	  case SEARCH_OPT_WRITE_TABSEP: {
	  }
	}
    }


    if (objc == 6) {
      pattern = Tcl_GetString (objv[4]);
      codeIndex = 5;
    }




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
