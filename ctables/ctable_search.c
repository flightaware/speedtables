/*
 * Ctable search routines
 *
 * $Id$
 *
 */

#include "ctable.h"

#include "boyer_moore.c"

#include "jsw_rand.c"

#include "ctable_lists.c"

#include "jsw_slib.c"

/*
 * ctable_ParseFieldList - given a Tcl list object and a pointer to an array
 * of integer field numbers and a pointer to an integer for field counts,
 * install the field count into the field count and allocate an array of 
 * integers for the corresponding field indexes and fill that array with the 
 * field numbers corresponding to the field names in the list.
 *
 * It is up to the caller to free the memory pointed to through the
 * fieldList argument.
 *
 * return TCL_OK if all went according to plan, else TCL_ERROR.
 *
 */
int
ctable_ParseFieldList (Tcl_Interp *interp, Tcl_Obj *fieldListObj, CONST char **fieldNames, int **fieldListPtr, int *fieldCountPtr) {
    int             nFields;
    Tcl_Obj       **fieldsObjv;
    int             i;
    int            *fieldList;

    // the fields they want us to retrieve
    if (Tcl_ListObjGetElements (interp, fieldListObj, &nFields, &fieldsObjv) == TCL_ERROR) {
      return TCL_ERROR;
    }

    *fieldCountPtr = nFields;
    *fieldListPtr = fieldList = (int *)ckalloc (sizeof (int) * nFields);

    for (i = 0; i < nFields; i++) {
	if (Tcl_GetIndexFromObj (interp, fieldsObjv[i], fieldNames, "field", TCL_EXACT, &fieldList[i]) != TCL_OK) {
	    ckfree ((void *)fieldList);
	    *fieldListPtr = NULL;
	    return TCL_ERROR;
	  }
    }
    return TCL_OK;
}

/*
 * ctable_ParseSortFieldList - given a Tcl list object, and a pointer to a
 * ctable sort structure, store the number of fields in the list in the
 * sort structure's field count.  allocate an array of integers for the
 * field numbers and directions and store them into the sort structure passed.
 *
 * Strip the prepending dash of each field, if present, and do the lookup
 * and store the field number in the corresponding field number array.
 *
 * If the dash was present set the corresponding direction in the direction
 * array to 0 else set it to 1.
 *
 * It is up to the caller to free the memory pointed to through the
 * fieldList argument.
 *
 * return TCL_OK if all went according to plan, else TCL_ERROR.
 *
 */
int
ctable_ParseSortFieldList (Tcl_Interp *interp, Tcl_Obj *fieldListObj, CONST char **fieldNames, struct ctableSortStruct *sort) {
    int             nFields;
    Tcl_Obj       **fieldsObjv;
    Tcl_Obj        *fieldNameObj;
    int             i;
    char           *fieldName;

    // the fields they want us to retrieve
    if (Tcl_ListObjGetElements (interp, fieldListObj, &nFields, &fieldsObjv) == TCL_ERROR) {
      return TCL_ERROR;
    }

    sort->nFields = nFields;
    sort->fields =  (int *)ckalloc (sizeof (int) * nFields);
    sort->directions =  (int *)ckalloc (sizeof (int) * nFields);

    for (i = 0; i < nFields; i++) {
        fieldName = Tcl_GetString (fieldsObjv[i]);
	if (fieldName[0] == '-') {
	    sort->directions[i] = -1;
	    fieldName++;
	    fieldNameObj = Tcl_NewStringObj (fieldName, -1);
	} else {
	    fieldNameObj = fieldsObjv[i];
	    sort->directions[i] = 1;
	}

	if (Tcl_GetIndexFromObj (interp, fieldNameObj, fieldNames, "field", TCL_EXACT, &sort->fields[i]) != TCL_OK) {
	    ckfree ((void *)sort->fields);
	    ckfree ((void *)sort->directions);
	    sort->fields = NULL;
	    sort->directions = NULL;
	    return TCL_ERROR;
	  }
    }
    return TCL_OK;
}

int
ctable_searchMatchPatternCheck (char *s) {
    char c;

    int firstCharIsStar = 0;
    int lastCharIsStar = 0;

    if (*s == '\0') {
	return CTABLE_STRING_MATCH_ANCHORED;
    }

    if (*s++ == '*') {
	firstCharIsStar = 1;
    }

    while ((c = *s++) != '\0') {
	switch (c) {
	  case '*':
	    if (*s == '\0') {
		lastCharIsStar = 1;
	    } else {
		// some other * in the middle, too fancy
		return CTABLE_STRING_MATCH_PATTERN;
	    }
	    break;

	  case '?':
	  case '[':
	  case ']':
	  case '\\':
	    return CTABLE_STRING_MATCH_PATTERN;

	}
    }

    if (firstCharIsStar) {
	if (lastCharIsStar) {
	    return CTABLE_STRING_MATCH_UNANCHORED;
	}
	// we could do a reverse anchored search here but i don't
	// think this comes up often enough (*pattern) to warrant it
	return CTABLE_STRING_MATCH_PATTERN;
    }

    if (lastCharIsStar) {
	// first char is not star, last char is
	return CTABLE_STRING_MATCH_ANCHORED;
    }

    // first char is not star, last char is not star, this is
    // bad because they should be using "=" not "match" but we'll
    // use pattern because that will actually do the right thing.
    // alternatively we could add another string match pattern type
    return CTABLE_STRING_MATCH_PATTERN;
}


static int
ctable_ParseSearch (Tcl_Interp *interp, struct ctableTable *ctable, Tcl_Obj *componentListObj, CONST char **fieldNames, struct ctableSearchStruct *search) {
    Tcl_Obj    **componentList;
    int          componentIdx;
    int          componentListCount;

    Tcl_Obj    **termList;
    int          termListCount;

    int          field;

    struct ctableSearchComponentStruct  *components;
    struct ctableSearchComponentStruct  *component;
    
    // these terms must line up with the CTABLE_COMP_* defines
    static CONST char *searchTerms[] = {"false", "true", "null", "notnull", "<", "<=", "=", "!=", ">=", ">", "match", "match_case", "range", (char *)NULL};

    if (Tcl_ListObjGetElements (interp, componentListObj, &componentListCount, &componentList) == TCL_ERROR) {
        return TCL_ERROR;
    }

    if (componentListCount == 0) {
        search->components = NULL;
	return TCL_OK;
    }

    search->nComponents = componentListCount;

    components = (struct ctableSearchComponentStruct *)ckalloc (componentListCount * sizeof (struct ctableSearchComponentStruct));

    search->components = components;

    for (componentIdx = 0; componentIdx < componentListCount; componentIdx++) {
        int term;

	if (Tcl_ListObjGetElements (interp, componentList[componentIdx], &termListCount, &termList) == TCL_ERROR) {
	  err:
	    ckfree ((char *)components);
	    return TCL_ERROR;
	}

	if (termListCount < 2 || termListCount > 4) {
	    // would be cool to support regexps here too
	    Tcl_WrongNumArgs (interp, 0, termList, "term field ?value..?");
	    goto err;
	}

	if (Tcl_GetIndexFromObj (interp, termList[0], searchTerms, "term", TCL_EXACT, &term) != TCL_OK) {
	    goto err;
	}

	if (Tcl_GetIndexFromObj (interp, termList[1], fieldNames, "field", TCL_EXACT, &field) != TCL_OK) {
	    goto err;
	}

	component = &components[componentIdx];

	component->comparisonType = term;
	component->fieldID = field;
	component->clientData = NULL;
	component->row1 = NULL;
	component->row2 = NULL;

	if (term == CTABLE_COMP_FALSE || term == CTABLE_COMP_TRUE || term == CTABLE_COMP_NULL || term == CTABLE_COMP_NOTNULL) {
	    component->comparedToObject = NULL;
	    component->comparedToString = NULL;
	    component->comparedToStringLength = 0;
	    if (termListCount != 2) {
		Tcl_AppendResult (interp, "false, true, null and notnull search expressions must have only two fields", (char *) NULL);
		goto err;
	    }
	}  else {
	    if (term == CTABLE_COMP_RANGE) {
	        void *row;

	        if (termListCount != 4) {
		    Tcl_AppendResult (interp, "term \"", Tcl_GetString (termList[0]), "\" require 4 arguments (term, field, lowValue, highValue)", (char *) NULL);
		    goto err;
		}
		component->comparedToObject = termList[2];

		row = (*ctable->creatorTable->make_empty_row) ();
		if ((*ctable->creatorTable->set) (interp, ctable, termList[2], row, field, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
		    goto err;
		}
		component->row1 = row;

		row = (*ctable->creatorTable->make_empty_row) ();
		if ((*ctable->creatorTable->set) (interp, ctable, termList[3], row, field, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
		    goto err;
		}
		component->row2 = row;

	    } else if (termListCount != 3) {
		Tcl_AppendResult (interp, "term \"", Tcl_GetString (termList[0]), "\" require 3 arguments (term, field, value)", (char *) NULL);
		goto err;
	    }

	    /* stash this as a string, we could be smarter - we sould
	     * be smarter with a union and figure it out for the
	     * data types that'll be lookin' for it
	     * NB this could cause unnecessary tcl object shimmering,
	     * needs a close look
	     */
	    component->comparedToObject = termList[2];
	    component->comparedToString = Tcl_GetStringFromObj (component->comparedToObject, &component->comparedToStringLength);

	    if ((term == CTABLE_COMP_MATCH) || (term == CTABLE_COMP_MATCH_CASE)) {
		struct ctableSearchMatchStruct *sm = (struct ctableSearchMatchStruct *)ckalloc (sizeof (struct ctableSearchMatchStruct));

		sm->type = ctable_searchMatchPatternCheck (Tcl_GetString (component->comparedToObject));
		sm->nocase = (term == CTABLE_COMP_MATCH);

		if (sm->type == CTABLE_STRING_MATCH_UNANCHORED) {
		    char *needle;
		    int len;

		    needle = Tcl_GetStringFromObj (component->comparedToObject, &len);
		    boyer_moore_setup (sm, (unsigned char *)needle + 1, len - 2, sm->nocase);
		}

		component->clientData = sm;
	    }
	}
    }

    // it worked, leave the components allocated
    return TCL_OK;
}

static int
ctable_SearchAction (Tcl_Interp *interp, struct ctableTable *ctable, struct ctableSearchStruct *search, struct ctable_baseRow *row) {
    char           *key;
    int             i;
    Tcl_HashTable *keyTablePtr = ctable->keyTablePtr;

    key = Tcl_GetHashKey (keyTablePtr, row->hashEntry);

    if (search->writingTabsep) {
	Tcl_DString     dString;

	Tcl_DStringInit (&dString);

        if (search->nRetrieveFields < 0) {
	    (*ctable->creatorTable->dstring_append_get_tabsep) (key, row, ctable->creatorTable->fieldList, ctable->creatorTable->nFields, &dString, search->noKeys);
	} else {
	    (*ctable->creatorTable->dstring_append_get_tabsep) (key, row, search->retrieveFields, search->nRetrieveFields, &dString, search->noKeys);
	}

	if (Tcl_WriteChars (search->tabsepChannel, Tcl_DStringValue (&dString), Tcl_DStringLength (&dString)) < 0) {
	    return TCL_ERROR;
	}

	Tcl_DStringFree (&dString);
	return TCL_OK;
    }

    if (search->codeBody != NULL) {
	Tcl_Obj *listObj = Tcl_NewObj();
	int      evalResult;

	if (search->useGet) {
	    if (search->nRetrieveFields < 0) {
		listObj = (*ctable->creatorTable->gen_list) (interp, row);
	    } else {
	       int i;

	       for (i = 0; i < search->nRetrieveFields; i++) {
		   ctable->creatorTable->lappend_field (interp, listObj, row, ctable->creatorTable->fieldList[i]);
	       }
	    }
	} else if (search->useArrayGet) {
	    if (search->nRetrieveFields < 0) {
	       int i;

	       for (i = 0; i < ctable->creatorTable->nFields; i++) {
		   ctable->creatorTable->lappend_nonnull_field_and_name (interp, listObj, row, i);
	       }
	    } else {
	       int i;

	       for (i = 0; i < search->nRetrieveFields; i++) {
		   ctable->creatorTable->lappend_nonnull_field_and_name (interp, listObj, row, search->retrieveFields[i]);
	       }
	    }
	} else if (search->useArrayGetWithNulls) {
	    if (search->nRetrieveFields < 0) {
		listObj = (*ctable->creatorTable->gen_keyvalue_list) (interp, row);
	    } else {
		for (i = 0; i < search->nRetrieveFields; i++) {
		    ctable->creatorTable->lappend_field_and_name (interp, listObj, row, search->retrieveFields[i]);
		}
	    }
	} else {
	    panic ("code path shuld have matched useArrayGet or useArrayGetWithNulls");
	}

	// if the key var is defined, set the key into it
	if (search->keyVarNameObj != NULL) {
	    if (Tcl_ObjSetVar2 (interp, search->keyVarNameObj, (Tcl_Obj *)NULL, Tcl_NewStringObj (key, -1), TCL_LEAVE_ERR_MSG) == (Tcl_Obj *) NULL) {
		return TCL_ERROR;
	    }
	}

	// set the returned list into the value var
	if (Tcl_ObjSetVar2 (interp, search->varNameObj, (Tcl_Obj *)NULL, listObj, TCL_LEAVE_ERR_MSG) == (Tcl_Obj *) NULL) {
	    return TCL_ERROR;
	}

	evalResult = Tcl_EvalObjEx (interp, search->codeBody, 0);
	switch (evalResult) {
	  case TCL_ERROR:
	    Tcl_AppendResult (interp, " while processing search code body", (char *) NULL);
	    return TCL_ERROR;

	  case TCL_OK:
	  case TCL_CONTINUE:
	  case TCL_BREAK:
	  case TCL_RETURN:
	    return evalResult;
	}
    }

    return TCL_OK;
}

//
// ctable_PerformSearch - perform the search
//
// write field names if we need to
//
// for each row in the table, apply search compare test in turn
//    the first one that comes up that the row should be excluded ends
//    looking at that one
//
//    if nothing excluded it, we pick it -- this can mean taking the action
//    immediately or, if sorting, picking the object for sorting and then
//    taking the action
//
//
#define LINKED_LIST

static int
ctable_PerformSearch (Tcl_Interp *interp, struct ctableTable *ctable, struct ctableSearchStruct *search, int count) {
    Tcl_HashEntry   *hashEntry;
#ifndef LINKED_LIST
    Tcl_HashSearch   hashSearch;
#endif
    char            *key;

    int              compareResult;
    int              matchCount = 0;
    int              sortIndex;
    int              actionResult = TCL_OK;
    int              limit = search->offset + search->limit;

    struct ctable_baseRow **sortTable = NULL;
    Tcl_HashTable *keyTablePtr = ctable->keyTablePtr;

#ifdef LINKED_LIST
    struct ctable_baseRow *row;
#endif

    if (count == 0) {
        return TCL_OK;
    }

    if (search->writingTabsepIncludeFieldNames) {
	int i;
	Tcl_DString     dString;
	int            *fields;
	int             nFields;

	Tcl_DStringInit (&dString);

        if (search->nRetrieveFields < 0) {
	    fields = ctable->creatorTable->fieldList;
	    nFields = ctable->creatorTable->nFields;
	} else {
	    nFields = search->nRetrieveFields;
	    fields = search->retrieveFields;
	}

	if (!search->noKeys) {
	    Tcl_DStringAppend(&dString, "_key", 4);
	}
	for (i = 0; i < nFields; i++) {
	    if (!search->noKeys || i != 0) {
		Tcl_DStringAppend(&dString, "\t", 1);
	    }
	    Tcl_DStringAppend(&dString, ctable->creatorTable->fieldNames[fields[i]], -1);
	}
	Tcl_DStringAppend(&dString, "\n", 1);

	if (Tcl_WriteChars (search->tabsepChannel, Tcl_DStringValue (&dString), Tcl_DStringLength (&dString)) < 0) {
	    return TCL_ERROR;
	}

	Tcl_DStringFree (&dString);
    }

    // if we're sorting, allocate a space for the search results that
    // we'll then sort from -- unfortunately we don't know how many
    // search results we may get, so we are prepared to receive all
    // of them.  if you want to optimize this for space, you'll have to grow 
    // the search result dynamically -- just buy more memory
    //
    // you can't sort until after you've picked everything and you can't
    // stop earching until you've looked at everything (you can't do stuff
    // based on limit or offset) becuase the order of what you want isn't
    // established until after the sort.
    if ((search->sortControl.nFields > 0) && (!search->countOnly)) {
	sortTable = (struct ctable_baseRow **)ckalloc (sizeof (void *) * count);
    }

    // walk the table -- soon we hope to replace this with a skiplist walk
    // or equivalent
#ifdef LINKED_LIST
    CTABLE_LIST_FOREACH (ctable->ll_head, row, 0) {
        hashEntry = row->hashEntry;
        key = Tcl_GetHashKey (keyTablePtr, hashEntry);
#else
    for (hashEntry = Tcl_FirstHashEntry (keyTablePtr, &hashSearch); hashEntry != (Tcl_HashEntry *) NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {
	void           *row;

	key = Tcl_GetHashKey (keyTablePtr, hashEntry);

#endif

        // if we have a match pattern (for the key) and it doesn't match,
	// skip this row

	if ((search->pattern != (char *) NULL) && (!Tcl_StringCaseMatch (key, search->pattern, 1))) continue;

	//
	// run the supplied compare routine
	//
#ifndef LINKED_LIST
	row = Tcl_GetHashValue (hashEntry);
#endif
	compareResult = (*ctable->creatorTable->search_compare) (interp, search, (void *)row, 0);
	if (compareResult == TCL_CONTINUE) {
	    continue;
	}

	if (compareResult == TCL_ERROR) {
	    actionResult = TCL_ERROR;
	    goto clean_and_return;
	}

	// It's a Match 
        // Are we not sorting? 

	if (sortTable == NULL) {
	    // if we haven't met the start point, blow it off
	    if (++matchCount <= search->offset) continue;

	    if (search->countOnly) {
		// we're only counting -- if there is a limit and it's been 
		// met, we're done
		if ((search->limit != 0) && (matchCount >= limit)) {
		    actionResult = TCL_OK;
		    goto clean_and_return;
		}

		// the limit hasn't been exceeded or there isn't one,
		// so we keep counting -- but we continue here because
		// we don't need to do any processing on the line
		continue;
	    }

	    /* we want to take the match actions here --
	     * we're here when we aren't sorting
	     */
	     actionResult = ctable_SearchAction (interp, ctable, search, row);
	     if (actionResult == TCL_ERROR) {
		  goto clean_and_return;
	     }

	     if (actionResult == TCL_CONTINUE || actionResult == TCL_OK) {
		// if there was a limit and we've met it, we're done
		if ((search->limit != 0) && (matchCount >= limit)) {
		    actionResult = TCL_OK;
		    goto clean_and_return;
		}
		 continue;
	     }

	     if (actionResult == TCL_BREAK || actionResult == TCL_RETURN) {
		  actionResult = TCL_OK;
		  goto clean_and_return;
	     }
	// match, handle action or tabsep write
	} else {
	    /* We are sorting, grab it, we gotta sort before we can run
	     * against start and limit and stuff */
	    assert (matchCount < count);
	    // printf ("filling sort table %d -> hash entry %lx (%s)\n", matchCount, (long unsigned int)hashEntry, key);
	    sortTable[matchCount++] = row;
	}
    }

    // if we're not sorting, we're done -- we did 'em all on the fly
    if (sortTable == NULL) {
	actionResult = TCL_OK;
	goto clean_and_return;
    }

    qsort_r (sortTable, matchCount, sizeof (Tcl_HashEntry *), &search->sortControl, ctable->creatorTable->sort_compare);

    // it's sorted
    // now let's see what we've got within the offset and limit

    // if the offset's more than the matchCount, they got nuthin'
    if (search->offset > matchCount) {
	actionResult = TCL_OK;
	goto clean_and_return;
    }

    // figure out the last row they could want, if it's more than what's
    // there, set it down to what came back
    if ((limit == 0) || (limit > matchCount)) {
        limit = matchCount;
    }

    // walk the result
    for (sortIndex = search->offset; sortIndex < limit; sortIndex++) {

	/* here is where we want to take the match actions
	 * when we are sorting
	 */
	 actionResult = ctable_SearchAction (interp, ctable, search, sortTable[sortIndex]);
	 if (actionResult == TCL_ERROR) {
	     goto clean_and_return;
	 }

	 if (actionResult == TCL_CONTINUE || actionResult == TCL_OK) {
	     continue;
	 }

	 if (actionResult == TCL_BREAK || actionResult == TCL_RETURN) {
	     actionResult = TCL_OK;
	     goto clean_and_return;
	 }
    }

  clean_and_return:
    if (sortTable != NULL) {
	ckfree ((void *)sortTable);
    }

    if (actionResult == TCL_OK && search->countOnly) {
	Tcl_SetIntObj (Tcl_GetObjResult (interp), matchCount);
    }

    return actionResult;
}

//
// ctable_SkipSearchAction - pretty much the same as ctable_SearchAction
// except that it doesn't support the "-key varName" thing.
//
//
static int
ctable_SkipSearchAction (Tcl_Interp *interp, struct ctableTable *ctable, struct ctableSearchStruct *search, void *row) {
    char           *key = NULL;
    int             i;

    if (search->writingTabsep) {
	Tcl_DString     dString;

	Tcl_DStringInit (&dString);

        // get the fields and append them to the dstring tab-separated
	// inhibit emitting the outside-of-the-record hash key because
	// we don't have any idea what it is and we don't care anyway

        if (search->nRetrieveFields < 0) {
	    (*ctable->creatorTable->dstring_append_get_tabsep) (key, row, ctable->creatorTable->fieldList, ctable->creatorTable->nFields, &dString, 1);
	} else {
	    (*ctable->creatorTable->dstring_append_get_tabsep) (key, row, search->retrieveFields, search->nRetrieveFields, &dString, 1);
	}

	if (Tcl_WriteChars (search->tabsepChannel, Tcl_DStringValue (&dString), Tcl_DStringLength (&dString)) < 0) {
	    return TCL_ERROR;
	}

	Tcl_DStringFree (&dString);
	return TCL_OK;
    }

    if (search->codeBody != NULL) {
	Tcl_Obj *listObj = Tcl_NewObj();
	int      evalResult;

	if (search->useGet) {
	    if (search->nRetrieveFields < 0) {
		listObj = (*ctable->creatorTable->gen_list) (interp, row);
	    } else {
	       int i;

	       for (i = 0; i < search->nRetrieveFields; i++) {
		   ctable->creatorTable->lappend_field (interp, listObj, row, ctable->creatorTable->fieldList[i]);
	       }
	    }
	} else if (search->useArrayGet) {
	    if (search->nRetrieveFields < 0) {
	       int i;

	       for (i = 0; i < ctable->creatorTable->nFields; i++) {
		   ctable->creatorTable->lappend_nonnull_field_and_name (interp, listObj, row, i);
	       }
	    } else {
	       int i;

	       for (i = 0; i < search->nRetrieveFields; i++) {
		   ctable->creatorTable->lappend_nonnull_field_and_name (interp, listObj, row, search->retrieveFields[i]);
	       }
	    }
	} else if (search->useArrayGetWithNulls) {
	    if (search->nRetrieveFields < 0) {
		listObj = (*ctable->creatorTable->gen_keyvalue_list) (interp, row);
	    } else {
		for (i = 0; i < search->nRetrieveFields; i++) {
		    ctable->creatorTable->lappend_field_and_name (interp, listObj, row, search->retrieveFields[i]);
		}
	    }
	} else {
	    panic ("code path shuld have matched useArrayGet or useArrayGetWithNulls");
	}

	// set the returned list into the value var
	if (Tcl_ObjSetVar2 (interp, search->varNameObj, (Tcl_Obj *)NULL, listObj, TCL_LEAVE_ERR_MSG) == (Tcl_Obj *) NULL) {
	    return TCL_ERROR;
	}

	evalResult = Tcl_EvalObjEx (interp, search->codeBody, 0);
	switch (evalResult) {
	  case TCL_ERROR:
	    Tcl_AppendResult (interp, " while processing search code body", (char *) NULL);
	    return TCL_ERROR;

	  case TCL_OK:
	  case TCL_CONTINUE:
	  case TCL_BREAK:
	  case TCL_RETURN:
	    return evalResult;
	}
    }

    return TCL_OK;
}


//
// ctable_PerformSkipSearch - perform the search
//
// write field names if we need to
//
// for each row in the table, apply search compare test in turn
//    the first one that comes up that the row should be excluded ends
//    looking at that one
//
//    if nothing excluded it, we pick it -- this can mean taking the action
//    immediately or, if sorting, picking the object for sorting and then
//    taking the action
//
//
static int
ctable_PerformSkipSearch (Tcl_Interp *interp, struct ctableTable *ctable, struct ctableSearchStruct *search, int count) {
    int              compareResult;
    int              matchCount = 0;
    int              sortIndex;
    int              actionResult = TCL_OK;
    int              limit = search->offset + search->limit;

    int              tailoredWalk = 0;

// #undef LINKED_LIST
#ifdef LINKED_LIST
    struct ctable_baseRow *row;
    struct ctable_baseRow *row1 = NULL;
    struct ctable_baseRow *walkRow;
#else
    void            *row1 = NULL;
    jsw_node_t      *curl;
#endif
    void            *row2 = NULL;

    void          **sortTable = NULL;

    jsw_skip_t      *skip = NULL;
    int              field = 0;

    if (count == 0) {
        return TCL_OK;
    }

    if (search->writingTabsepIncludeFieldNames) {
	int i;
	Tcl_DString     dString;
	int            *fields;
	int             nFields;

	Tcl_DStringInit (&dString);

        if (search->nRetrieveFields < 0) {
	    fields = ctable->creatorTable->fieldList;
	    nFields = ctable->creatorTable->nFields;
	} else {
	    nFields = search->nRetrieveFields;
	    fields = search->retrieveFields;
	}

	for (i = 0; i < nFields; i++) {
	    if (i != 0) {
		Tcl_DStringAppend(&dString, "\t", 1);
	    }
	    Tcl_DStringAppend(&dString, ctable->creatorTable->fieldNames[fields[i]], -1);
	}
	Tcl_DStringAppend(&dString, "\n", 1);

	if (Tcl_WriteChars (search->tabsepChannel, Tcl_DStringValue (&dString), Tcl_DStringLength (&dString)) < 0) {
	    return TCL_ERROR;
	}

	Tcl_DStringFree (&dString);
    }

    // if we're sorting, allocate a space for the search results that
    // we'll then sort from -- unfortunately we don't know how many
    // search results we may get, so we are prepared to receive all
    // of them.  if you want to optimize this for space, you'll have to grow 
    // the search result dynamically -- just buy more memory
    //
    // you can't sort until after you've picked everything and you can't
    // stop earching until you've looked at everything (you can't do stuff
    // based on limit or offset) becuase the order of what you want isn't
    // established until after the sort.
    if ((search->sortControl.nFields > 0) && (!search->countOnly)) {
        sortTable = (void **)ckalloc (count * sizeof (void *));
    }

    // if the first compare thing is something we understand how to do
    // with indexed fields and the field they're asking for us to do it
    // on happens to be indexed, we need to do special walking magic

    // else if there's any index column, we can walk that faster than
    // we can walk the tcl hashtable

    // if there's no index column, we need to fail or revert to the
    // hash at least for now

    // here i'd really like to start making the structure to compare
    // to and in fact we have to if we want to take advantage of the
    // skip lists because that's how they work




    // walk the table -- soon we hope to replace this with a skiplist walk
    // or equivalent
    if (search->nComponents > 0) {
	int term;

	struct ctableSearchComponentStruct *component = &search->components[0];

	field = component->fieldID;
	term = component->comparisonType;
        if ((ctable->skipLists[field] != NULL) && (term == CTABLE_COMP_RANGE)) {
	    // ding ding ding - we have a winner, time for an accelerated
	    // search
	    tailoredWalk = 1;
	    skip = ctable->skipLists[field];
	    row1 = component->row1;
	    row2 = component->row2;
	}
    }

    // if we don't have a tailored walk, see if we have any skip list
    // we can use
    if (!tailoredWalk) {
	skip = NULL;
        for (field= 0; field < ctable->creatorTable->nFields; field++) {
	    if ((skip = ctable->skipLists[field]) != NULL) {
	        break;
	    }
	}
    }

    if (skip == NULL) {
	Tcl_AppendResult (interp, "no field has an index, can't perform tailored search, sorry", (char *) NULL);
	actionResult = TCL_ERROR;
	goto clean_and_return;
    }

    if (tailoredWalk) {
       // yay get the huge win by zooming past hopefully a zillion records
       // right here
       //
       jsw_sfind_equal_or_greater (skip, row1);
    } else {
        // not tailored, we're looking at all rows
	jsw_sreset (skip);
    }

    //
    // walk the skip list, whether we searched and found something or if
    // we're walking the whole thing
    //
    // if the walk is "tailored", meaning the first search term is of an
    // indexed row and it's of a type where we can cut off the search
    // past a point, see if we're past the cutoff point and if we are
    // terminate the search.
    //
    //
    // here are a couple of interesting ways to also play this
    //
    // for (; ((struct jsw_skip *)skip)->curl != NULL && (row = ((struct jsw_skip *)skip)->curl->item); ((struct jsw_skip *)skip)->curl = ((struct jsw_skip *)skip)->curl->next[0])
    //
    // CTABLE_LIST_FOREACH (ctable->ll_head, row, 0)
    //
    //  for (; curl != NULL && (row = curl->item); curl = curl->next[0])


    for (; ((row = jsw_srow (skip)) != NULL); jsw_snext(skip)) {

    // curl = ((struct jsw_skip *)skip)->curl;

      if (tailoredWalk) {
          if (ctable->creatorTable->fields[field]->compareFunction (row, row2) >= 0) {
	     // it was a tailored walk and we're past the end of the
	     // range of stuff so we can blow off the rest, hopefully
	     // a huge number
	    break;
	  }
      }

      // walk walkRow through the linked list of rows off this skip list node
      // if you ever change this to make deletion possible while searching,
      // switch this to use the safe foreach routine instead

      CTABLE_LIST_FOREACH (row, walkRow, ctable->creatorTable->fields[field]->indexNumber) {

	//
	// run the supplied compare routine
	//
	// if it's a tailored walk (tailoredWalk == 1), we start the comparing
	// from the second search term (if there is more than one, it'll
	// actually do something, else it'll just not exclude the row, i.e.
	// it will do what it's supposed to.)
	//
	compareResult = (*ctable->creatorTable->search_compare) (interp, search, walkRow, tailoredWalk);
	if (compareResult == TCL_CONTINUE) {
	    continue;
	}

	if (compareResult == TCL_ERROR) {
	    actionResult = TCL_ERROR;
	    goto clean_and_return;
	}

	// It's a Match 
        // Are we not sorting? 

	if (sortTable == NULL) {
	    // if we haven't met the start point, blow it off
	    if (++matchCount <= search->offset) continue;

	    if (search->countOnly) {
		// we're only counting -- if there is a limit and it's been 
		// met, we're done
		if ((search->limit != 0) && (matchCount >= limit)) {
		    actionResult = TCL_OK;
		    goto clean_and_return;
		}

		// the limit hasn't been exceeded or there isn't one,
		// so we keep counting -- but we continue here because
		// we don't need to do any processing on the line
		continue;
	    }

	    /* we want to take the match actions here --
	     * we're here when we aren't sorting
	     */
	     actionResult = ctable_SkipSearchAction (interp, ctable, search, walkRow);
	     if (actionResult == TCL_ERROR) {
		  goto clean_and_return;
	     }

	     if (actionResult == TCL_CONTINUE || actionResult == TCL_OK) {
		// if there was a limit and we've met it, we're done
		if ((search->limit != 0) && (matchCount >= limit)) {
		    actionResult = TCL_OK;
		    goto clean_and_return;
		}
		 continue;
	     }

	     if (actionResult == TCL_BREAK || actionResult == TCL_RETURN) {
		  actionResult = TCL_OK;
		  goto clean_and_return;
	     }
	// match, handle action or tabsep write
	} else {
	    /* We are sorting, grab it, we gotta sort before we can run
	     * against start and limit and stuff */
	    assert (matchCount < count);
	    // printf ("filling sort table %d -> hash entry %lx (%s)\n", matchCount, (long unsigned int)hashEntry, key);
	    sortTable[matchCount++] = walkRow;
	}
      }
    }

    // if we're not sorting, we're done -- we did 'em all on the fly
    if (sortTable == NULL) {
	actionResult = TCL_OK;
	goto clean_and_return;
    }

    qsort_r (sortTable, matchCount, sizeof (void *), &search->sortControl, ctable->creatorTable->sort_compare);

    // it's sorted
    // now let's see what we've got within the offset and limit

    // if the offset's more than the matchCount, they got nuthin'
    if (search->offset > matchCount) {
	actionResult = TCL_OK;
	goto clean_and_return;
    }

    // figure out the last row they could want, if it's more than what's
    // there, set it down to what came back
    if ((limit == 0) || (limit > matchCount)) {
        limit = matchCount;
    }

    // walk the result
    for (sortIndex = search->offset; sortIndex < limit; sortIndex++) {

	/* here is where we want to take the match actions
	 * when we are sorting
	 */
	 actionResult = ctable_SkipSearchAction (interp, ctable, search, sortTable[sortIndex]);
	 if (actionResult == TCL_ERROR) {
	     goto clean_and_return;
	 }

	 if (actionResult == TCL_CONTINUE || actionResult == TCL_OK) {
	     continue;
	 }

	 if (actionResult == TCL_BREAK || actionResult == TCL_RETURN) {
	     actionResult = TCL_OK;
	     goto clean_and_return;
	 }
    }

  clean_and_return:
    if (sortTable != NULL) {
	ckfree ((void *)sortTable);
    }

    if (actionResult == TCL_OK && search->countOnly) {
	Tcl_SetIntObj (Tcl_GetObjResult (interp), matchCount);
    }

    return actionResult;
}

static int
ctable_SetupSearch (Tcl_Interp *interp, struct ctableTable *ctable, Tcl_Obj *CONST objv[], int objc, struct ctableSearchStruct *search, CONST char **fieldNames) {
    int             i;
    int             searchTerm = 0;

    static CONST char *searchOptions[] = {"-array_get", "-array_get_with_nulls", "-code", "-compare", "-countOnly", "-fields", "-get", "-glob", "-key", "-include_field_names", "-limit", "-noKeys", "-offset", "-regexp", "-sort", "-write_tabsep", (char *)NULL};

    enum searchOptions {SEARCH_OPT_ARRAYGET_NAMEOBJ, SEARCH_OPT_ARRAYGETWITHNULLS_NAMEOBJ, SEARCH_OPT_CODE, SEARCH_OPT_COMPARE, SEARCH_OPT_COUNTONLY, SEARCH_OPT_FIELDS, SEARCH_OPT_GET_NAMEOBJ, SEARCH_OPT_GLOB, SEARCH_OPT_KEYVAR_NAMEOBJ, SEARCH_OPT_INCLUDE_FIELD_NAMES, SEARCH_OPT_LIMIT, SEARCH_OPT_DONT_INCLUDE_KEY, SEARCH_OPT_OFFSET, SEARCH_OPT_REGEXP, SEARCH_OPT_SORT, SEARCH_OPT_WRITE_TABSEP};

    if (objc < 2) {
      wrong_args:
	Tcl_WrongNumArgs (interp, 2, objv, "?-array_get varName? ?-array_get_with_nulls varName? ?-code codeBody? ?-compare list? ?-countOnly 0|1? ?-fields fieldList? ?-get varName? ?-glob pattern? ?-key varName? ?-include_field_names 0|1?  ?-limit limit? ?-noKeys 0|1? ?-offset offset? ?-regexp pattern? ?-sort {?-?field1..}? ?-write_tabsep channel?");
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
    search->sortControl.directions = NULL;
    search->sortControl.nFields = 0;
    search->retrieveFields = NULL;
    search->nRetrieveFields = -1;   // -1 = all, 0 = none
    search->noKeys = 0;
    search->varNameObj = NULL;
    search->keyVarNameObj = NULL;
    search->useArrayGet = 0;
    search->useArrayGetWithNulls = 0;
    search->useGet = 0;
    search->codeBody = NULL;
    search->writingTabsep = 0;
    search->writingTabsepIncludeFieldNames = 0;

    for (i = 2; i < objc; ) {
	if (Tcl_GetIndexFromObj (interp, objv[i++], searchOptions, "search option", TCL_EXACT, &searchTerm) != TCL_OK) {
	    return TCL_ERROR;
	}

	//  all the arguments require one parameter
	if (i >= objc) {
	    goto wrong_args;
	}

	switch (searchTerm) {
	  case SEARCH_OPT_SORT: {
	    // the fields they want us to sort on
	    if (ctable_ParseSortFieldList (interp, objv[i++], fieldNames, &search->sortControl) == TCL_ERROR) {
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

	  case SEARCH_OPT_DONT_INCLUDE_KEY: {
	    if (Tcl_GetBooleanFromObj (interp, objv[i++], &search->noKeys) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search noKeys", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_INCLUDE_FIELD_NAMES: {
	    if (Tcl_GetBooleanFromObj (interp, objv[i++], &search->writingTabsepIncludeFieldNames) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search -include_field_names", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_ARRAYGET_NAMEOBJ: {
	    search->varNameObj = objv[i++];
	    search->useArrayGet = 1;
	    break;
	  }

	  case SEARCH_OPT_ARRAYGETWITHNULLS_NAMEOBJ: {
	    search->varNameObj = objv[i++];
	    search->useArrayGetWithNulls = 1;
	    break;
	  }

	  case SEARCH_OPT_KEYVAR_NAMEOBJ: {
	    search->keyVarNameObj = objv[i++];
	    break;
          }

	  case SEARCH_OPT_GET_NAMEOBJ: {
	    search->varNameObj = objv[i++];
	    search->useGet = 1;
	    break;
          }

	  case SEARCH_OPT_GLOB: {
	    search->pattern = Tcl_GetString (objv[i++]);
	    break;
	  }

	  case SEARCH_OPT_REGEXP: {
	    Tcl_AppendResult (interp, "regexp not implemented yet", (char *) NULL);
	    return TCL_ERROR;
	  }

	  case SEARCH_OPT_COMPARE: {
	    if (ctable_ParseSearch (interp, ctable, objv[i++], fieldNames, search) == TCL_ERROR) {
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
	    int        mode;
	    char      *channelName;

	    channelName = Tcl_GetString (objv[i++]);
	    if ((search->tabsepChannel = Tcl_GetChannel (interp, channelName, &mode)) == NULL) {
	        Tcl_AppendResult (interp, " while processing write_tabsep channel", (char *) NULL);
	        return TCL_ERROR;
	    }

	    if (!(mode & TCL_WRITABLE)) {
		Tcl_AppendResult (interp, "channel \"", channelName, "\" not writable", (char *)NULL);
		return TCL_ERROR;
	    }

	    search->writingTabsep = 1;
	  }
	}
    }

    if (search->writingTabsep && (search->codeBody != NULL || search->keyVarNameObj != NULL || search->varNameObj != NULL)) {
	Tcl_AppendResult (interp, "can't use -code, -key, -array_get, -array_get_with_nulls  or -get along with -write_tabsep", (char *) NULL);
	return TCL_ERROR;
    }

    if (search->writingTabsepIncludeFieldNames && !search->writingTabsep) {
	Tcl_AppendResult (interp, "can't use -include_field_names without -write_tabsep", (char *) NULL);
	return TCL_ERROR;
    }

    if (search->sortControl.nFields && search->countOnly) {
	Tcl_AppendResult (interp, "it's nuts to -sort something that's a -countOnly anyway", (char *) NULL);
	return TCL_ERROR;
    }

    if (search->useArrayGet + search->useArrayGetWithNulls + search->useGet > 1) {
	Tcl_AppendResult (interp, "-array_get, -array_get_with_nulls and -get options are mutually exclusive", (char *) NULL);
	return TCL_ERROR;
    }

    if (!search->useArrayGet && !search->useArrayGetWithNulls && !search->useGet && !search->writingTabsep && !search->countOnly) {
        Tcl_AppendResult (interp, "one of -array_get, -array_get_with_nulls, -get, -write_tabsep or -countOnly must be specified", (char *)NULL);
	return TCL_ERROR;
    }

    if (search->useArrayGet || search->useArrayGetWithNulls || search->useGet) {
        if (!search->codeBody) {
	    Tcl_AppendResult (interp, "-code must be set if -array_get, -array_get_with_nulls or -get is set", (char *)NULL);
	    return TCL_ERROR;
	}
    }

    return TCL_OK;
}

//
// ctable_TeardownSearch - tear down (free) a search structure and the
//  stuff within it.
//
static void
ctable_TeardownSearch (struct ctableSearchStruct *search) {
    int i;

    if (search->components == NULL) {
        return;
    }

    // teardown components
    for (i = 0; i < search->nComponents; i++) {
	struct ctableSearchComponentStruct  *component = &search->components[i];
	if (component->clientData != NULL) {
	    // this needs to be pluggable
	    if ((component->comparisonType == CTABLE_COMP_MATCH) || (component->comparisonType == CTABLE_COMP_MATCH_CASE)) {
		struct ctableSearchMatchStruct *sm = component->clientData;
		if (sm->type == CTABLE_STRING_MATCH_UNANCHORED) {
		    boyer_moore_teardown (sm);
		}
	    }

	    if (component->row1 != NULL) {
	        ckfree (component->row1);
	    }

	    if (component->row2 != NULL) {
	        ckfree (component->row2);
	    }

	    ckfree (component->clientData);
	}
    }

    ckfree ((void *)search->components);

    if (search->sortControl.fields != NULL) {
        ckfree ((void *)search->sortControl.fields);
        ckfree ((void *)search->sortControl.directions);
    }
}

//
// ctable_SetupAndPerformSearch - setup and perform a search on a table
//
// uses the key-value hash table as the outer loop and requires a full
// brute force search of the entire table.
//
int
ctable_SetupAndPerformSearch (Tcl_Interp *interp, Tcl_Obj *CONST objv[], int objc, struct ctableTable *ctable) {
    struct ctableSearchStruct    search;
    CONST char                 **fieldNames = ctable->creatorTable->fieldNames;
    int                          count = ctable->count;

    if (ctable_SetupSearch (interp, ctable, objv, objc, &search, fieldNames) == TCL_ERROR) {
        return TCL_ERROR;
    }

    if (ctable_PerformSearch (interp, ctable, &search, count) == TCL_ERROR) {
        return TCL_ERROR;
    }

    ctable_TeardownSearch (&search);
    return TCL_OK;
}

//
// ctable_SetupAndPerformSkipSearch - setup and perform a skiplist search
//   on a table.
//
// Uses a skip list index as the outer loop.  Still brute force unless the
// foremost compare routine is tailorable, however even so, much faster
// than a hash table walk.
//
//
int
ctable_SetupAndPerformSkipSearch (Tcl_Interp *interp, Tcl_Obj *CONST objv[], int objc, struct ctableTable *ctable) {
    struct ctableSearchStruct    search;
    CONST char                 **fieldNames = ctable->creatorTable->fieldNames;
    int                          count = ctable->count;

    if (ctable_SetupSearch (interp, ctable, objv, objc, &search, fieldNames) == TCL_ERROR) {
        return TCL_ERROR;
    }

    if (ctable_PerformSkipSearch (interp, ctable, &search, count) == TCL_ERROR) {
        return TCL_ERROR;
    }

    ctable_TeardownSearch (&search);
    return TCL_OK;
}


//
// ctable_DropIndex - delete all the rows in a row's index, free the
// structure and set the field's pointer to the skip list to NULL
//
//
int
ctable_DropIndex (Tcl_Interp *interp, struct ctableTable *ctable, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];

    if (skip == NULL) {
        return TCL_OK;
    }

    ctable->skipLists[field] = NULL;
    jsw_sdelete_skiplist (skip);
    return TCL_OK;
}

//
// ctable_DropAllIndexes - delete all of a table's indexes
//
int
ctable_DropAllIndexes (Tcl_Interp *interp, struct ctableTable *ctable) {
    int field;

    for (field = 0; field < ctable->creatorTable->nFields; field++) {
        if (ctable_DropIndex (interp, ctable, field) != TCL_OK) {
	    return TCL_ERROR;
	}
    }
    return TCL_OK;
}

//
// ctable_IndexCount -- set the Tcl interpreter obj result to the
//                      number of items in the index
//
// mostly just going to be used as a cross-check for testing to make sure
// inserts and deletes into indexes corresponding to changes in rows works
// properly
//
int
ctable_IndexCount (Tcl_Interp *interp, struct ctableTable *ctable, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];
    int         count;

    if (skip == NULL) {
	Tcl_AppendResult (interp, "that field does not have an index", (char *) NULL);
	return TCL_ERROR;
    }

    count = (int)jsw_ssize(skip);
    Tcl_SetObjResult (interp, Tcl_NewIntObj (count));
    return TCL_OK;
}

int
ctable_DumpIndex (Tcl_Interp *interp, struct ctableTable *ctable, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];
    void       *row;
    Tcl_Obj    *utilityObj = Tcl_NewObj ();
    CONST char *s;

    if (skip == NULL) {
        return TCL_OK;
    }

    jsw_dump_head (skip);

    for (jsw_sreset (skip); (row = jsw_srow (skip)) != NULL; jsw_snext(skip)) {
        s = ctable->creatorTable->get_string (row, field, NULL, utilityObj);
	jsw_dump (s, skip, ctable->creatorTable->fields[field]->indexNumber);
    }

    Tcl_DecrRefCount (utilityObj);

    return TCL_OK;
}


//
// ctable_ListIndex - return a list of all of the index values 
//
// warning - can be hugely inefficient if you have a zillion elements
// but useful for testing
//
int
ctable_ListIndex (Tcl_Interp *interp, struct ctableTable *ctable, int fieldNum) {
    jsw_skip_t *skip = ctable->skipLists[fieldNum];
    void       *p;
    Tcl_Obj    *resultObj = Tcl_GetObjResult (interp);

    if (skip == NULL) {
        return TCL_OK;
    }

    for (jsw_sreset (skip); (p = jsw_srow (skip)) != NULL; jsw_snext(skip)) {

        if (ctable->creatorTable->lappend_field (interp, resultObj, p, fieldNum) == TCL_ERROR) {
	    Tcl_AppendResult (interp, " while walking index fields", (char *) NULL);
	    return TCL_ERROR;
	}
    }

    return TCL_OK;
}

int
ctable_RemoveFromIndex (Tcl_Interp *interp, struct ctableTable *ctable, void *vRow, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];
    struct ctable_baseRow *row = vRow;
    int index;

// printf("remove from index field %d\n", field);

    if (skip == NULL) {
// printf("it's null\n");
        return TCL_OK;
    }

#ifdef CTABLE_NODUPS
    if (!jsw_serase (skip, row)) {
        panic ("corrupted index detected for field %s", ctable->creatorTable->fields[field]->name);
    }
#else
    if (ctable_ListRemoveMightBeTheLastOne (row, ctable->creatorTable->fields[field]->indexNumber)) {
// printf("i might be the last one, field %d\n", field);
	index = ctable->creatorTable->fields[field]->indexNumber;
        // it might be the last one, see if it really was
// printf ("row->ll_nodes[index].head %lx\n", (long unsigned int)row->_ll_nodes[index].head);
	if (*row->_ll_nodes[index].head == NULL) {
// printf("erasing last entry field %d\n", field);
            // put the pointer back so the compare routine will have
	    // something to match
            *row->_ll_nodes[index].head = row;
	    if (!jsw_serase (skip, row)) {
		panic ("corrupted index detected for field %s", ctable->creatorTable->fields[field]->name);
	    }
	    // *row->ll_nodex[index].head = NULL; // don't think this is needed
	}
    }
#endif
    return TCL_OK;
}

//
// ctable_RemoveFromAllIndexes -- remove a row from all of the indexes it's
// in -- this does a bidirectional linked list remove for each 
//
//
//
int
ctable_RemoveFromAllIndexes (Tcl_Interp *interp, struct ctableTable *ctable, void *row) {
    int         field;
    
#ifdef CTABLE_NODUPS
	panic ("haven't implemented remove from all indexes for nodups");
#endif

    // everybody's in index 0, take this guy out
    ctable_ListRemove (row, 0);

    // NB slightly gross, we shouldn't have to look at all of the fields
    // to even see which ones could be indexed but the programmer is
    // in a hurry
    for (field = 0; field < ctable->creatorTable->nFields; field++) {
	if (ctable->skipLists[field] != NULL) {
	    ctable_RemoveFromIndex (interp, ctable, row, field);
	}
    }
    return TCL_OK;
}

//
// ctable_InsertIntoIndex - for the given field of the given row of the given
// ctable, insert this row into that table's field's index if there is an
// index on that field.
//
int
ctable_InsertIntoIndex (Tcl_Interp *interp, struct ctableTable *ctable, void *row, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];

    if (skip == NULL) {
    return TCL_OK;
    }

#ifdef CTABLE_NODUPS
    if (!jsw_sinsert (skip, row)) {
	Tcl_AppendResult (interp, "duplicate entry", (char *) NULL);
	return TCL_ERROR;
    }
#else
// printf("ctable_InsertIntoIndex field %d index %d\n", field, ctable->creatorTable->fields[field]->indexNumber);
    jsw_sinsert_linked (skip, row, ctable->creatorTable->fields[field]->indexNumber);
#endif
    return TCL_OK;
}

int
ctable_RemoveNullFromIndex (Tcl_Interp *interp, struct ctableTable *ctable, void *row, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];

    if (skip == NULL) {
        return TCL_OK;
    }

    Tcl_AppendResult (interp, "remove null from index unimplemented", (char *) NULL);
    return TCL_ERROR;
}

int
ctable_InsertNullIntoIndex (Tcl_Interp *interp, struct ctableTable *ctable, void *row, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];

    if (skip == NULL) {
        return TCL_OK;
    }

    Tcl_AppendResult (interp, "insert null into index unimplemented", (char *) NULL);
    return TCL_OK;
}

//
// ctable_CreateIndex - create an index on a specified field of a specified
// ctable.
//
// used to you could index any field but now we can't handle duplicates and
// really anything since we're switching to bidirectionally linked lists
// as targets of skip list nodes.
//
// consequently should make sure the field has an index set up for it
// in the linked list nodes of the row
//
int
ctable_CreateIndex (Tcl_Interp *interp, struct ctableTable *ctable, int field, int depth) {
#ifdef LINKED_LIST
    struct ctable_baseRow *row;
#else
    Tcl_HashTable   *keyTablePtr = ctable->keyTablePtr;
    Tcl_HashEntry   *hashEntry;
    Tcl_HashSearch   hashSearch;
    void            *row;
#endif

    jsw_skip_t      *skip = ctable->skipLists[field];

    // if there's already a skip list, just say "fine"
    // it's debatable if that's really what we want to do.
    // perhaps we should generate an error, but that seems
    // painful to the programmer who uses this tool.

    if (skip != NULL) {
        return TCL_OK;
    }

    if (ctable->creatorTable->fields[field]->indexNumber < 0) {
	Tcl_AppendResult (interp, "can't create an index on a field that hasn't been defined as allowing an index", (char *)NULL);
	return TCL_ERROR;
    }

    skip = jsw_snew (depth, ctable->creatorTable->fields[field]->compareFunction);

    // we plug the list in last
    // we'll have to do a lot more here for concurrent access NB

    ctable->skipLists[field] = skip;

    // yes yes yet another walk through the hash table, in create index?!
    // gotta do it that way until skip lists are solid
#ifdef LINKED_LIST
    CTABLE_LIST_FOREACH (ctable->ll_head, row, 0) {
#else
    for (hashEntry = Tcl_FirstHashEntry (keyTablePtr, &hashSearch); hashEntry != (Tcl_HashEntry *) NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {
	row = Tcl_GetHashValue (hashEntry);
#endif

        // NB do we really want to allow dups?  not necessarily, we need
	// to be able to say.  but sometimes, definitely.  it's tricky.
	// punt for now.
	// also we want to be able to call out to an error handler rather
	// than fail and unwind the stack
	if (ctable_InsertIntoIndex (interp, ctable, row, field) == TCL_ERROR) {
	    Tcl_Obj *utilityObj;

	    // you can't leave them with a partial index or there will
	    // be heck to pay later when queries don't find all the
	    // rows, etc
	    jsw_sdelete_skiplist (skip);
	    ctable->skipLists[field] = NULL;
	    utilityObj = Tcl_NewObj();
	    Tcl_AppendResult (interp, " while creating index \"", ctable->creatorTable->fields[field]->name, "\", value \"", ctable->creatorTable->get_string (row, field, NULL, utilityObj), "\"", (char *) NULL);
	    Tcl_DecrRefCount (utilityObj);
	    return TCL_ERROR;
	}
    }

    return TCL_OK;
}

