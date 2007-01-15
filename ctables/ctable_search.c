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

#include "speedtableHash.c"

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

//
// ctable_ParseSortFieldList - given a Tcl list object, and a pointer to a
// ctable sort structure, store the number of fields in the list in the
// sort structure's field count.  allocate an array of integers for the
// field numbers and directions and store them into the sort structure passed.
//
// Strip the prepending dash of each field, if present, and do the lookup
// and store the field number in the corresponding field number array.
//
// If the dash was present set the corresponding direction in the direction
// array to 0 else set it to 1.
//
// It is up to the caller to free the memory pointed to through the
// fieldList argument.
//
// return TCL_OK if all went according to plan, else TCL_ERROR.
//
//
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

//
// ctable_searchMatchPatternCheck - examine the match pattern to determine
// a strategy for matching the pattern.
//
// If it's anchored, i.e. doesn't start with an asterisk, that's good to know, 
// we'll be real fast.
//
// If it's a pattern, we'll use more full blown pattern matching.
//
// If it's unanchored, we'll use Boyer-Moore to go as fast as we can.
//
// There are oppportunities for optimization here, check out Peter's
// speedtable query optimizer for optimizations the determination of
// which can be made here instead.  Shrug.
//
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
ctable_ParseSearch (Tcl_Interp *interp, CTable *ctable, Tcl_Obj *componentListObj, CONST char **fieldNames, CTableSearch *search) {
    Tcl_Obj    **componentList;
    int          componentIdx;
    int          componentListCount;

    Tcl_Obj    **termList;
    int          termListCount;

    int          field;

    CTableSearchComponent  *components;
    CTableSearchComponent  *component;
    
    // these terms must line up with the CTABLE_COMP_* defines
    static CONST char *searchTerms[] = {"false", "true", "null", "notnull", "<", "<=", "=", "!=", ">=", ">", "match", "notmatch", "match_case", "notmatch_case", "range", "in", (char *)NULL};

    if (Tcl_ListObjGetElements (interp, componentListObj, &componentListCount, &componentList) == TCL_ERROR) {
        return TCL_ERROR;
    }

    if (componentListCount == 0) {
        search->components = NULL;
	return TCL_OK;
    }

    search->nComponents = componentListCount;

    components = (CTableSearchComponent *)ckalloc (componentListCount * sizeof (CTableSearchComponent));

    search->components = components;

    for (componentIdx = 0; componentIdx < componentListCount; componentIdx++) {
        int term;

	if (Tcl_ListObjGetElements (interp, componentList[componentIdx], &termListCount, &termList) == TCL_ERROR) {
	  err:
	    ckfree ((char *)components);
	    return TCL_ERROR;
	}

	if (termListCount < 2) {
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
	component->inListObj = NULL;
	component->inCount = 0;
	component->compareFunction = ctable->creatorTable->fields[field]->compareFunction;

	if (term == CTABLE_COMP_FALSE || term == CTABLE_COMP_TRUE || term == CTABLE_COMP_NULL || term == CTABLE_COMP_NOTNULL) {
	    if (termListCount != 2) {
		Tcl_AppendResult (interp, "false, true, null and notnull search expressions must have only two fields", (char *) NULL);
		goto err;
	    }
	}  else {
	    if (term == CTABLE_COMP_IN) {
	        if (termListCount < 3) {
		    Tcl_AppendResult (interp, "term \"", Tcl_GetString (termList[0]), "\" require at least 3 arguments (term, field, ?value...?)", (char *) NULL);
		    goto err;
		}

		component->inListObj = &termList[2];
		component->inCount = termListCount - 2;
		component->row1 = (*ctable->creatorTable->make_empty_row) ();

	    } else if (term == CTABLE_COMP_RANGE) {
	        void *row;

	        if (termListCount != 4) {
		    Tcl_AppendResult (interp, "term \"", Tcl_GetString (termList[0]), "\" require 4 arguments (term, field, lowValue, highValue)", (char *) NULL);
		    goto err;
		}

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

		continue;

	    } else if (termListCount != 3) {
		Tcl_AppendResult (interp, "term \"", Tcl_GetString (termList[0]), "\" require 3 arguments (term, field, value)", (char *) NULL);
		goto err;
	    }

	    if ((term == CTABLE_COMP_MATCH) || (term == CTABLE_COMP_NOTMATCH) || (term == CTABLE_COMP_MATCH_CASE) || (term == CTABLE_COMP_NOTMATCH_CASE)) {
		struct ctableSearchMatchStruct *sm = (struct ctableSearchMatchStruct *)ckalloc (sizeof (struct ctableSearchMatchStruct));

		sm->type = ctable_searchMatchPatternCheck (Tcl_GetString (termList[2]));
		sm->nocase = ((term == CTABLE_COMP_MATCH) || (term == CTABLE_COMP_NOTMATCH));

		if (sm->type == CTABLE_STRING_MATCH_UNANCHORED) {
		    char *needle;
		    int len;

		    needle = Tcl_GetStringFromObj (termList[2], &len);
		    boyer_moore_setup (sm, (unsigned char *)needle + 1, len - 2, sm->nocase);
		}

		component->clientData = sm;
	    }
	    void *row;

	    /* stash what we want to compare to into a row as in "range"
	     */
	    row = (*ctable->creatorTable->make_empty_row) ();
	    if ((*ctable->creatorTable->set) (interp, ctable, termList[2], row, field, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
		goto err;
	    }
	    component->row1 = row;
	}
    }

    // it worked, leave the components allocated
    return TCL_OK;
}

//
// ctable_SearchAction - Perform the search action on a row that's matched
//  the search criteria.
//
static int
ctable_SearchAction (Tcl_Interp *interp, CTable *ctable, CTableSearch *search, ctable_BaseRow *row) {
    char           *key;
    int             i;
    struct ctableCreatorTable *creatorTable = ctable->creatorTable;

    key = row->hashEntry.key;

    // if we're tab-separated...

    if (search->writingTabsep) {
	Tcl_DString     dString;

	Tcl_DStringInit (&dString);

	// string-append the specified fields, or all fields, tab separated

        if (search->nRetrieveFields < 0) {
	    (*creatorTable->dstring_append_get_tabsep) (key, row, creatorTable->fieldList, creatorTable->nFields, &dString, search->noKeys);
	} else {
	    (*creatorTable->dstring_append_get_tabsep) (key, row, search->retrieveFields, search->nRetrieveFields, &dString, search->noKeys);
	}

        // write the line out

	if (Tcl_WriteChars (search->tabsepChannel, Tcl_DStringValue (&dString), Tcl_DStringLength (&dString)) < 0) {
	    return TCL_ERROR;
	}

	Tcl_DStringFree (&dString);
	return TCL_OK;
    }

    // if there's a code body to eval...

    if (search->codeBody != NULL) {
	Tcl_Obj *listObj = NULL;
	int      evalResult;

	// generate the list of requested fields, or all fields, in
	// "get style" (value only), "array get style" (key-value
	// pairs with nulls suppressed) and "array get with nulls"
	// style, (all requested fields, null or not)

	if (search->useGet) {
	    if (search->nRetrieveFields < 0) {
		listObj = (*creatorTable->gen_list) (interp, row);
	    } else {
	       int i;

	       listObj = Tcl_NewObj ();
	       for (i = 0; i < search->nRetrieveFields; i++) {
		   creatorTable->lappend_field (interp, listObj, row, creatorTable->fieldList[i]);
	       }
	    }
	} else if (search->useArrayGet) {
	    if (search->nRetrieveFields < 0) {
	       int i;

	       listObj = Tcl_NewObj ();
	       for (i = 0; i < creatorTable->nFields; i++) {
		   creatorTable->lappend_nonnull_field_and_name (interp, listObj, row, i);
	       }
	    } else {
	       int i;

	       listObj = Tcl_NewObj ();
	       for (i = 0; i < search->nRetrieveFields; i++) {
		   creatorTable->lappend_nonnull_field_and_name (interp, listObj, row, search->retrieveFields[i]);
	       }
	    }
	} else if (search->useArrayGetWithNulls) {
	    if (search->nRetrieveFields < 0) {
		listObj = (*creatorTable->gen_keyvalue_list) (interp, row);
	    } else {
	       listObj = Tcl_NewObj ();
		for (i = 0; i < search->nRetrieveFields; i++) {
		    creatorTable->lappend_field_and_name (interp, listObj, row, search->retrieveFields[i]);
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

	// evaluate the code body
	//
	// By using a Tcl object for the code body, the code body will be
        // on-the-fly compiled by Tcl once and cached on subsequent
	// evals.  Cool.
	//
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
// ctable_WriteFieldNames - write field names from a search structure to
//   the specified channel, tab-separated
//
//
static int
ctable_WriteFieldNames (Tcl_Interp *interp, CTable *ctable, CTableSearch *search)
{
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
        Tcl_DStringAppend (&dString, "_key", 4);
    }

    for (i = 0; i < nFields; i++) {
	if (!search->noKeys || i != 0) {
	    Tcl_DStringAppend(&dString, "\t", 1);
	}

	Tcl_DStringAppend(&dString, ctable->creatorTable->fields[i]->name, -1);
    }
    Tcl_DStringAppend(&dString, "\n", 1);

    if (Tcl_WriteChars (search->tabsepChannel, Tcl_DStringValue (&dString), Tcl_DStringLength (&dString)) < 0) {
	Tcl_DStringFree (&dString);
	return TCL_ERROR;
    }

    Tcl_DStringFree (&dString);
    return TCL_OK;
}

//
// ctable_PostSearchCommonActions - actions taken at the end of a search
//
// If results sorting is required, we sort the results.
//
// We interpret start and offset, if set, to limit rows returned.
//
// We walk the sort results, calling ctable_SearchAction on each.
//
//
static int
ctable_PostSearchCommonActions (Tcl_Interp *interp, CTable *ctable, CTableSearch *search)
{
    int sortIndex;

    // if we're not sorting, we're done -- we did 'em all on the fly
    if (search->sortTable == NULL) {
        return TCL_OK;
    }

    qsort_r (search->sortTable, search->matchCount, sizeof (ctable_HashEntry *), &search->sortControl, ctable->creatorTable->sort_compare);

    // it's sorted
    // now let's see what we've got within the offset and limit

    // if the offset's more than the matchCount, they got nuthin'
    if (search->offset > search->matchCount) {
        return TCL_OK;
    }

    // figure out the last row they could want, if it's more than what's
    // there, set it down to what came back
    if ((search->offsetLimit == 0) || (search->offsetLimit > search->matchCount)) {
        search->offsetLimit = search->matchCount;
    }

    // walk the result
    for (sortIndex = search->offset; sortIndex < search->offsetLimit; sortIndex++) {
        int actionResult;

	/* here is where we want to take the match actions
	 * when we are sorting
	 */
	 actionResult = ctable_SearchAction (interp, ctable, search, search->sortTable[sortIndex]);
	 if (actionResult == TCL_CONTINUE || actionResult == TCL_OK) {
	     continue;
	 }

	 if (actionResult == TCL_BREAK || actionResult == TCL_RETURN) {
	     return TCL_OK;
	 }

	 if (actionResult == TCL_ERROR) {
	     return TCL_ERROR;
	 }
    }

    return TCL_OK;
}

//
// ctable_SearchCompareRow - perform comparisons on a row
//
inline static int
ctable_SearchCompareRow (Tcl_Interp *interp, CTable *ctable, CTableSearch *search, ctable_BaseRow *row)
{
    int   compareResult;
    int   actionResult;

    // if we have a match pattern (for the key) and it doesn't match,
    // skip this row

    if (search->pattern != (char *) NULL) {
	if (!Tcl_StringCaseMatch (row->hashEntry.key, search->pattern, 1)) {
	    return TCL_CONTINUE;
	}
    }

    //
    // run the supplied compare routine
    //
    compareResult = (*ctable->creatorTable->search_compare) (interp, search, (void *)row, search->tailoredWalk);
    if (compareResult == TCL_CONTINUE) {
	return TCL_CONTINUE;
    }

    if (compareResult == TCL_ERROR) {
	return TCL_ERROR;
    }

    // It's a Match 
    // Are we sorting? Plop the match in the sort table and return

    if (search->sortTable != NULL) {
	/* We are sorting, grab it, we gotta sort before we can run
	 * against start and limit and stuff */
	assert (search->matchCount < ctable->count);
	search->sortTable[search->matchCount++] = row;
	return TCL_CONTINUE;
    }

    // We're not sorting, let's figure out what to do as we match.
    // If we haven't met the start point, blow it off.
    if (++search->matchCount <= search->offset) {
	return TCL_CONTINUE;
    }

    if (search->countOnly) {
	// we're only counting -- if there is a limit and it's been 
	// met, we're done
	if ((search->limit != 0) && (search->matchCount >= search->offsetLimit)) {
	    return TCL_BREAK;
	}

	// the limit hasn't been exceeded or there isn't one,
	// so we keep counting -- but we continue here because
	// we don't need to do any processing on the line
	return TCL_CONTINUE;
    }

    /* we want to take the match actions here --
     * we're here when we aren't sorting
     */
     actionResult = ctable_SearchAction (interp, ctable, search, row);
     if (actionResult == TCL_ERROR) {
	  return TCL_ERROR;
     }

     if ((actionResult == TCL_CONTINUE) || (actionResult == TCL_OK)) {
	// if there was a limit and we've met it, we're done
	if ((search->limit != 0) && (search->matchCount >= search->offsetLimit)) {
	    return TCL_BREAK;
	}
	return TCL_CONTINUE;
     }

     if ((actionResult == TCL_BREAK) || (actionResult == TCL_RETURN)) {
	 return TCL_BREAK;
     }

     panic("software failure - unhandled SearchAction return");
     return TCL_ERROR;
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
static int
ctable_PerformSearch (Tcl_Interp *interp, CTable *ctable, CTableSearch *search) {
    int                    compareResult;
    int                    actionResult = TCL_OK;
    ctable_BaseRow        *row;

    search->matchCount = 0;
    search->tailoredWalk = 0;
    search->sortTable = NULL;
    search->offsetLimit = search->offset + search->limit;

    if (search->writingTabsepIncludeFieldNames) {
	ctable_WriteFieldNames (interp, ctable, search);
    }

    if (ctable->count == 0) {
        return TCL_OK;
    }

    // if we're sorting, allocate a space for the search results that
    // we'll then sort from
    if ((search->sortControl.nFields > 0) && (!search->countOnly)) {
	search->sortTable = (ctable_BaseRow **)ckalloc (sizeof (void *) * ctable->count);
    }

    // walk the table 
    CTABLE_LIST_FOREACH (ctable->ll_head, row, 0) {

	compareResult = ctable_SearchCompareRow (interp, ctable, search, row);
	if ((compareResult == TCL_CONTINUE) || (compareResult == TCL_OK)) continue;

	if (compareResult == TCL_BREAK) break;

	if (compareResult == TCL_ERROR) {
	    actionResult = TCL_ERROR;
	    goto clean_and_return;
	}
    }

    actionResult = ctable_PostSearchCommonActions (interp, ctable, search);
  clean_and_return:
    if (search->sortTable != NULL) {
	ckfree ((void *)search->sortTable);
    }

    if (actionResult == TCL_OK && search->countOnly) {
	Tcl_SetIntObj (Tcl_GetObjResult (interp), search->matchCount);
    }

    return actionResult;
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
ctable_PerformSkipSearch (Tcl_Interp *interp, CTable *ctable, CTableSearch *search) {
    int              compareResult;
    int              actionResult = TCL_OK;

    struct ctableCreatorTable *creatorTable = ctable->creatorTable;

    ctable_BaseRow          *row = NULL;
    ctable_BaseRow          *row1 = NULL;
    ctable_BaseRow          *walkRow;
    void                    *row2 = NULL;

    jsw_skip_t      *skip = NULL;
    int              field = 0;

    fieldCompareFunction_t compareFunction;
    int                    indexNumber;
    int                    tailoredTerm = 0;

    int                    inIndex = 0; // used when handling {in ...}
    int                    normal = 1;


    search->matchCount = 0;
    search->tailoredWalk = 0;
    search->sortTable = NULL;
    search->offsetLimit = search->offset + search->limit;

    if (search->writingTabsepIncludeFieldNames) {
	ctable_WriteFieldNames (interp, ctable, search);
    }

    if (ctable->count == 0) {
        return TCL_OK;
    }

    // if we're sorting, allocate a space for the search results that
    // we'll then sort from
    if ((search->sortControl.nFields > 0) && (!search->countOnly)) {
        search->sortTable = (ctable_BaseRow **)ckalloc (ctable->count * sizeof (void *));
    }

    // if the first compare thing is something we understand how to do
    // with indexed fields and the field they're asking for us to do it
    // on happens to be indexed, we need to do special walking magic

    // else find any index column

    // if there's no index column, we need to fail or revert to brute force
    // at least for now

    if (search->nComponents > 0) {
	CTableSearchComponent *component = &search->components[0];

	field = component->fieldID;
	tailoredTerm = component->comparisonType;
        if (ctable->skipLists[field] != NULL) {
	    if ((tailoredTerm == CTABLE_COMP_RANGE) || (tailoredTerm == CTABLE_COMP_EQ) || (tailoredTerm = CTABLE_COMP_IN)) {
		// ding ding ding - we have a winner, time for an accelerated
		// search
		search->tailoredWalk = 1;
		skip = ctable->skipLists[field];

		if (tailoredTerm == CTABLE_COMP_IN) {
		    normal = 0;
		} else {
		    row1 = component->row1;
		    row2 = component->row2;
		}
	    }
        }
    }

    // right here if we don't have a tailored walk we can see if there is
    // a sort and if there is and it's only one field (no subfield for
    // sorting) and that field exists as an index we can do a skip list
    // walk and not save up and do the sort
    //
    // if we don't have that and we don't have a range or something else
    // that's going to help the search be fast, switch to brute force
    //

    // if we don't have a tailored walk, see if we have any skip list
    // we can use
    if (!search->tailoredWalk) {
        int i;

	// find the first index used in any search expression from left to right
	for (i = 0; i < search->nComponents; i++) {
	    CTableSearchComponent *component = &search->components[i];

	    if ((skip = ctable->skipLists[component->fieldID]) != NULL) {
	        // printf("not tailored walk, found index on field %d\n", component->fieldID);
	        break;
	    }
	}

        // no relevant skip list?  see if we can find any 
	if (skip == NULL) {
	    for (field= 0; field < creatorTable->nFields; field++) {
		if ((skip = ctable->skipLists[field]) != NULL) {
		    // printf("not tailored walk, found arbitrary index on field %d\n", field);
		    break;
		}
	    }
	}
    }

    if (skip == NULL) {
	Tcl_AppendResult (interp, "no field has an index, can't perform tailored search, sorry", (char *) NULL);
	actionResult = TCL_ERROR;
	goto clean_and_return;
    }

    if (search->tailoredWalk && normal) {
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
    // curl = ((struct jsw_skip *)skip)->curl;

    compareFunction = creatorTable->fields[field]->compareFunction;
    indexNumber = creatorTable->fields[field]->indexNumber;

    // for (; ((row = jsw_srow (skip)) != NULL); jsw_snext(skip)) {

    // DO NOT use continue to continue, you have to "goto contin" because
    // we have multiple ways we want to do for loops and we can't pull
    // it off that way -- we have the loops set out into an explicit
    // before assignment, a comparison to see if we're done, and a
    // move-to-the-next piece, and the move-to-the-next piece has to
    // be explicitly called out as there are different possible pathways.

    while (1) {

      if (normal) {
          if ((row = jsw_srow (skip)) == NULL) break;

	  if (search->tailoredWalk) {
	      if (tailoredTerm == CTABLE_COMP_RANGE) {
		  if (compareFunction (row, row2) >= 0) {
		     // it was a tailored walk and we're past the end of the
		     // range of stuff so we can blow off the rest, hopefully
		     // a huge number
		    break;
		}
	      } else if (tailoredTerm == CTABLE_COMP_EQ) {
		  if (compareFunction (row, row1) != 0) {
		      break;
		  }
	      } else {
		  // it may not be an error to not have a terminating condition 
		  // on a tailored walk
		  // panic("software failure - no terminating condition for tailored walk");
	      }
	  }
      } else {
	  if ((tailoredTerm == CTABLE_COMP_IN) && (search->tailoredWalk)) {
	      CTableSearchComponent *component = &search->components[0];

	      if (inIndex >= component->inCount) break;

	      if ((*ctable->creatorTable->set) (interp, ctable, component->inListObj[inIndex], component->row1, field, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
	          Tcl_AppendResult (interp, " while processing \"in\" compare function", (char *) NULL);
		  actionResult = TCL_ERROR;
		  goto clean_and_return;
	      }

	      if (jsw_sfind (skip, component->row1) == NULL) goto contin;
	      row = jsw_srow (skip);
	  } else {
	      panic ("unexpected code path in ctable_PerformSkipSearch");
	  }
      }

      // walk walkRow through the linked list of rows off this skip list node
      // if you ever change this to make deletion possible while searching,
      // switch this to use the safe foreach routine instead

      CTABLE_LIST_FOREACH (row, walkRow, indexNumber) {
	compareResult = ctable_SearchCompareRow (interp, ctable, search, walkRow);
	if ((compareResult == TCL_CONTINUE) || (compareResult == TCL_OK)) continue;

	if (compareResult == TCL_BREAK) {
	    actionResult = TCL_OK;
	    goto clean_and_return;
	}

	if (compareResult == TCL_ERROR) {
	    actionResult = TCL_ERROR;
	    goto clean_and_return;
	}
      }

    contin:

      if (normal) {
	  jsw_snext(skip);
      } else {
          if ((tailoredTerm == CTABLE_COMP_IN) && (search->tailoredWalk)) {
	      inIndex++;
	  }
      }
    }

    actionResult = ctable_PostSearchCommonActions (interp, ctable, search);
  clean_and_return:
    if (search->sortTable != NULL) {
	ckfree ((void *)search->sortTable);
    }

    if (actionResult == TCL_OK && search->countOnly) {
	Tcl_SetIntObj (Tcl_GetObjResult (interp), search->matchCount);
    }

    return actionResult;
}

//
// ctable_SetupSearch - prepare to search by parsing the command line arguments
// specified when the ctables "search" method is invoked.
//
//
static int
ctable_SetupSearch (Tcl_Interp *interp, CTable *ctable, Tcl_Obj *CONST objv[], int objc, CTableSearch *search) {
    int             i;
    int             searchTerm = 0;
    CONST char                 **fieldNames = ctable->creatorTable->fieldNames;

    static CONST char *searchOptions[] = {"-array_get", "-array_get_with_nulls", "-code", "-compare", "-countOnly", "-fields", "-get", "-glob", "-key", "-include_field_names", "-limit", "-noKeys", "-offset", "-regexp", "-sort", "-write_tabsep", (char *)NULL};

    enum searchOptions {SEARCH_OPT_ARRAYGET_NAMEOBJ, SEARCH_OPT_ARRAYGETWITHNULLS_NAMEOBJ, SEARCH_OPT_CODE, SEARCH_OPT_COMPARE, SEARCH_OPT_COUNTONLY, SEARCH_OPT_FIELDS, SEARCH_OPT_GET_NAMEOBJ, SEARCH_OPT_GLOB, SEARCH_OPT_KEYVAR_NAMEOBJ, SEARCH_OPT_INCLUDE_FIELD_NAMES, SEARCH_OPT_LIMIT, SEARCH_OPT_DONT_INCLUDE_KEY, SEARCH_OPT_OFFSET, SEARCH_OPT_REGEXP, SEARCH_OPT_SORT, SEARCH_OPT_WRITE_TABSEP};

    if (objc < 2) {
      wrong_args:
	Tcl_WrongNumArgs (interp, 2, objv, "?-array_get varName? ?-array_get_with_nulls varName? ?-code codeBody? ?-compare list? ?-countOnly 0|1? ?-fields fieldList? ?-get varName? ?-glob pattern? ?-key varName? ?-include_field_names 0|1?  ?-limit limit? ?-noKeys 0|1? ?-offset offset? ?-regexp pattern? ?-sort {?-?field1..}? ?-write_tabsep channel?");
	return TCL_ERROR;
    }

    // initialize search control structure
    search->ctable = ctable;
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
ctable_TeardownSearch (CTableSearch *search) {
    int i;

    if (search->components == NULL) {
        return;
    }

    // teardown components
    for (i = 0; i < search->nComponents; i++) {
	CTableSearchComponent  *component = &search->components[i];
	if (component->clientData != NULL) {

	    if (component->row1 != NULL) {
	        search->ctable->creatorTable->delete (search->ctable, component->row1, CTABLE_INDEX_PRIVATE);
	    }

	    if (component->row2 != NULL) {
	        search->ctable->creatorTable->delete (search->ctable, component->row2, CTABLE_INDEX_PRIVATE);
	    }

	    // this needs to be pluggable
	    if ((component->comparisonType == CTABLE_COMP_MATCH) || (component->comparisonType == CTABLE_COMP_NOTMATCH) || (component->comparisonType == CTABLE_COMP_MATCH_CASE) || (component->comparisonType == CTABLE_COMP_NOTMATCH_CASE)) {
		struct ctableSearchMatchStruct *sm = component->clientData;
		if (sm->type == CTABLE_STRING_MATCH_UNANCHORED) {
		    boyer_moore_teardown (sm);
		}
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
ctable_SetupAndPerformSearch (Tcl_Interp *interp, Tcl_Obj *CONST objv[], int objc, CTable *ctable) {
    CTableSearch    search;

    if (ctable_SetupSearch (interp, ctable, objv, objc, &search) == TCL_ERROR) {
        return TCL_ERROR;
    }

    if (ctable_PerformSearch (interp, ctable, &search) == TCL_ERROR) {
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
ctable_SetupAndPerformSkipSearch (Tcl_Interp *interp, Tcl_Obj *CONST objv[], int objc, CTable *ctable) {
    CTableSearch    search;

    if (ctable_SetupSearch (interp, ctable, objv, objc, &search) == TCL_ERROR) {
        return TCL_ERROR;
    }

    if (ctable_PerformSkipSearch (interp, ctable, &search) == TCL_ERROR) {
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
void
ctable_DropIndex (CTable *ctable, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];

    if (skip == NULL) return;

    ctable->skipLists[field] = NULL;
    jsw_sdelete_skiplist (skip);
}

//
// ctable_DropAllIndexes - delete all of a table's indexes
//
void
ctable_DropAllIndexes (CTable *ctable) {
    int field;

    for (field = 0; field < ctable->creatorTable->nFields; field++) {
        ctable_DropIndex (ctable, field);
    }
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
ctable_IndexCount (Tcl_Interp *interp, CTable *ctable, int field) {
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
ctable_DumpIndex (Tcl_Interp *interp, CTable *ctable, int field) {
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
ctable_ListIndex (Tcl_Interp *interp, CTable *ctable, int fieldNum) {
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

inline void
ctable_RemoveFromIndex (CTable *ctable, void *vRow, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];
    ctable_BaseRow *row = vRow;
    int index;

// printf("remove from index field %d\n", field);

    if (skip == NULL) {
// printf("it's null\n");
        return;
    }

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

    return;
}

//
// ctable_RemoveFromAllIndexes -- remove a row from all of the indexes it's
// in -- this does a bidirectional linked list remove for each 
//
//
//
void
ctable_RemoveFromAllIndexes (CTable *ctable, void *row) {
    int         field;
    
    // everybody's in index 0, take this guy out
    ctable_ListRemove (row, 0);

    // NB slightly gross, we shouldn't have to look at all of the fields
    // to even see which ones could be indexed but the programmer is
    // in a hurry
    for (field = 0; field < ctable->creatorTable->nFields; field++) {
	if (ctable->skipLists[field] != NULL) {
	    ctable_RemoveFromIndex (ctable, row, field);
	}
    }
}

//
// ctable_InsertIntoIndex - for the given field of the given row of the given
// ctable, insert this row into that table's field's index if there is an
// index on that field.
//
inline int
ctable_InsertIntoIndex (Tcl_Interp *interp, CTable *ctable, void *row, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];
    struct ctableFieldInfo *f;
    Tcl_Obj *utilityObj;

    if (skip == NULL) {
    return TCL_OK;
    }

    f = ctable->creatorTable->fields[field];

# if 0
// dump info about row being inserted
utilityObj = Tcl_NewObj();
printf("ctable_InsertIntoIndex field %d, field name %s, index %d, value %s\n", field, f->name, f->indexNumber, ctable->creatorTable->get_string (row, field, NULL, utilityObj));
Tcl_DecrRefCount (utilityObj);
#endif

    if (!jsw_sinsert_linked (skip, row, f->indexNumber, f->unique)) {

	utilityObj = Tcl_NewObj();
	Tcl_AppendResult (interp, "unique check failed for field \"", f->name, "\", value \"", ctable->creatorTable->get_string (row, field, NULL, utilityObj), "\"", (char *) NULL);
	Tcl_DecrRefCount (utilityObj);
        return TCL_ERROR;
    }
    return TCL_OK;
}

inline int
ctable_RemoveNullFromIndex (Tcl_Interp *interp, CTable *ctable, void *row, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];

    if (skip == NULL) {
        return TCL_OK;
    }

    Tcl_AppendResult (interp, "remove null from index unimplemented", (char *) NULL);
    return TCL_ERROR;
}

inline int
ctable_InsertNullIntoIndex (Tcl_Interp *interp, CTable *ctable, void *row, int field) {
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
ctable_CreateIndex (Tcl_Interp *interp, CTable *ctable, int field, int depth) {
    ctable_BaseRow *row;

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
    CTABLE_LIST_FOREACH (ctable->ll_head, row, 0) {
	// we want to be able to call out to an error handler rather
	// than fail and unwind the stack.
	// (not here so much as in read_tabsep because here we just unwind
	// and undo the new index if we get an error)
	if (ctable_InsertIntoIndex (interp, ctable, row, field) == TCL_ERROR) {
	    Tcl_Obj *utilityObj;

	    // you can't leave them with a partial index or there will
	    // be heck to pay later when queries don't find all the
	    // rows, etc
	    jsw_sdelete_skiplist (skip);
	    ctable->skipLists[field] = NULL;
	    utilityObj = Tcl_NewObj();
	    Tcl_AppendResult (interp, " while creating index", (char *) NULL);
	    Tcl_DecrRefCount (utilityObj);
	    return TCL_ERROR;
	}
    }

    return TCL_OK;
}

int
ctable_LappendIndexLowAndHi (Tcl_Interp *interp, CTable *ctable, int field) {
    jsw_skip_t            *skip = ctable->skipLists[field];
    ctable_BaseRow        *row;
    Tcl_Obj               *resultObj = Tcl_GetObjResult (interp);

    if (skip == NULL) {
	Tcl_AppendResult (interp, "that field isn't indexed", (char *)NULL);
	return TCL_ERROR;
    }

    jsw_sreset (skip);
    row = jsw_srow (skip);

    if (row == NULL) {
        return TCL_OK;
    }

    if (ctable->creatorTable->lappend_field (interp, resultObj, row, ctable->creatorTable->fieldList[field]) == TCL_ERROR) {
        return TCL_ERROR;
    }

    jsw_findlast (skip);
    row = jsw_srow (skip);

    if (ctable->creatorTable->lappend_field (interp, resultObj, row, ctable->creatorTable->fieldList[field]) == TCL_ERROR) {
        return TCL_ERROR;
    }

    return TCL_OK;
}

