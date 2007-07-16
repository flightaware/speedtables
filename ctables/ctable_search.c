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

#include "ctable_batch.c"

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
ctable_ParseSortFieldList (Tcl_Interp *interp, Tcl_Obj *fieldListObj, CONST char **fieldNames, CTableSort *sort) {
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
if(!s) panic("ctable_searchMatchPatternCheck called with null");

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

    // first char is not star, last char is not star, and there are
    // no other metacharacters in the string. This is bad because they
    // should be using "=" not "match" but we'll use pattern because
    // that will actually do the right thing.  alternatively we could
    // add another string match pattern type
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
	component->compareFunction = ctable->creator->fields[field]->compareFunction;

	if (term == CTABLE_COMP_FALSE || term == CTABLE_COMP_TRUE || term == CTABLE_COMP_NULL || term == CTABLE_COMP_NOTNULL) {
	    if (termListCount != 2) {
		Tcl_AppendResult (interp, "false, true, null and notnull search expressions must have only two fields", (char *) NULL);
		goto err;
	    }
	}  else {
	    if (term == CTABLE_COMP_IN) {
	        if (termListCount != 3) {
		    Tcl_AppendResult (interp, "term \"", Tcl_GetString (termList[0]), "\" require 3 arguments (term, field, list)", (char *) NULL);
		    goto err;
		}

		if (Tcl_ListObjGetElements (interp, termList[2], &component->inCount, &component->inListObj) == TCL_ERROR) {
		    goto err;
		}

		component->row1 = (*ctable->creator->make_empty_row) ();

	    } else if (term == CTABLE_COMP_RANGE) {
	        void *row;

	        if (termListCount != 4) {
		    Tcl_AppendResult (interp, "term \"", Tcl_GetString (termList[0]), "\" require 4 arguments (term, field, lowValue, highValue)", (char *) NULL);
		    goto err;
		}

		row = (*ctable->creator->make_empty_row) ();
		if ((*ctable->creator->set) (interp, ctable, termList[2], row, field, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
		    goto err;
		}
		component->row1 = row;

		row = (*ctable->creator->make_empty_row) ();
		if ((*ctable->creator->set) (interp, ctable, termList[3], row, field, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
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
	    row = (*ctable->creator->make_empty_row) ();
	    if ((*ctable->creator->set) (interp, ctable, termList[2], row, field, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
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
    ctable_CreatorTable *creator = ctable->creator;

    key = row->hashEntry.key;

    if (search->endAction == CTABLE_SEARCH_ACTION_WRITE_TABSEP) {
	Tcl_DString     dString;

	Tcl_DStringInit (&dString);

	// string-append the specified fields, or all fields, tab separated

	if (search->nRetrieveFields < 0) {
	    (*creator->dstring_append_get_tabsep) (key, row, creator->publicFieldList, creator->nPublicFields, &dString, search->noKeys);
	} else {
	    (*creator->dstring_append_get_tabsep) (key, row, search->retrieveFields, search->nRetrieveFields, &dString, search->noKeys);
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

	switch (search->endAction) {

	  case CTABLE_SEARCH_ACTION_GET: {
	    if (search->nRetrieveFields < 0) {
		listObj = creator->gen_list (interp, row);
	    } else {
	       int i;

	       listObj = Tcl_NewObj ();
	       for (i = 0; i < search->nRetrieveFields; i++) {
		   creator->lappend_field (interp, listObj, row, creator->fieldList[i]);
	       }
	    }
	    break;
	  }

	  case CTABLE_SEARCH_ACTION_ARRAY_WITH_NULLS:
	  case CTABLE_SEARCH_ACTION_ARRAY: {
	   int result = TCL_OK;

	    if (search->nRetrieveFields < 0) {
	       int i;

	       for (i = 0; i < creator->nFields; i++) {
		   if (is_hidden_field(creator,i)) {
		       continue;
		   }
	           if (search->endAction == CTABLE_SEARCH_ACTION_ARRAY) {
		       result = creator->array_set (interp, search->varNameObj, row, i);
		   } else {
		       result = creator->array_set_with_nulls (interp, search->varNameObj, row, i);
		   }
	       }
	    } else {
	       int i;

	       for (i = 0; i < search->nRetrieveFields; i++) {
	           if (search->endAction == CTABLE_SEARCH_ACTION_ARRAY) {
		       if (is_hidden_field(creator,i)) {
		           continue;
		       }
		       result = creator->array_set (interp, search->varNameObj, row, search->retrieveFields[i]);
		   } else {
		       result = creator->array_set_with_nulls (interp, search->varNameObj, row, search->retrieveFields[i]);
		   }
	       }
	    }

	    if (result != TCL_OK) {
	        return result;
	    }
	    break;
	  }

	  case CTABLE_SEARCH_ACTION_ARRAY_GET: {
	    int i;

	    listObj = Tcl_NewObj ();
	    if (search->nRetrieveFields < 0) {
		for (i = 0; i < creator->nFields; i++) {
		    if (is_hidden_field(creator,i)) {
			continue;
		    }
		    creator->lappend_nonnull_field_and_name (interp, listObj, row, i);
		 }
	    } else {
		for (i = 0; i < search->nRetrieveFields; i++) {
		    creator->lappend_nonnull_field_and_name (interp, listObj, row, search->retrieveFields[i]);
		}
	    }
	    break;
	  }

	  case CTABLE_SEARCH_ACTION_ARRAY_GET_WITH_NULLS: {
	    int i;

	    listObj = Tcl_NewObj ();
	    if (search->nRetrieveFields < 0) {
		for (i = 0; i < creator->nFields; i++) {
		    if (is_hidden_field(creator,i)) {
			continue;
		    }
		    creator->lappend_field_and_name (interp, listObj, row, i);
		}
	    } else {
		listObj = Tcl_NewObj ();
		for (i = 0; i < search->nRetrieveFields; i++) {
		    creator->lappend_field_and_name (interp, listObj, row, search->retrieveFields[i]);
		}
	    }
	    break;
	  }

	  default: {
	      if (search->keyVarNameObj == NULL) {
	          panic ("software failure - unhandled search action");
	      }
	  }
	}

	// if the key var is defined, set the key into it
	if (search->keyVarNameObj != NULL) {
	    if (Tcl_ObjSetVar2 (interp, search->keyVarNameObj, (Tcl_Obj *)NULL, Tcl_NewStringObj (key, -1), TCL_LEAVE_ERR_MSG) == (Tcl_Obj *) NULL) {
		return TCL_ERROR;
	    }
	}

	// set the returned list into the value var
	if ((listObj != NULL) && (Tcl_ObjSetVar2 (interp, search->varNameObj, (Tcl_Obj *)NULL, listObj, TCL_LEAVE_ERR_MSG) == (Tcl_Obj *) NULL)) {
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
    Tcl_DString          dString;
    int                 *fields;
    int                  nFields;
    ctable_CreatorTable *creator = ctable->creator;

    Tcl_DStringInit (&dString);

    if (search->nRetrieveFields < 0) {
	fields = creator->publicFieldList;
	nFields = creator->nPublicFields;
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

	Tcl_DStringAppend(&dString, creator->fields[fields[i]]->name, -1);
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
// ctable_PerformTransactions - atomic actions taken at the end of a search
//
static int
ctable_PerformTransaction (Tcl_Interp *interp, CTable *ctable, CTableSearch *search)
{
    int fieldIndex, rowIndex;
    ctable_CreatorTable *creator = ctable->creator;

    if(search->tranType == CTABLE_SEARCH_TRAN_NONE) {
	return TCL_OK;
    }

    if(search->tranType == CTABLE_SEARCH_TRAN_DELETE) {

      // walk the result and delete the matched rows
      for (rowIndex = search->offset; rowIndex < search->offsetLimit; rowIndex++) {
	  (*creator->delete) (ctable, search->tranTable[rowIndex], CTABLE_INDEX_NORMAL);
	  ctable->count--;
      }

      return TCL_OK;

    }

    if(search->tranType == CTABLE_SEARCH_TRAN_UPDATE) {

	int objc;
	Tcl_Obj **objv;
	int *updateFields;

	// Convert the tranData field into a list
        if (Tcl_ListObjGetElements (interp, search->tranData, &objc, &objv) == TCL_ERROR) {
updateParseError:
	    Tcl_AppendResult (interp, " parsing argument to -update", (char *)NULL);
	    return TCL_ERROR;
	}

	if(objc & 1) {
	    Tcl_AppendResult (interp, "-update list must contain an even number of elements", (char *)NULL);
            return TCL_ERROR;
        }

	// get some space for the field indices
	updateFields = (int *)ckalloc (sizeof (int) * (objc/2));

	// Convert the names to field indices
	for(fieldIndex = 0; fieldIndex < objc/2; fieldIndex++) {
	    if (Tcl_GetIndexFromObj (interp, objv[fieldIndex*2], creator->fieldNames, "field", TCL_EXACT, &updateFields[fieldIndex]) != TCL_OK) {
		ckfree((void *)updateFields);
		goto updateParseError;
	    }
	}

	// Perform update
        for (rowIndex = search->offset; rowIndex < search->offsetLimit; rowIndex++) {
	    void *row = search->tranTable[rowIndex];

	    for(fieldIndex = 0; fieldIndex < objc/2; fieldIndex++) {
		if((*creator->set)(interp, ctable, objv[fieldIndex*2+1], row, updateFields[fieldIndex], CTABLE_INDEX_NORMAL) == TCL_ERROR) {
		    ckfree((void *)updateFields);
		    Tcl_AppendResult (interp, " (update may be incomplete)", (char *)NULL);
		    return TCL_ERROR;
		}
	    }
	}

	ckfree((void *)updateFields);

        return TCL_OK;
    }

    Tcl_AppendResult(interp, "internal error - unknown transaction type %d", search->tranType);

    return TCL_ERROR;
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
// If transaction processing is required, we call ctable_PerformTransactions
//
//
static int
ctable_PostSearchCommonActions (Tcl_Interp *interp, CTable *ctable, CTableSearch *search)
{
    int sortIndex;
    ctable_CreatorTable *creator = ctable->creator;

    // if we're not sorting or performing a transaction, we're done -- we did 'em all on the fly
    if (search->tranTable == NULL) {
        return TCL_OK;
    }

    // if there was nothing matched, or we're before the offset, we're done
    if(search->matchCount == 0 || search->offset > search->matchCount) {
	return TCL_OK;
    }

    // figure out the last row they could want, if it's more than what's
    // there, set it down to what came back
    if ((search->offsetLimit == 0) || (search->offsetLimit > search->matchCount)) {
        search->offsetLimit = search->matchCount;
    }

    if(search->sortControl.nFields) {	// sorting
      qsort_r (search->tranTable, search->matchCount, sizeof (ctable_HashEntry *), &search->sortControl, creator->sort_compare);
    }

    if(search->bufferResults) { // we deferred the operation to here
      // walk the result
      for (sortIndex = search->offset; sortIndex < search->offsetLimit; sortIndex++) {
        int actionResult;

	/* here is where we want to take the match actions
	 * when we are sorting or otherwise buffering
	 */
	 actionResult = ctable_SearchAction (interp, ctable, search, search->tranTable[sortIndex]);
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
    }

    // Finally, perform any pending transaction.
    if(search->tranType != CTABLE_SEARCH_TRAN_NONE) {
	if (ctable_PerformTransaction(interp, ctable, search) == TCL_ERROR) {
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
    compareResult = (*ctable->creator->search_compare) (interp, search, (void *)row);

    if (compareResult == TCL_CONTINUE) {
	return TCL_CONTINUE;
    }

    if (compareResult == TCL_ERROR) {
	return TCL_ERROR;
    }

    // It's a Match 
    // Are we sorting? Plop the match in the sort table and return
    // Increment count in this block to make sure it's incremented in all
    // paths.

    if (search->tranTable == NULL) {
	++search->matchCount;
    } else {
	/* We are sorting or doing a transaction, grab it. If we're sorting,
	 * return because we gotta sort before we can compare
	 * against start and limit and stuff */
	assert (search->matchCount < ctable->count);
	search->tranTable[search->matchCount++] = row;

	// If buffering for any reason (eg, sorting), defer until later
	if(search->bufferResults)
	    return TCL_CONTINUE;
    }

    // We're not sorting or buffering, let's figure out what to do as we
    // match. If we haven't met the start point, blow it off.
    if (search->matchCount <= search->offset) {
	return TCL_CONTINUE;
    }

    if (search->endAction == CTABLE_SEARCH_ACTION_COUNT_ONLY) {
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

enum skipStart_e {
    SKIP_START_NONE, SKIP_START_GE_ROW1, SKIP_START_GT_ROW1, SKIP_START_EQ_ROW1, SKIP_START_RESET
};
enum skipEnd_e {
    SKIP_END_NONE, SKIP_END_NE_ROW1, SKIP_END_GE_ROW1, SKIP_END_GT_ROW1, SKIP_END_GE_ROW2
};
enum skipNext_e {
    SKIP_NEXT_NONE, SKIP_NEXT_ROW, SKIP_NEXT_IN_LIST
};

// skiplist scanning rules table.
//   scan starts at skipStart, goes to skipEnd, and uses skipNext to traverse.
//   score is based on an estimate of how much a scan on this field is likely
//   to limit the search.
// rationale:
//   <, <=, or >= are 2 points for being constrained at one end
//   > is only 1 point because we need to loop over "=" at start
//   range is 4 points for being constrained at both ends
//   = is 6 points for being a "minimum range"
//   in is 100 points (and win) because it HAS to be done over a list
// plus one point for being the sort field, because that saves creating and
//   sorting the transaction table.
//
static struct {
    enum skipStart_e	skipStart;
    enum skipEnd_e	skipEnd;
    enum skipNext_e	skipNext;
    int			score;
} skipTypes[] = {
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // FALSE
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // TRUE
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // NULL
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // NOTNULL
  {SKIP_START_RESET,	SKIP_END_GE_ROW1, SKIP_NEXT_ROW,   2 }, // LT
  {SKIP_START_RESET,	SKIP_END_GT_ROW1, SKIP_NEXT_ROW,   2 }, // LE
  {SKIP_START_EQ_ROW1,	SKIP_END_GT_ROW1, SKIP_NEXT_ROW,   6 }, // EQ
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // NE
  {SKIP_START_GE_ROW1,	SKIP_END_NONE,	  SKIP_NEXT_ROW,   2 }, // GE
  {SKIP_START_GT_ROW1,	SKIP_END_NONE,	  SKIP_NEXT_NONE,  1 }, // GT
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // MATCH
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // NOTMATCH
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // MATCH_CASE
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // NOTMATCH_CASE
  {SKIP_START_GE_ROW1,	SKIP_END_GE_ROW2, SKIP_NEXT_ROW,   4 }, // RANGE
  {SKIP_START_RESET,	SKIP_END_NONE, SKIP_NEXT_IN_LIST, 100}  // IN
};

#define SORT_SCORE 1 // being able to sort is worth 1 point
     // TODO: see if this should be higher
     //       if you change this, change the "not implemented"
     //       value in the table above to -1 - SORT_SCORE

enum walkType_e { WALK_DEFAULT, WALK_SKIP, WALK_HASH_EQ, WALK_HASH_IN };

static enum walkType_e hashTypes[] = {
  WALK_DEFAULT, WALK_DEFAULT, WALK_DEFAULT, WALK_DEFAULT, // FALSE..NOTNULL
  WALK_DEFAULT, WALK_DEFAULT, WALK_HASH_EQ, WALK_DEFAULT, // LT..NE
  WALK_DEFAULT, WALK_DEFAULT, WALK_DEFAULT, WALK_DEFAULT, // GT..NOTMATCH
  WALK_DEFAULT, WALK_DEFAULT, WALK_DEFAULT, WALK_HASH_IN  // MATCH_CASE..IN
};

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
    int           	  compareResult;
    int            	  actionResult = TCL_OK;

    ctable_CreatorTable	 *creator = ctable->creator;

    ctable_BaseRow	  *row = NULL;
    ctable_BaseRow	  *row1 = NULL;
    ctable_BaseRow	  *walkRow;
    void                  *row2 = NULL;
    char	  	  *key = NULL;

    int			   bestScore = 0;

    jsw_skip_t   	  *skipList = NULL;
    int           	   skipField = 0;
    int			   inOrderWalk = 0;

    fieldCompareFunction_t compareFunction = NULL;
    int                    indexNumber = -1;
    int                    comparisonType = 0;

    int			   sortField = -1;

    enum walkType_e	   walkType	= WALK_DEFAULT;

    enum skipStart_e	   skipStart = 0;
    enum skipEnd_e	   skipEnd = 0;
    enum skipNext_e	   skipNext = 0;

    int			   count;

    int			   inIndex = 0;
    Tcl_Obj		 **inListObj = NULL;
    int			   inCount = 0;

    search->matchCount = 0;
    search->alreadySearched = -1;
    search->tranTable = NULL;
    search->offsetLimit = search->offset + search->limit;

    if (search->writingTabsepIncludeFieldNames) {
	ctable_WriteFieldNames (interp, ctable, search);
    }

    if (ctable->count == 0) {
        return TCL_OK;
    }

    // Check to see if we're sorting on a single field
    if (search->sortControl.nFields == 1) {
	sortField = search->sortControl.fields[0];
    }

    // If there's no components in the search, make sure the index is NONE
    if(!search->nComponents) {
	search->reqIndexField = CTABLE_SEARCH_INDEX_NONE;
    }

    // If they're not asking for an indexed search, but the first
    // component is "in", request an indexed search.
    if (search->reqIndexField == CTABLE_SEARCH_INDEX_NONE && search->nComponents > 0) {
	if(search->components[0].comparisonType == CTABLE_COMP_IN) {
	    search->reqIndexField = search->components[0].fieldID;
	}
    }

    // if they're asking for an index search, look for the best search
    // in the list of comparisons
    //
    // See the skipTypes table for the scores, but basically the tighter
    // the constraint, the better.
    //
    // If we can use a hash table, we use it, because it's either JUST
    // a simple hash lookup, or it's "in" which has to be handled here.

    if (search->reqIndexField != CTABLE_SEARCH_INDEX_NONE && search->nComponents > 0) {
	int index = 0;
	int try;

	if(search->reqIndexField != CTABLE_SEARCH_INDEX_ANY) {
	    while(index < search->nComponents) {
	        if(search->components[index].fieldID == search->reqIndexField)
		    break;
		index++;
	    }
	}

	// Look for the best usable search field starting with the requested
	// one
	for(try = 0; try < search->nComponents; try++, index++) {
	    if(index >= search->nComponents)
	        index = 0;
	    CTableSearchComponent *component = &search->components[index];
	    int field = component->fieldID;
	    int score;

	    comparisonType = component->comparisonType;

	    // If it's the key, then see if it's something we can walk
	    // using a hash.
	    if(field == creator->keyField) {
		walkType = hashTypes[comparisonType];

		if (walkType != WALK_DEFAULT) {

		    if(walkType == WALK_HASH_IN) {
			inOrderWalk = 0; // TODO: check if list in order
		        inListObj = component->inListObj;
		        inCount = component->inCount;
		    } else { //    WALK_HASH_EQ
			inOrderWalk = 1; // degenerate case, only one result.
			row1 = component->row1;
			key = row1->hashEntry.key;
		    }

		    search->alreadySearched = index;

		    // Always use a hash if it's available, because it's
		    // either '=' (with only one result) or 'in' (which
		    // has to be walked here).
		    break;
		}
	    }

	    score = skipTypes[comparisonType].score;

	    // Prefer to avoid sort
	    if(field == sortField) score += SORT_SCORE;

	    // We already found a better option than this one, skip it
	    if (bestScore > score)
		continue;

	    // Got a new best candidate, save the world.
	    skipField = field;

	    skipNext  = skipTypes[comparisonType].skipNext;
	    skipStart = skipTypes[comparisonType].skipStart;
	    skipEnd   = skipTypes[comparisonType].skipEnd;

	    search->alreadySearched = index;
	    skipList = ctable->skipLists[field];
	    walkType = WALK_SKIP;

            compareFunction = creator->fields[field]->compareFunction;
            indexNumber = creator->fields[field]->indexNumber;

	    switch(skipNext) {
		case SKIP_NEXT_ROW: {
		    inOrderWalk = 1;
		    row1 = component->row1;
		    row2 = component->row2;
		    break;
		}
		case SKIP_NEXT_IN_LIST: {
		    inOrderWalk = 0; // TODO: check if list in order
		    inListObj = component->inListObj;
		    inCount = component->inCount;
		    row1 = component->row1;
		    break;
		}
		default: { // Can't happen
		    panic("skipNext has unexpected value %d", skipNext);
		}
	    }

	    // Score of 100 means it's mandatory
	    if (bestScore >= 100)
	        break;
        }
    }

    // if we're sorting on the field we're searching, AND we can eliminate
    // the sort because we know we're walking in order, then eliminate the
    // sort step
    if (inOrderWalk) {
        if (search->sortControl.nFields == 1) {
	    if(sortField == skipField) {
		search->sortControl.nFields = 0;
	    }
	}
    }

    // buffer results if:
    //   We're not countOnly, and...
    //     We're searching, or...
    //     We explicitly requested bufering.
    if(search->endAction == CTABLE_SEARCH_ACTION_COUNT_ONLY) {
	search->bufferResults = 0;
    } else if(search->sortControl.nFields > 0) {
	search->bufferResults = 1;
    } else if(search->bufferResults == -1) {
    	search->bufferResults = 0;
    }

    // if we're buffering (for any reason) or running a transaction,
    // allocate a space for the search results that we'll then sort from
    if (
      search->bufferResults ||
      search->tranType != CTABLE_SEARCH_TRAN_NONE
    ) {
	search->tranTable = (ctable_BaseRow **)ckalloc (sizeof (void *) * ctable->count);
    }

    if (walkType == WALK_DEFAULT) {
	// walk the hash table 
	CTABLE_LIST_FOREACH (ctable->ll_head, row, 0) {
	    compareResult = ctable_SearchCompareRow (interp, ctable, search, row);
	    if ((compareResult == TCL_CONTINUE) || (compareResult == TCL_OK)) continue;

	    if (compareResult == TCL_BREAK) break;

	    if (compareResult == TCL_ERROR) {
		actionResult = TCL_ERROR;
		goto clean_and_return;
	    }
        }
    } else if(walkType == WALK_HASH_EQ || walkType == WALK_HASH_IN) {
	// if it's '=': inIndex == inCount == 0 BUT key != NULL
	while (inIndex < inCount || key) {
	    // If we don't have a key, get one.
	    if (!key)
		key = Tcl_GetString(inListObj[inIndex++]);

	    // Look it up
	    row2 = creator->find_row(ctable, key);

	    // Throw away this key
	    key = NULL;

	    // If we didn't find the prize, try again
	    if(!row2)
		continue;

	    row1 = (ctable_BaseRow *)row2;

	    compareResult = ctable_SearchCompareRow (interp, ctable, search, row1);
	    if ((compareResult == TCL_CONTINUE) || (compareResult == TCL_OK)) continue;

	    if (compareResult == TCL_BREAK) break;

	    if (compareResult == TCL_ERROR) {
		actionResult = TCL_ERROR;
		goto clean_and_return;
	    }
        }
    } else {

        //
        // walk the skip list
        //
        // all walks are "tailored", meaning the first search term is of an
        // indexed row and it's of a type where we can cut off the search
        // past a point, see if we're past the cutoff point and if we are
        // terminate the search.
        //

	// Find the row to start walking on
	switch(skipStart) {

	    case SKIP_START_EQ_ROW1: {
		jsw_sfind (skipList, row1);
		break;
	    }

	    case SKIP_START_GE_ROW1: {
		jsw_sfind_equal_or_greater (skipList, row1);
		break;
	    }

	    case SKIP_START_GT_ROW1: {
		jsw_sfind_equal_or_greater (skipList, row1);
		while (1) {
                    if ((row = jsw_srow (skipList)) == NULL)
		        goto search_complete;
	    	    if (compareFunction (row, row1) > 0)
			break;
		    jsw_snext(skipList);
		}
		break;
	    }

	    case SKIP_START_RESET: {
		jsw_sreset(skipList);
		break;
	    }

	    default: { // can't happen
		panic("skipStart has unexpected value %d", skipStart);
	    }
	}

	// Count is only to make sure we blow up on infinite loops
	for(count = 0; count < ctable->count; count++) {
	    if(skipNext == SKIP_NEXT_IN_LIST) {
		// We're looking at a list of entries rather than a range,
		// so we have to loop here searching for each in turn instead
		// of just following the skiplist
		while(1) {
		  // If we're at the end, game over.
		  if(inIndex >= inCount)
		      goto search_complete;

		  // make a row matching the next value in the list
                  if ((*ctable->creator->set) (interp, ctable, inListObj[inIndex++], row1, skipField, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
                      Tcl_AppendResult (interp, " while processing \"in\" compare function", (char *) NULL);
                      actionResult = TCL_ERROR;
                      goto clean_and_return;
                  }

		  // If there's a match for this row, break out of the loop
                  if (jsw_sfind (skipList, row1) != NULL)
		      break;
	        }
	    }

	    // Now we can fetch whatever we found.
            if ((row = jsw_srow (skipList)) == NULL)
		goto search_complete;

	    // if at end or past any terminating condition, break
	    switch(skipEnd) {
	        case SKIP_END_GE_ROW1: {
		    if (compareFunction (row, row1) >= 0)
			goto search_complete;
		    break;
		}
	        case SKIP_END_GT_ROW1: {
		    if (compareFunction (row, row1) > 0)
			goto search_complete;
		    break;
		}
	        case SKIP_END_GE_ROW2: {
		    if (compareFunction (row, row2) >= 0)
			goto search_complete;
		    break;
		}
		default: {
		    // may not be a terminating condition, or it may
		    // have been taken care of above
	        }
	    }

            // walk walkRow through the linked list of rows off this skip list
	    // node. if you ever change this to make deletion possible while
	    // searching, switch this to use the safe foreach routine instead

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

	    if(skipNext == SKIP_NEXT_ROW)
		jsw_snext(skipList);
	}
	// Should never just fall out of the loop...
	Tcl_AppendResult (interp, "infinite search loop", (char *) NULL);
	actionResult = TCL_ERROR;
	goto clean_and_return;
    }

  search_complete:
    actionResult = ctable_PostSearchCommonActions (interp, ctable, search);
  clean_and_return:
    if (search->tranTable != NULL) {
	ckfree ((void *)search->tranTable);
    }

    if (actionResult == TCL_OK && (search->endAction == CTABLE_SEARCH_ACTION_COUNT_ONLY)) {
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
ctable_SetupSearch (Tcl_Interp *interp, CTable *ctable, Tcl_Obj *CONST objv[], int objc, CTableSearch *search, int indexField) {
    int             i;
    int             searchTerm = 0;
    CONST char                 **fieldNames = ctable->creator->fieldNames;

    static CONST char *searchOptions[] = {"-array", "-array_with_nulls", "-array_get", "-array_get_with_nulls", "-code", "-compare", "-countOnly", "-fields", "-get", "-glob", "-key", "-with_field_names", "-limit", "-noKeys", "-offset", "-regexp", "-sort", "-write_tabsep", "-delete", "-update", "-buffer", "-index", (char *)NULL};

    enum searchOptions {SEARCH_OPT_ARRAY, SEARCH_OPT_ARRAY_WITH_NULLS, SEARCH_OPT_ARRAYGET_NAMEOBJ, SEARCH_OPT_ARRAYGETWITHNULLS_NAMEOBJ, SEARCH_OPT_CODE, SEARCH_OPT_COMPARE, SEARCH_OPT_COUNTONLY, SEARCH_OPT_FIELDS, SEARCH_OPT_GET_NAMEOBJ, SEARCH_OPT_GLOB, SEARCH_OPT_KEYVAR_NAMEOBJ, SEARCH_OPT_WITH_FIELD_NAMES, SEARCH_OPT_LIMIT, SEARCH_OPT_DONT_INCLUDE_KEY, SEARCH_OPT_OFFSET, SEARCH_OPT_REGEXP, SEARCH_OPT_SORT, SEARCH_OPT_WRITE_TABSEP, SEARCH_OPT_DELETE, SEARCH_OPT_UPDATE, SEARCH_OPT_BUFFER, SEARCH_OPT_INDEX};

    if (objc < 2) {
      wrong_args:
	Tcl_WrongNumArgs (interp, 2, objv, "?-array_get varName? ?-array_get_with_nulls varName? ?-code codeBody? ?-compare list? ?-countOnly 0|1? ?-fields fieldList? ?-get varName? ?-glob pattern? ?-key varName? ?-with_field_names 0|1?  ?-limit limit? ?-noKeys 0|1? ?-offset offset? ?-regexp pattern? ?-sort {?-?field1..}? ?-write_tabsep channel? ?-delete 0|1? ?-update {fields value...}? ?-buffer 0|1?");
	return TCL_ERROR;
    }

    // initialize search control structure
    search->ctable = ctable;
    search->endAction = CTABLE_SEARCH_ACTION_NONE;
    search->nComponents = 0;
    search->components = NULL;
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
    search->codeBody = NULL;
    search->writingTabsepIncludeFieldNames = 0;
    search->tranType = CTABLE_SEARCH_TRAN_NONE;
    search->reqIndexField = indexField;
    search->bufferResults = -1; // -1 is "if sorting only"

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

	  case SEARCH_OPT_INDEX: {
	    if (Tcl_GetIndexFromObj (interp, objv[i++], fieldNames, "field", TCL_EXACT, &search->reqIndexField) != TCL_OK) {
		Tcl_AppendResult (interp, " while processing search index", (char *) NULL);
		return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_WITH_FIELD_NAMES: {
	    if (Tcl_GetBooleanFromObj (interp, objv[i++], &search->writingTabsepIncludeFieldNames) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search -with_field_names", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_ARRAY: {
	    if (search->endAction != CTABLE_SEARCH_ACTION_NONE) {
	      endActionOverload: 
	        Tcl_AppendResult (interp, "one and only one of -array, -array_with_nulls, -array_get, -array_get_with_nulls, -write_tabsep and -countOnly must be specified", (char *) NULL);
	        return TCL_ERROR;
	    }
	    search->varNameObj = objv[i++];
	    search->endAction = CTABLE_SEARCH_ACTION_ARRAY;
	    break;
	  }

	  case SEARCH_OPT_ARRAY_WITH_NULLS: {
	    if (search->endAction != CTABLE_SEARCH_ACTION_NONE) goto endActionOverload;
	    search->varNameObj = objv[i++];
	    search->endAction = CTABLE_SEARCH_ACTION_ARRAY_WITH_NULLS;
	    break;
	  }

	  case SEARCH_OPT_ARRAYGET_NAMEOBJ: {
	    if (search->endAction != CTABLE_SEARCH_ACTION_NONE) goto endActionOverload;
	    search->varNameObj = objv[i++];
	    search->endAction = CTABLE_SEARCH_ACTION_ARRAY_GET;
	    break;
	  }

	  case SEARCH_OPT_ARRAYGETWITHNULLS_NAMEOBJ: {
	    if (search->endAction != CTABLE_SEARCH_ACTION_NONE) goto endActionOverload;
	    search->varNameObj = objv[i++];
	    search->endAction = CTABLE_SEARCH_ACTION_ARRAY_GET_WITH_NULLS;
	    break;
	  }

	  case SEARCH_OPT_KEYVAR_NAMEOBJ: {
	    search->keyVarNameObj = objv[i++];
	    break;
          }

	  case SEARCH_OPT_GET_NAMEOBJ: {
	    if (search->endAction != CTABLE_SEARCH_ACTION_NONE) goto endActionOverload;
	    search->varNameObj = objv[i++];
	    search->endAction = CTABLE_SEARCH_ACTION_GET;
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
	    int countOnly;

	    if (Tcl_GetBooleanFromObj (interp, objv[i++], &countOnly) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search countOnly", (char *) NULL);
	        return TCL_ERROR;
	    }

	    if (countOnly) {
		if (search->endAction != CTABLE_SEARCH_ACTION_NONE) goto endActionOverload;
		search->endAction = CTABLE_SEARCH_ACTION_COUNT_ONLY;
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

	  case SEARCH_OPT_DELETE: {
	    int do_delete;
	    if (Tcl_GetIntFromObj (interp, objv[i++], &do_delete) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing delete option", (char *) NULL);
	        return TCL_ERROR;
	    }

	    if(do_delete) {
	      if(search->tranType != CTABLE_SEARCH_TRAN_NONE &&
	         search->tranType != CTABLE_SEARCH_TRAN_DELETE
	      ) {
		Tcl_AppendResult (interp, "Can not combine -delete with other transaction options", (char *)NULL);
		return TCL_ERROR;
	      }
	      search->tranType = CTABLE_SEARCH_TRAN_DELETE;
	    } else {
	      if(search->tranType == CTABLE_SEARCH_TRAN_DELETE)
		search->tranType = CTABLE_SEARCH_TRAN_NONE;
	    }
	    break;
	  }

	  case SEARCH_OPT_UPDATE: {
	    if(search->tranType != CTABLE_SEARCH_TRAN_NONE &&
	       search->tranType != CTABLE_SEARCH_TRAN_UPDATE
	    ) {
		Tcl_AppendResult (interp, "Can not combine -update with other transaction options", (char *)NULL);
		return TCL_ERROR;
	    }
	    search->tranType = CTABLE_SEARCH_TRAN_UPDATE;
	    search->tranData = objv[i++];
	    break;
	  }

	  case SEARCH_OPT_BUFFER: {
	    int do_buffer;
	    if (Tcl_GetIntFromObj (interp, objv[i++], &do_buffer) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing buffer option", (char *) NULL);
	        return TCL_ERROR;
	    }

	    search->bufferResults = do_buffer;
	    break;
	  }

	  case SEARCH_OPT_WRITE_TABSEP: {
	    int        mode;
	    char      *channelName;

	    if (search->endAction != CTABLE_SEARCH_ACTION_NONE) goto endActionOverload;

	    channelName = Tcl_GetString (objv[i++]);
	    if ((search->tabsepChannel = Tcl_GetChannel (interp, channelName, &mode)) == NULL) {
	        Tcl_AppendResult (interp, " while processing write_tabsep channel", (char *) NULL);
	        return TCL_ERROR;
	    }

	    if (!(mode & TCL_WRITABLE)) {
		Tcl_AppendResult (interp, "channel \"", channelName, "\" not writable", (char *)NULL);
		return TCL_ERROR;
	    }

	    search->endAction = CTABLE_SEARCH_ACTION_WRITE_TABSEP;
	  }
	}
    }

    if (search->endAction == CTABLE_SEARCH_ACTION_NONE &&
	search->tranType != CTABLE_SEARCH_TRAN_NONE) {
	search->endAction = CTABLE_SEARCH_ACTION_TRANSACTION_ONLY;
    }

    if (search->endAction == CTABLE_SEARCH_ACTION_NONE &&
	search->keyVarNameObj == NULL) {
	goto endActionOverload;
    }

    if (search->endAction == CTABLE_SEARCH_ACTION_WRITE_TABSEP) {
        if (search->codeBody != NULL || search->keyVarNameObj != NULL || search->varNameObj != NULL) {
	    Tcl_AppendResult (interp, "can't use -code or -key along with -write_tabsep", (char *) NULL);
	    return TCL_ERROR;
	}
    } else if (search->writingTabsepIncludeFieldNames) {
	Tcl_AppendResult (interp, "can't use -with_field_names without -write_tabsep", (char *) NULL);
	return TCL_ERROR;
    }

    if ((search->endAction == CTABLE_SEARCH_ACTION_COUNT_ONLY) && search->sortControl.nFields) {
	Tcl_AppendResult (interp, "it's nuts to -sort something that's a -countOnly anyway", (char *) NULL);
	return TCL_ERROR;
    }

    if ((search->endAction != CTABLE_SEARCH_ACTION_WRITE_TABSEP) && (search->endAction != CTABLE_SEARCH_ACTION_COUNT_ONLY) && (search->endAction != CTABLE_SEARCH_ACTION_TRANSACTION_ONLY)) {
        if (!search->codeBody) {
	    Tcl_AppendResult (interp, "one of -code, -write-tabsep, -delete, or -update must be specified", (char *)NULL);
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
	        search->ctable->creator->delete (search->ctable, component->row1, CTABLE_INDEX_PRIVATE);
	    }

	    if (component->row2 != NULL) {
	        search->ctable->creator->delete (search->ctable, component->row2, CTABLE_INDEX_PRIVATE);
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
// ctable_SetupAndPerformSearch - setup and perform a (possibly) skiplist search
//   on a table.
//
// Uses a skip list index as the outer loop.  Still brute force unless the
// foremost compare routine is tailorable, however even so, much faster
// than a hash table walk.
//
//
int
ctable_SetupAndPerformSearch (Tcl_Interp *interp, Tcl_Obj *CONST objv[], int objc, CTable *ctable, int indexField) {
    CTableSearch    search;

    if (ctable_SetupSearch (interp, ctable, objv, objc, &search, indexField) == TCL_ERROR) {
        return TCL_ERROR;
    }

    if (ctable_PerformSearch (interp, ctable, &search) == TCL_ERROR) {
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

    for (field = 0; field < ctable->creator->nFields; field++) {
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
        s = ctable->creator->get_string (row, field, NULL, utilityObj);
	jsw_dump (s, skip, ctable->creator->fields[field]->indexNumber);
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

        if (ctable->creator->lappend_field (interp, resultObj, p, fieldNum) == TCL_ERROR) {
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

    if (ctable_ListRemoveMightBeTheLastOne (row, ctable->creator->fields[field]->indexNumber)) {
// printf("i might be the last one, field %d\n", field);
	index = ctable->creator->fields[field]->indexNumber;
        // it might be the last one, see if it really was
// printf ("row->ll_nodes[index].head %lx\n", (long unsigned int)row->_ll_nodes[index].head);
	if (*row->_ll_nodes[index].head == NULL) {
// printf("erasing last entry field %d\n", field);
            // put the pointer back so the compare routine will have
	    // something to match
            *row->_ll_nodes[index].head = row;
	    if (!jsw_serase (skip, row)) {
		panic ("corrupted index detected for field %s", ctable->creator->fields[field]->name);
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
    for (field = 0; field < ctable->creator->nFields; field++) {
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
    ctable_FieldInfo *f;
    Tcl_Obj *utilityObj;

    if (skip == NULL) {
    return TCL_OK;
    }

    f = ctable->creator->fields[field];

# if 0
// dump info about row being inserted
utilityObj = Tcl_NewObj();
printf("ctable_InsertIntoIndex field %d, field name %s, index %d, value %s\n", field, f->name, f->indexNumber, ctable->creator->get_string (row, field, NULL, utilityObj));
Tcl_DecrRefCount (utilityObj);
#endif

    if (!jsw_sinsert_linked (skip, row, f->indexNumber, f->unique)) {

	utilityObj = Tcl_NewObj();
	Tcl_AppendResult (interp, "unique check failed for field \"", f->name, "\", value \"", ctable->creator->get_string (row, field, NULL, utilityObj), "\"", (char *) NULL);
	Tcl_DecrRefCount (utilityObj);
        return TCL_ERROR;
    }
    return TCL_OK;
}

inline int
ctable_RemoveNullFromIndex (Tcl_Interp *interp, CTable *ctable, void *row, int field) {
    return TCL_OK; /* PDS 20070215 NULL kludge FIXME? */
#if 0 /* PDS 20070215 NULL kludge FIXME? */
    jsw_skip_t *skip = ctable->skipLists[field];

    if (skip == NULL) {
        return TCL_OK;
    }

    Tcl_AppendResult (interp, "remove null from index unimplemented", (char *) NULL);
    return TCL_ERROR;
#endif /* PDS 20070215 NULL kludge FIXME? */
}

inline int
ctable_InsertNullIntoIndex (Tcl_Interp *interp, CTable *ctable, void *row, int field) {
    return TCL_OK; /* PDS 20070215 NULL kludge FIXME? */
#if 0 /* PDS 20070215 NULL kludge FIXME? */
    jsw_skip_t *skip = ctable->skipLists[field];

    if (skip == NULL) {
        return TCL_OK;
    }

    Tcl_AppendResult (interp, "insert null into index unimplemented", (char *) NULL);
    return TCL_OK;
#endif /* PDS 20070215 NULL kludge FIXME? */
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

    if (ctable->creator->fields[field]->indexNumber < 0) {
	Tcl_AppendResult (interp, "can't create an index on a field that hasn't been defined as allowing an index", (char *)NULL);
	return TCL_ERROR;
    }

    skip = jsw_snew (depth, ctable->creator->fields[field]->compareFunction);

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

    if (ctable->creator->lappend_field (interp, resultObj, row, ctable->creator->fieldList[field]) == TCL_ERROR) {
        return TCL_ERROR;
    }

    jsw_findlast (skip);
    row = jsw_srow (skip);

    if (ctable->creator->lappend_field (interp, resultObj, row, ctable->creator->fieldList[field]) == TCL_ERROR) {
        return TCL_ERROR;
    }

    return TCL_OK;
}

