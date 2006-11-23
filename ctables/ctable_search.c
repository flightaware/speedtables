/*
 *
 *
 *
 *
 * $Id$
 *
 */

#include "ctable.h"

/*
 * ctable_ParseFieldList - given a Tcl list object and an array of pointers
 * to field names, install a field count into an integer pointer passed
 * in and allocate an array of integers for the corresponding field indexes.
 *
 * It is up to the caller to free the memory pointed to through the
 * fieldList argument.
 *
 * return TCL_OK if all went according to plan, else TCL_ERROR.
 *
 */
int
ctable_ParseFieldList (Tcl_Interp *interp, Tcl_Obj *fieldListObj, CONST char **fieldNames, int **fieldList, int *fieldCountPtr) {
    int             nFields;
    Tcl_Obj       **fieldsObjv;
    int             i;

    // the fields they want us to retrieve
    if (Tcl_ListObjGetElements (interp, fieldListObj, &nFields, &fieldsObjv) == TCL_ERROR) {
      return TCL_ERROR;
    }

    *fieldCountPtr = nFields;
    *fieldList = (int *)ckalloc (sizeof (int) * nFields);

    for (i = 0; i < nFields; i++) {
	if (Tcl_GetIndexFromObj (interp, fieldsObjv[i], fieldNames, "field", TCL_EXACT, fieldList[i]) != TCL_OK) {
	    ckfree ((void *)(*fieldList));
	    return TCL_ERROR;
	  }
    }
    return TCL_OK;
}

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
ctable_PerformSearch (Tcl_Interp *interp, Tcl_HashTable *keyTablePtr, struct ctableSearchStruct *search, int count) {
    Tcl_Obj        **componentList;
    int              componentIdx;
    int              componentListCount;

    Tcl_HashEntry   *hashEntry;
    Tcl_HashSearch   hashSearch;
    char            *key;

    Tcl_Obj        **termList;
    int              term;
    int              termListCount;

    int              field;
    int              compareResult;
    int              maxMatches = 0;
    int              matchCount = 0;

    Tcl_HashEntry **hashSortTable = NULL;

    if (count == 0) {
        return TCL_OK;
    }

    if ((search->sortControl.nFields > 0) && (!search->countOnly)) {
	hashSortTable = (Tcl_HashEntry **)ckalloc (sizeof (Tcl_HashEntry *) * count);
    }

    /* Build up a table of ptrs to hash entries of rows of the table.
     * Optional match pattern on the primary key means we may end up
     * with fewer than the total number.
    */
    for (hashEntry = Tcl_FirstHashEntry (keyTablePtr, &hashSearch); hashEntry != (Tcl_HashEntry *) NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {

	key = Tcl_GetHashKey (keyTablePtr, hashEntry);

	if ((search->pattern != (char *) NULL) && (!Tcl_StringCaseMatch (key, search->pattern, 1))) continue;

	compareResult = (*search->search_compare) (interp, search, hashEntry);
	if (compareResult == TCL_CONTINUE) {
	    continue;
	}

	if (compareResult == TCL_ERROR) {
	    if (hashSortTable != NULL) {
		ckfree ((void *)hashSortTable);
	    }
	    return TCL_ERROR;
	}

	/* It's a Match */

        /* Are we not sorting? */
	if (hashSortTable == NULL) {
	    /* if we haven't met the start point, blow it off */
	    if (++matchCount < search->offset) continue;

	    if (matchCount >= search->limit) {
	        return TCL_OK;
	    }

	    /* match, handle action or tabsep write */
	} else {
	    /* We are sorting, grab it, we gotta sort before we can run
	     * against start and limit and stuff */
	    assert (matchCount < count);
	    // printf ("filling sort table %d -> hash entry %lx (%s)\n", matchCount, (long unsigned int)hashEntry, key);
	    hashSortTable[matchCount++] = hashEntry;

	    qsort_r (hashSortTable, matchCount, sizeof (Tcl_HashEntry *), &search->sortControl, search->sort_compare);

	    for (sortIndex = 0; sortIndex < matchCount; sortIndex++) {
		  key = Tcl_GetHashKey (keyTablePtr, hashSortTable[sortIndex]);

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
    return TCL_OK;
}

static int
ctable_SetupSearch (Tcl_Interp *interp, Tcl_Obj **objv, int objc, struct ctableSearchStruct *search, CONST char **fieldNames) {
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

    // initialize search control structure
    search->nComponents = 0;
    search->components = NULL;
    search->countOnly = 0;
    search->countMax = 0;
    search->offset = 0;
    search->limit = 0;
    search->pattern = NULL;
    search->sortControl.fields = NULL;
    search->sortControl.nFields = 0;
    search->retrieveFields = NULL;
    search->nRetrieveFields = 0;
    search->noKeys = 0;
    search->codeBody = NULL;
    search->writingTabsep = 0;

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
	    // the fields they want us to sort on
            if (ctable_ParseFieldList (interp, objv[i++], fieldNames, &search->sortControl.fields, &search->sortControl.nFields) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing sort options", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_FIELDS: {
	    // the fields they want us to retrieve
	    if (ctable_ParseFieldList (interp, objv[i++], fieldNames, &search->retrieveFields, &search->nRetrieveFields) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search fields", (char *) NULL);
	        return TCL_ERROR;
	    }

	    break;
	  }

	  case SEARCH_OPT_INCLUDE_KEY: {
	    if (Tcl_GetBooleanFromObj (interp, objv[i++], &search->noKeys) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search noKeys", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_GLOB: {
	    search->pattern = Tcl_GetString (objv[i++);
	    break;
	  }

	  case SEARCH_OPT_REGEXP: {
	    Tcl_AppendResult (interp, "regexp not implemented yet", (char *) NULL);
	    return TCL_ERROR;
	  }

	  case SEARCH_OPT_COMPARE: {
	    if (ctable_ParseSearch (interp, objv[i++], fieldNames, search) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search compare", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_COUNTONLY: {
	    if (Tcl_GetBooleanFromObj (interp, objv[i++], &search->countOnly) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search countOnly", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_OFFSET: {
	    if (Tcl_GetIntFromObj (interp, objv[i++], &search->offset) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search offset", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_LIMIT: {
	    if (Tcl_GetIntFromObj (interp, objv[i++], &search->limit) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search limit", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_CODE: {
	      search->codeBody = objv[i++];
	      break;
	  }

	  case SEARCH_OPT_WRITE_TABSEP: {
	    if ((search->tabsepChannel = Tcl_GetChannel (interp, Tcl_GetString (objv[i++]), TCL_WRITABLE)) == NULL) {
	        Tcl_AppendResult (interp, " while processing write_tabsep channel", (char *) NULL);
	        return TCL_ERROR;
	    }
	    search->writingTabsep = 1;
	  }
	}
    }

    if (search->writingTabsep && search->codeBody != NULL) {
	Tcl_AppendResult (interp, "can't use -code and -write_tabsep together", (char *) NULL);
	return TCL_ERROR;
    }

    if (search->sortControl.nFields && search->countOnly) {
	Tcl_AppendResult (interp, "it's nuts to -sort something that's a -countOnly anyway", (char *) NULL);
	return TCL_ERROR;
    }
}

#error "still need to set search_compare and sort_compare elements of the search structure"
