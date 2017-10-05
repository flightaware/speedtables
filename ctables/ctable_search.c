/*
 * Ctable search routines
 *
 * $Id$
 *
 */

#include "ctable.h"

#include "ctable_qsort.c"

#include "boyer_moore.c"

#include "jsw_rand.c"

#include "ctable_lists.c"

#include "ctable_batch.c"

#include "jsw_slib.c"

#include "speedtableHash.c"

#include <time.h>

// forward references
CTABLE_INTERNAL struct cursor *
ctable_CreateEmptyCursor(Tcl_Interp *interp, CTable *ctable, char *name);
CTABLE_INTERNAL struct cursor *
ctable_CreateCursor(Tcl_Interp *interp, CTable *ctable, CTableSearch *search);
CTABLE_INTERNAL int
ctable_CreateCursorCommand(Tcl_Interp *interp, struct cursor *cursor);
CTABLE_INTERNAL Tcl_Obj *
ctable_CursorToName(struct cursor *cursor);

//#define INDEXDEBUG
// #define MEGADEBUG
// #define SEARCHDEBUG
#ifndef TRACKFIELD
#define TRACKFIELD 1
#endif
// debugging routines - verify that every skiplist contains an entry for
// every row.
CTABLE_INTERNAL void
ctable_verifyField(CTable *ctable, int field, int verbose)
{
    ctable_BaseRow *row = NULL;
    ctable_BaseRow *found = NULL;
    ctable_BaseRow *walk = NULL;
    jsw_skip_t     *skip = ctable->skipLists[field];
    int             index = ctable->creator->fields[field]->indexNumber;

    if(verbose) fprintf(stderr, "Verifying field %s\n", ctable->creator->fields[field]->name);
    CTABLE_LIST_FOREACH (ctable->ll_head, row, 0) {
	if (verbose) fprintf(stderr, "  Searching 0x%lx for 0x%lx\n", (long)skip, (long)row);
	// make sure the entry can be found.
	jsw_sreset(skip);
	jsw_sfind (skip, row);
	found = jsw_srow(skip);
	if(found != row) {
	    int count = 0;
	    if(!verbose) {
		fprintf(stderr, "Verifying field %s\n", ctable->creator->fields[field]->name);
		fprintf(stderr, "  Searching skip 0x%lx for row 0x%lx\n", (long)skip, (long)row);
	    }
	    fprintf(stderr, "    Walking from 0x%lx\n", (long)found);
            // walk walkRow through the linked list of rows off this skip list
            CTABLE_LIST_FOREACH (found, walk, index) {
		fprintf(stderr, "      ... 0x%lx\n", (long)walk);
		count++;
	        if(row == walk)
		    break;
	    }
	    if(row != walk)
	        panic("row 0x%lx not found in table", (long)row);
	    fprintf(stderr, "    Found after %d links\n", count);
	}
    }
    if(verbose) fprintf(stderr, "Field %s OK\n", ctable->creator->fields[field]->name);
}

CTABLE_INTERNAL void
ctable_verify (Tcl_Interp *interp, CTable *ctable, int verbose) {
    int field;

    if(verbose) fprintf(stderr, "Verify start.\n");
    for(field = 0; field < ctable->creator->nFields; field++) {
	if(ctable->creator->fields[field]->canBeNull == 0) {
	    if(ctable->skipLists[field]) {
	        ctable_verifyField(ctable, field, verbose);
	    } else if(verbose) {
		fprintf(stderr, "No index for field %s\n", ctable->creator->fields[field]->name);
	    }
	} else if(verbose) {
	    fprintf(stderr, "Skipping nullable field %s\n", ctable->creator->fields[field]->name);
	}
    }
    if(verbose) fprintf(stderr, "Verify end.\n");
}


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
CTABLE_INTERNAL int
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
	    ckfree ((char *)fieldList);
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
// array to -1 else set it to 1.
//
// It is up to the caller to free the memory pointed to through the
// fieldList argument.
//
// return TCL_OK if all went according to plan, else TCL_ERROR.
//
//
CTABLE_INTERNAL int
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
	int fieldNameNeedsFreeing = 0;

        fieldName = Tcl_GetString (fieldsObjv[i]);
	if (fieldName[0] == '-') {
	    sort->directions[i] = -1;
	    fieldName++;
	    fieldNameObj = Tcl_NewStringObj (fieldName, -1);
	    fieldNameNeedsFreeing = 1;
	} else {
	    fieldNameObj = fieldsObjv[i];
	    sort->directions[i] = 1;
	    fieldNameNeedsFreeing = 0;
	}

	if (Tcl_GetIndexFromObj (interp, fieldNameObj, fieldNames, "field", TCL_EXACT, &sort->fields[i]) != TCL_OK) {
	    if (fieldNameNeedsFreeing) {
		Tcl_DecrRefCount (fieldNameObj);
	    }
	    ckfree ((char *)sort->fields);
	    ckfree ((char *)sort->directions);
	    sort->fields = NULL;
	    sort->directions = NULL;
	    return TCL_ERROR;
	}

	if (fieldNameNeedsFreeing) {
	    Tcl_DecrRefCount (fieldNameObj);
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
CTABLE_INTERNAL int
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

CTABLE_INTERNAL int ctable_CreateInRows(Tcl_Interp *interp, CTable *ctable, CTableSearchComponent *component)
{
    int i;

    if(component->inListRows || component->inCount == 0)
	return TCL_OK;

    component->inListRows = (ctable_BaseRow **)ckalloc(component->inCount * sizeof (ctable_BaseRow *));

    // Since the main loop may abort, make sure this is clean
    for(i = 0; i < component->inCount; i++) {
	component->inListRows[i] = NULL;
    }

    for(i = 0; i < component->inCount; i++) {
	component->inListRows[i] = (*ctable->creator->make_empty_row) (ctable);

	if ((*ctable->creator->set) (interp, ctable, component->inListObj[i], component->inListRows[i], component->fieldID, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
	    Tcl_AddErrorInfo (interp, "\n    while processing \"in\" compare function");
	    return TCL_ERROR;
	}
    }
    return TCL_OK;
}

CTABLE_INTERNAL void ctable_FreeInRows(CTable *ctable, CTableSearchComponent *component)
{
    if(component->inListRows) {
	int i;
	for(i = 0; i < component->inCount; i++) {
	    if(component->inListRows[i]) {
	        ctable->creator->delete_row (ctable, component->inListRows[i], CTABLE_INDEX_PRIVATE);
	    }
	}
	ckfree((char*)component->inListRows);
	component->inListRows = NULL;
    }
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

    static CONST char *searchTerms[] = CTABLE_SEARCH_TERMS;

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
	    search->components = NULL;
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
	component->row3 = NULL;
	component->inListObj = NULL;
	component->inListRows = NULL;
	component->inCount = 0;
	component->compareFunction = ctable->creator->fields[field]->compareFunction;

	if (term == CTABLE_COMP_FALSE || term == CTABLE_COMP_TRUE || term == CTABLE_COMP_NULL || term == CTABLE_COMP_NOTNULL) {
	    if (termListCount != 2) {
		Tcl_AppendResult (interp, "false, true, null and notnull search expressions must have only two fields", (char *) NULL);
		goto err;
	    }
	} else {

	    if (term == CTABLE_COMP_IN) {
	        if (termListCount != 3) {
		    Tcl_AppendResult (interp, "term \"", Tcl_GetString (termList[0]), "\" require 3 arguments (term, field, list)", (char *) NULL);
		    goto err;
		}

		if (Tcl_ListObjGetElements (interp, termList[2], &component->inCount, &component->inListObj) == TCL_ERROR) {
		    goto err;
		}

		# TODO find minimum and maximum of the list and put them in row1 and row2 and continue
	    } else if (term == CTABLE_COMP_RANGE) {
	        ctable_BaseRow *row;

	        if (termListCount != 4) {
		    Tcl_AppendResult (interp, "term \"", Tcl_GetString (termList[0]), "\" require 4 arguments (term, field, lowValue, highValue)", (char *) NULL);
		    goto err;
		}

		row = (*ctable->creator->make_empty_row) (ctable);
		if ((*ctable->creator->set) (interp, ctable, termList[2], row, field, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
		    goto err;
		}
		component->row1 = row;

		row = (*ctable->creator->make_empty_row) (ctable);
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
		// Check if field that supports string matches
		int ftype = ctable->creator->fieldTypes[field];
		if(ftype != CTABLE_TYPE_FIXEDSTRING && ftype != CTABLE_TYPE_VARSTRING && ftype != CTABLE_TYPE_KEY) {
		    Tcl_AppendResult (interp, "term \"", Tcl_GetString (termList[1]), "\" must be a string type for \"", Tcl_GetString (termList[0]), "\" operation", (char *) NULL);
		    goto err;
		}

		struct ctableSearchMatchStruct *sm = (struct ctableSearchMatchStruct *)ckalloc (sizeof (struct ctableSearchMatchStruct));

		sm->type = ctable_searchMatchPatternCheck (Tcl_GetString (termList[2]));
		sm->nocase = ((term == CTABLE_COMP_MATCH) || (term == CTABLE_COMP_NOTMATCH));

		if (sm->type == CTABLE_STRING_MATCH_UNANCHORED) {
		    char *needle;
		    int len;

		    needle = Tcl_GetStringFromObj (termList[2], &len);
		    boyer_moore_setup (sm, (unsigned char *)needle + 1, len - 2, sm->nocase);
		} else if(sm->type == CTABLE_STRING_MATCH_ANCHORED && term == CTABLE_COMP_MATCH_CASE) {
		    int len;
		    char *needle = Tcl_GetStringFromObj (termList[2], &len);
		    char *prefix = (char *) ckalloc(len+1);
		    int i;

		    /* stash the prefix of the match into row2 */
		    for(i = 0; i < len; i++) {
			if(needle[i] == '*') {
			    break;
			}
			prefix[i] = needle[i];
			break;
		    }

		    // This test should never fail.
		    if(i > 0) {
		        ctable_BaseRow *row;
		        prefix[i] = '\0';

		        row = (*ctable->creator->make_empty_row) (ctable);
	    		if ((*ctable->creator->set) (interp, ctable, Tcl_NewStringObj (prefix, -1), row, field, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
			    goto err;
	    	        }
	    		component->row2 = row;

			// Now set up row3 as the first non-matching string
			prefix[i-1]++;

		        row = (*ctable->creator->make_empty_row) (ctable);
	    		if ((*ctable->creator->set) (interp, ctable, Tcl_NewStringObj (prefix, -1), row, field, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
			    goto err;
	    	        }
	    		component->row3 = row;

		    }
		    ckfree(prefix);
		}

		component->clientData = sm;
	    }

	    /* stash what we want to compare to into a row as in "range"
	     */
	    if (term != CTABLE_COMP_IN) {
		ctable_BaseRow *row;
		row = (*ctable->creator->make_empty_row) (ctable);
		if ((*ctable->creator->set) (interp, ctable, termList[2], row, field, CTABLE_INDEX_PRIVATE) == TCL_ERROR) {
			goto err;
		}
		component->row1 = row;
	    }
	}
    }

    // it worked, leave the components allocated
    return TCL_OK;
}

static int
ctable_ParseFilters (Tcl_Interp *interp, CTable *ctable, Tcl_Obj *filterListObj, CTableSearch *search) {
    Tcl_Obj               **filterList;
    int                     filterListCount;

    CTableSearchFilter     *filters = NULL;

    int i;

    // Assume nothing, trust no one.
    search->filters = NULL;
    search->nFilters = 0;

    if (Tcl_ListObjGetElements (interp, filterListObj, &filterListCount, &filterList) == TCL_ERROR)
        goto abend;

    // Nothing to do
    if (filterListCount == 0) {
        return TCL_OK;
    }


    // List is {{filtername filtervalue} {filtername filtervalue}} .. if passing a list to a filter, pass a list

    // make room, make room
    filters = (CTableSearchFilter *)ckalloc (filterListCount * sizeof (CTableSearchFilter));

    // step through list, looking for filter names and filling in the structs
    for (i = 0; i < filterListCount; i++) {
        Tcl_Obj    **termList;
        int          termListCount;
        int item;

        if (Tcl_ListObjGetElements (interp, filterList[i], &termListCount, &termList) == TCL_ERROR || termListCount != 2) {
          Tcl_AppendResult (interp, "each term of the filter must be a nested list with 2 items", (char *) NULL);
          goto abend;
        }


        if (Tcl_GetIndexFromObj (interp, termList[0], ctable->creator->filterNames, "filter", TCL_EXACT, &item) != TCL_OK)
            goto abend;

        filters[i].filterFunction = ctable->creator->filterFunctions[item];
        filters[i].filterObject = termList[1];
    }

    // Register the filter list we've created
    search->filters = filters;
    search->nFilters = filterListCount;
    return TCL_OK;

abend:
    if(filters)
        ckfree ((char *)filters);
    return TCL_ERROR;
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

    if (search->action == CTABLE_SEARCH_ACTION_WRITE_TABSEP) {
	Tcl_DString     dString;

	Tcl_DStringInit (&dString);

	// string-append the specified fields, or all fields, tab separated

	if (search->nRetrieveFields < 0) {
	    (*creator->dstring_append_get_tabsep) (key, row, creator->publicFieldList, creator->nPublicFields, &dString, search->noKeys, search->sepstr, search->quoteType, search->nullString);
	} else {
	    (*creator->dstring_append_get_tabsep) (key, row, search->retrieveFields, search->nRetrieveFields, &dString, search->noKeys, search->sepstr, search->quoteType, search->nullString);
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

	switch (search->action) {

	  case CTABLE_SEARCH_ACTION_GET: {
	    if (search->nRetrieveFields < 0) {
		listObj = creator->gen_list (interp, row);
	    } else {
	       int i;

	       listObj = Tcl_NewObj ();
	       for (i = 0; i < search->nRetrieveFields; i++) {
		   creator->lappend_field (interp, listObj, row, search->retrieveFields[i]);
	       }
	    }
	    break;
	  }

	  case CTABLE_SEARCH_ACTION_ARRAY_WITH_NULLS:
	  case CTABLE_SEARCH_ACTION_ARRAY: {
	    int result = TCL_OK;

	    // Clear array before filling it in. Ignore failure because it's
	    // OK for the array not to exist at this point.
	    Tcl_UnsetVar2(interp, Tcl_GetString(search->rowVarNameObj), NULL, 0);

	    if (search->nRetrieveFields < 0) {
	       int i;

	       for (i = 0; i < creator->nFields; i++) {
		   if (is_hidden_field(creator,i) && !is_key_field(creator,i,search->noKeys)) {
		       continue;
		   }
	           if (search->action == CTABLE_SEARCH_ACTION_ARRAY) {
		       result = creator->array_set (interp, search->rowVarNameObj, row, i);
		   } else {
		       result = creator->array_set_with_nulls (interp, search->rowVarNameObj, row, i);
		   }
	       }
	    } else {
	       int i;

	       for (i = 0; i < search->nRetrieveFields; i++) {
	           if (search->action == CTABLE_SEARCH_ACTION_ARRAY) {
		       result = creator->array_set (interp, search->rowVarNameObj, row, search->retrieveFields[i]);
		   } else {
		       result = creator->array_set_with_nulls (interp, search->rowVarNameObj, row, search->retrieveFields[i]);
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
		    if (is_hidden_field(creator,i) && !is_key_field(creator,i,search->noKeys)) {
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
		    if (is_hidden_field(creator,i) && !is_key_field(creator,i,search->noKeys)) {
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
	if ((listObj != NULL) && (Tcl_ObjSetVar2 (interp, search->rowVarNameObj, (Tcl_Obj *)NULL, listObj, TCL_LEAVE_ERR_MSG) == (Tcl_Obj *) NULL)) {
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
	    Tcl_AddErrorInfo (interp, "\n   while processing search code body");
	    return TCL_ERROR;

	  case TCL_OK:
	  case TCL_CONTINUE:
	  case TCL_BREAK:
	    Tcl_ResetResult(interp);
	  case TCL_RETURN:
	    return evalResult;
	}
    }

    return TCL_OK;
}

//
// ctable_checkForKey - check for a "key" field, and if there set the internal
// noKeys flag to suppress the separate output of the "_key" field.
//
CTABLE_INTERNAL void ctable_checkForKey(CTable *ctable, CTableSearch *search)
{
    if (!search->noKeys) {
	int		     i;
        int                 *fields;
        int                  nFields;
        ctable_CreatorTable *creator = ctable->creator;

        if (search->nRetrieveFields < 0) {
	    fields = creator->publicFieldList;
	    nFields = creator->nPublicFields;
        } else {
	    nFields = search->nRetrieveFields;
	    fields = search->retrieveFields;
        }

        for (i = 0; i < nFields; i++) {
	    if(fields[i] == creator->keyField) {
		search->noKeys = 1;
		break;
	    }
	}
    }
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

    // Generate key field if necessary
    if (!search->noKeys)
        Tcl_DStringAppend (&dString, "_key", 4);

    for (i = 0; i < nFields; i++) {
	if (!search->noKeys || i != 0) {
	    Tcl_DStringAppend(&dString, search->sepstr, -1);
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

    if(search->tranType == CTABLE_SEARCH_TRAN_NONE || search->tranType == CTABLE_SEARCH_TRAN_CURSOR) {
	return TCL_OK;
    }

    if(search->tranType == CTABLE_SEARCH_TRAN_DELETE) {

      // walk the result and delete the matched rows
      for (rowIndex = search->offset; rowIndex < search->offsetLimit; rowIndex++) {
	  (*creator->delete_row) (ctable, search->tranTable[rowIndex], CTABLE_INDEX_NORMAL);
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
	        ckfree((char*)updateFields);
		goto updateParseError;
	    }
	}

	// Perform update
        for (rowIndex = search->offset; rowIndex < search->offsetLimit; rowIndex++) {
	    ctable_BaseRow *row = search->tranTable[rowIndex];

	    for(fieldIndex = 0; fieldIndex < objc/2; fieldIndex++) {
		if((*creator->set)(interp, ctable, objv[fieldIndex*2+1], row, updateFields[fieldIndex], CTABLE_INDEX_NORMAL) == TCL_ERROR) {
		    ckfree((char*)updateFields);
		    Tcl_AppendResult (interp, " (update may be incomplete)", (char *)NULL);
		    return TCL_ERROR;
		}
	    }
	}

	ckfree((char*)updateFields);

        return TCL_OK;
    }

    Tcl_AppendResult(interp, "internal error - unknown transaction type %d", search->tranType);

    return TCL_ERROR;
}

//
// ctable_search_poll - called periodically from a search to avoid blocking
// the Tcl event loop.
//
CTABLE_INTERNAL int ctable_search_poll(Tcl_Interp *interp, CTable *ctable, CTableSearch *search)
{
    if(search->pollCodeBody) {
	int result = Tcl_EvalObjEx (interp, search->pollCodeBody, 0);
	if(result == TCL_ERROR) {
	    Tcl_BackgroundError(interp);
	    Tcl_ResetResult(interp);
	}
    } else {
	Tcl_DoOneEvent(0);
    }
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
// If transaction processing is required, we call ctable_PerformTransactions
//
//
static int
ctable_PostSearchCommonActions (Tcl_Interp *interp, CTable *ctable, CTableSearch *search)
{
    int walkIndex;
    ctable_CreatorTable *creator = ctable->creator;
    int actionResult = TCL_OK;

    // if there was nothing matched, or we're before the offset, we're done
    if(search->matchCount == 0 || search->offset > search->matchCount) {
	// And we didn't match anything
	search->matchCount = 0;
	return TCL_OK;
    }

    // if we're not sorting or performing a transaction, we're done -- we
    // did 'em all on the fly
    if (search->tranTable == NULL) {
	// But account for the offset in the matchCount
	search->matchCount -= search->offset;
        return TCL_OK;
    }

    // figure out the last row they could want, if it's more than what's
    // there, set it down to what came back
    if ((search->offsetLimit == 0) || (search->offsetLimit > search->matchCount)) {
        search->offsetLimit = search->matchCount;
    }

    if(search->sortControl.nFields) {	// sorting
      ctable_qsort_r (search->tranTable, search->matchCount, sizeof (ctable_HashEntry *), &search->sortControl, (cmp_t*) creator->sort_compare);
    }

    if (search->tranType == CTABLE_SEARCH_TRAN_CURSOR) {
	search->cursor = ctable_CreateCursor(interp, ctable, search);
    } else if(search->bufferResults == CTABLE_BUFFER_DEFER) { // we deferred the operation to here
        // walk the result
        for (walkIndex = search->offset; walkIndex < search->offsetLimit; walkIndex++) {
	    if(search->pollInterval && --search->nextPoll <= 0) {
		if(ctable_search_poll(interp, ctable, search) == TCL_ERROR)
		    return TCL_ERROR;
		search->nextPoll = search->pollInterval;
	    }
	    /* here is where we want to take the match actions
	     * when we are sorting or otherwise buffering
	     */
	    actionResult = ctable_SearchAction (interp, ctable, search, search->tranTable[walkIndex]);
	    switch (actionResult) {
	        case TCL_CONTINUE:
	        case TCL_OK: {
	            actionResult = TCL_OK;
	            break;
	        }
	        case TCL_BREAK:
	        case TCL_RETURN: {
		    // We DO count this row as a match, to be consistent with
		    // the non-deferred case.
		    search->offsetLimit = walkIndex + 1;
	            goto normal_return;
	        }
	        case TCL_ERROR: {
	            return TCL_ERROR;
	        }
	    }
        }
    }

normal_return:
    // Calculate the final match count
    search->matchCount = search->offsetLimit - search->offset;

    // Finally, perform any pending transaction.
    if(search->tranType != CTABLE_SEARCH_TRAN_NONE && search->tranType !=  CTABLE_SEARCH_TRAN_CURSOR) {
	if (ctable_PerformTransaction(interp, ctable, search) == TCL_ERROR) {
	    return TCL_ERROR;
	}
    }

    return actionResult;
}

//
// ctable_SearchCompareRow - perform comparisons on a row
//
INLINE static int
ctable_SearchCompareRow (Tcl_Interp *interp, CTable *ctable, CTableSearch *search, ctable_BaseRow *row)
{
    int   compareResult;
    int   actionResult;

    // Handle polling
    if(search->pollInterval && --search->nextPoll <= 0) {
	if(ctable_search_poll(interp, ctable, search) == TCL_ERROR)
	    return TCL_ERROR;
	search->nextPoll = search->pollInterval;
    }

    // if we have a match pattern (for the key) and it doesn't match,
    // skip this row

    if (search->pattern != (char *) NULL) {
	if (!Tcl_StringCaseMatch (row->hashEntry.key, search->pattern, 1)) {
	    return TCL_CONTINUE;
	}
    }

    // check filters
    if (search->nFilters) {
	int i;
	int filterResult = TCL_OK;

	for(i = 0; i < search->nFilters; i++) {
	    filterFunction_t f = search->filters[i].filterFunction;
	    filterResult = (*f) (interp, ctable, row, search->filters[i].filterObject, search->sequence);
	    if(filterResult != TCL_OK)
		return filterResult;
	}
    }

    //
    // run the supplied compare routine
    //
    compareResult = (*ctable->creator->search_compare) (interp, search, row);
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
	/* We are buffering the results (eg, for a sort or a transaction)
	 * so just return, we'll do the heavy lifting later. */
	assert (search->matchCount <= ctable->count);
	search->tranTable[search->matchCount++] = row;

	// If buffering for an important reason (eg, sorting), defer
	if(search->bufferResults == CTABLE_BUFFER_DEFER)
	    return TCL_CONTINUE;
    }

    // We're not deferring the results, let's figure out what to do as we
    // match. If we haven't met the start point, blow it off.
    if (search->matchCount <= search->offset) {
	return TCL_CONTINUE;
    }

    if (search->action == CTABLE_SEARCH_ACTION_NONE) {
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

    /* we want to take the match actions here -- we're here when we aren't
     * buffering (at least not for an "important" reason)
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
	return actionResult;
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
    SKIP_NEXT_NONE, SKIP_NEXT_ROW, SKIP_NEXT_MATCH, SKIP_NEXT_IN_LIST
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
  {SKIP_START_GT_ROW1,	SKIP_END_NONE,	  SKIP_NEXT_ROW,   1 }, // GT
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // MATCH
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // NOTMATCH
  {SKIP_START_GE_ROW1,	SKIP_END_GE_ROW2, SKIP_NEXT_MATCH, 3 }, // MATCH_CASE
  {SKIP_START_NONE,	SKIP_END_NONE,	  SKIP_NEXT_NONE, -2 }, // NOTMATCH_CASE
  {SKIP_START_GE_ROW1,	SKIP_END_GE_ROW2, SKIP_NEXT_ROW,   4 }, // RANGE
# TODO change to SKIP_START_GE_ROW1, SKIP_END_GT_ROW1 after we have them populated
  {SKIP_START_RESET,	SKIP_END_NONE, SKIP_NEXT_IN_LIST,  2 }  // IN
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

#ifdef WITH_SHARED_TABLES
struct restart_t {
    ctable_BaseRow	  *row1;
    ctable_BaseRow	  *row2;
    enum skipStart_e	   skipStart;
    enum skipEnd_e	   skipEnd;
    fieldCompareFunction_t compareFunction;
};

CTABLE_INTERNAL int ctable_SearchRestartNeeded(ctable_BaseRow *row, struct restart_t *restart)
{
    // check to see if we're still following the right skiplist, by seeing
    // if the value we're following still satisfies the criteria
    switch(restart->skipEnd) {
	case SKIP_END_GE_ROW1: {
	    if (restart->compareFunction (row, restart->row1) >= 0)
		return 1;
	    break;
	}
	case SKIP_END_GT_ROW1: {
	    if (restart->compareFunction (row, restart->row1) > 0)
		return 1;
	    break;
	}
	case SKIP_END_GE_ROW2: {
	    if (restart->compareFunction (row, restart->row2) >= 0)
		return 1;
	    break;
	}
	default: {
	    break;
	}
    }
    switch(restart->skipStart) {
        case SKIP_START_GE_ROW1: {
	    if (restart->compareFunction (row, restart->row1) < 0)
		return 1;
	    break;
	}
	case SKIP_START_GT_ROW1: {
	    if (restart->compareFunction (row, restart->row1) <= 0)
		return 1;
	    break;
	}
	case SKIP_START_EQ_ROW1: {
	    if (restart->compareFunction (row, restart->row1) != 0)
		return 1;
	    break;
	}
        case SKIP_START_NONE:
	case SKIP_START_RESET: {
	    break;
	}
    }
    // Got through here... no restart needed
    return 0;
}
#endif

//
// ctable_PrepareTransactions - set up buffering for transactions if needed
//
CTABLE_INTERNAL void ctable_PrepareTransactions(CTable *ctable, CTableSearch *search)
{
    // buffer results if:
    //   We've got search actions, AND...
    //     We're searching, or...
    //     We're a reader table, or...
    //     We explicitly requested bufering.
    if (search->action == CTABLE_SEARCH_ACTION_NONE) {
	search->bufferResults = CTABLE_BUFFER_NONE;
    } else if(search->action == CTABLE_SEARCH_ACTION_CURSOR) {
	search->bufferResults = CTABLE_BUFFER_DEFER;
    } else if(search->sortControl.nFields > 0) {
	search->bufferResults = CTABLE_BUFFER_DEFER;
#ifdef WITH_SHARED_TABLES
    } else if(ctable->share_type == CTABLE_SHARED_READER) {
	search->bufferResults = CTABLE_BUFFER_DEFER;
#endif
    } else if(search->bufferResults < 0) {
    	search->bufferResults = CTABLE_BUFFER_NONE;
    }

    // If we're not buffering for any other reason, buffer for a transaction
    // but set bufferResults to PROVISIONAL so we can still terminate the
    // search early
    if(search->bufferResults == CTABLE_BUFFER_NONE && search->tranType != CTABLE_SEARCH_TRAN_NONE) {
	search->bufferResults = CTABLE_BUFFER_PROVISIONAL;
    }

    // if we're buffering,
    // allocate a space for the search results that we'll then sort from
    if (search->bufferResults != CTABLE_BUFFER_NONE) {
	search->tranTable = (ctable_BaseRow **)ckalloc (sizeof (ctable_BaseRow *) * ctable->count);
    }
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
CTABLE_INTERNAL int
ctable_PerformSearch (Tcl_Interp *interp, CTable *ctable, CTableSearch *search) {
    int           	  compareResult;
    int			  finalResult = TCL_OK;

    ctable_CreatorTable	 *creator = ctable->creator;

    ctable_BaseRow	  *row = NULL;
    ctable_BaseRow	  *row1 = NULL;
    ctable_BaseRow	  *walkRow;
    ctable_BaseRow        *row2 = NULL;
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

    enum skipStart_e	   skipStart = SKIP_START_NONE;
    enum skipEnd_e	   skipEnd = SKIP_END_NONE;
    enum skipNext_e	   skipNext = SKIP_NEXT_NONE;

    int			   myCount;

    int			   inIndex = 0;
    Tcl_Obj		 **inListObj = NULL;
    ctable_BaseRow	 **inListRows = NULL;
    int			   inCount = 0;

    int			   canUseHash = 1;

    CTableSearch         *s;

#ifdef WITH_SHARED_TABLES
    int			   firstTime = 1;
    int			   locked_cycle = LOST_HORIZON;
    int			   num_restarts = 0;

    jsw_skip_t   	  *skipListCopy = NULL;
#endif

    if (search->writingTabsepIncludeFieldNames) {
	ctable_WriteFieldNames (interp, ctable, search);
    }

#ifdef WITH_SHARED_TABLES
    if (firstTime) {
	firstTime = 0;
    } else {
restart_search:
	num_restarts++;

	// Check for indefinite deferral
	if(MAX_RESTARTS > 0 && num_restarts > MAX_RESTARTS) {
	    Tcl_AppendResult (interp, "restart count exceeded", (char *) NULL);
	    finalResult = TCL_ERROR;
	    goto clean_and_return;
	}

	// re-initialise and de-allocate and clean up, we're going through the
	// while exercise again...

        if (search->tranTable != NULL) {
	    ckfree ((char *)search->tranTable);
	    search->tranTable = NULL;
        }

        if(skipListCopy) {
	    jsw_free_private_copy(skipListCopy);
	    skipListCopy = NULL;
	}


        if (ctable->share_type == CTABLE_SHARED_READER) {
	    read_unlock(ctable->share);
	    locked_cycle = LOST_HORIZON;
	}

	row = NULL;
	row1 = NULL;
	row2 = NULL;
	key = NULL;
	bestScore = 0;

	skipList = NULL;
        skipField = 0;
        inOrderWalk = 0;

        compareFunction = NULL;
        indexNumber = -1;
        comparisonType = 0;

        sortField = -1;

        walkType = WALK_DEFAULT;

        skipStart = SKIP_START_NONE;
        skipEnd = SKIP_END_NONE;
        skipNext = SKIP_NEXT_NONE;
    
        inIndex = 0;
        inListObj = NULL;
        inCount = 0;
    }

    if (ctable->share_type == CTABLE_SHARED_READER) {
	// make sure the dummy ctable is up to date.
	locked_cycle = read_lock(ctable->share);

        ctable->count = ctable->share_ctable->count;
	ctable->skipLists = ctable->share_ctable->skipLists;
	ctable->ll_head = ctable->share_ctable->ll_head;
    }
#endif

    search->matchCount = 0;
    search->alreadySearched = -1;
    if (search->tranTable != NULL) {
	ckfree ((char *)search->tranTable);
	search->tranTable = NULL;
    }
    search->offsetLimit = search->offset + search->limit;

    if (ctable->count == 0) {
#ifdef WITH_SHARED_TABLES
        if(locked_cycle != LOST_HORIZON)
	    read_unlock(ctable->share);
#endif
	if (search->cursor) {
	    ctable_CreateCursorCommand(interp, search->cursor);
	    Tcl_SetObjResult (interp, ctable_CursorToName (search->cursor));
	} else if (search->cursorName) {
	    struct cursor *cursor = ctable_CreateEmptyCursor(interp, ctable, search->cursorName);
	    search->cursorName = NULL;
	    ctable_CreateCursorCommand(interp, cursor);
	    Tcl_SetObjResult (interp, ctable_CursorToName (cursor));
	} else {
	    Tcl_SetObjResult (interp, Tcl_NewIntObj (0));
	}
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

    // Check if we can use the hash table.
#ifdef WITH_SHARED_TABLES
    // fprintf(stderr, "ctable->share_type=%d\n", ctable->share_type);
    if(ctable->share_type == CTABLE_SHARED_READER) {
	// fprintf(stderr, "READER TABLE\n");
	canUseHash = 0;
    }
#endif

    // if they're asking for an index search, look for the best search
    // in the list of comparisons
    //
    // See the skipTypes table for the scores, but basically the tighter
    // the constraint, the better.
    //
    // If we can use a hash table, we use it, because it's either JUST
    // a simple hash lookup, or it's "in" which has to be handled here.
    //
    // If we're doing a client search, we don't have access to the
    // hashtable, so we can't do a hash search.
    if (search->reqIndexField != CTABLE_SEARCH_INDEX_NONE && search->nComponents > 0) {
	int index = 0;
	int trynum;

	if(search->reqIndexField != CTABLE_SEARCH_INDEX_ANY) {
	    while(index < search->nComponents) {
	        if(search->components[index].fieldID == search->reqIndexField)
		    break;
		index++;
	    }
	}

	// Look for the best usable search field starting with the requested
	// one
	for(trynum = 0; trynum < search->nComponents; trynum++, index++) {
	    if(index >= search->nComponents)
	        index = 0;
	    CTableSearchComponent *component = &search->components[index];
	    int field = component->fieldID;
	    int score;

	    comparisonType = component->comparisonType;

	    // If it's the key, then see if it's something we can walk
	    // using a hash.
	    if(field == creator->keyField && canUseHash) {
		walkType_e tryWalkType = hashTypes[comparisonType];

		if (tryWalkType != WALK_DEFAULT) {
		    walkType = tryWalkType;

		    if(walkType == WALK_HASH_IN) {
			inOrderWalk = 0; // TODO: check if list in order
		        inListObj = component->inListObj;
		        inCount = component->inCount;
		    } else { //    WALK_HASH_EQ
			inOrderWalk = 1; // degenerate case, only one result.
			row1 = (ctable_BaseRow*) component->row1;
			key = row1->hashEntry.key;
		    }

		    search->alreadySearched = index;

		    // Always use a hash if it's available, because it's
		    // either '=' (with only one result) or 'in' (with at
		    // most inCount results).
		    break;
		}
	    }

	    // Do we have an index on this puppy?
	    if(!ctable->skipLists[field]) {
		continue;
	    }

	    // Special case - if it's a match and not anchored, skip
	    if(skipTypes[comparisonType].skipNext == SKIP_NEXT_MATCH) {
		if(component->row2 == NULL) {
		    continue;
		}
	    }

	    // If we have previous searches, walk back through the previous searches to see if we're already using
	    // this field
	    for(s = search->previousSearch; s; s = s->previousSearch) {
		if(s->searchField == field) {
		    break;
		}
	    }
	    if(s) {
		continue;
	    }

	    score = skipTypes[comparisonType].score;

	    // Prefer to avoid sort
	    if(field == sortField) score += SORT_SCORE;

	    // We already found a better option than this one, skip it
	    if (bestScore > score)
		continue;

	    // Got a new best candidate, save the world.
	    skipField = field;
	    search->searchField = field;

	    skipNext  = skipTypes[comparisonType].skipNext;
	    skipStart = skipTypes[comparisonType].skipStart;
	    skipEnd   = skipTypes[comparisonType].skipEnd;

	    search->alreadySearched = index;
	    skipList = ctable->skipLists[field];
	    walkType = WALK_SKIP;

            compareFunction = creator->fields[field]->compareFunction;
            indexNumber = creator->fields[field]->indexNumber;

	    switch(skipNext) {
	        case SKIP_NEXT_MATCH: {
		    // For a match, we use row2 and row3 as row1 and row2,
		    // otherwise treat it as a range
		    inOrderWalk = 1;
		    row1 = (ctable_BaseRow*)component->row2;
		    row2 = component->row3;
		    skipNext = SKIP_NEXT_ROW;
		    break;
	        }
		case SKIP_NEXT_ROW: {
		    inOrderWalk = 1;
		    row1 = (ctable_BaseRow*) component->row1;
		    row2 = component->row2;
		    break;
		}
		case SKIP_NEXT_IN_LIST: {
		    inOrderWalk = 0; // TODO: check if list in order
		    inListObj = component->inListObj;
		    inCount = component->inCount;
		    if (ctable_CreateInRows(interp, ctable, component) == TCL_ERROR) {
			finalResult = TCL_ERROR;
			goto clean_and_return;
		    }
		    inListRows = component->inListRows;
		    row1 = (ctable_BaseRow*) component->row1;
		    break;
		}
		default: { // Can't happen
		    panic("skipNext has unexpected value %d (comparisonType == %d, skipStart == %d, skipEnd == %d, score == %d)", skipNext, comparisonType, skipStart, skipEnd, score);
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

    // Prepare transaction buffering if necessary
    ctable_PrepareTransactions(ctable, search);

    // Prepare for background operations
    if(search->pollInterval) search->nextPoll = search->pollInterval;

#ifdef INDEXDEBUG
fprintf(stderr, "Starting search.\n");
fprintf(stderr, "  walkType == %d\n", walkType);
fprintf(stderr, "  sortField == %d\n", sortField);
fprintf(stderr, "  skipField == %d\n", skipField);
fprintf(stderr, "  skipList == 0x%0ld\n", (long)skipList);
if(skipList) {
fprintf(stderr, "    skipNext == %d\n", skipNext);
fprintf(stderr, "    skipStart == %d\n", skipStart);
fprintf(stderr, "    skipEnd == %d\n", skipEnd);
}
fprintf(stderr, "  search->sortControl.nFields == %d\n", search->sortControl.nFields);
int ii;
fprintf(stderr, "  search->nComponents == %d\n", search->nComponents);
for(ii = 0; ii < search->nComponents; ii++) {
CTableSearchComponent *component = &search->components[ii];
fprintf(stderr, "    search->components[%d].fieldID == %d\n", ii, component->fieldID);
fprintf(stderr, "    search->components[%d].comparisonType == %d\n", ii, component->comparisonType);
}
#endif

    if (walkType == WALK_DEFAULT) {
#ifdef INDEXDEBUG
fprintf(stderr, "WALK_DEFAULT\n");
#endif
	// walk the hash table links.
	CTABLE_LIST_FOREACH (ctable->ll_head, row, 0) {
	    compareResult = ctable_SearchCompareRow (interp, ctable, search, row);
	    if ((compareResult == TCL_CONTINUE) || (compareResult == TCL_OK))
		continue;

	    if (compareResult == TCL_BREAK)
		break;

	    if (compareResult == TCL_RETURN) {
		finalResult = TCL_RETURN;
		break;
	    }

	    if (compareResult == TCL_ERROR) {
		finalResult = TCL_ERROR;
		goto clean_and_return;
	    }
        }
    } else if(walkType == WALK_HASH_EQ || walkType == WALK_HASH_IN) {
#ifdef INDEXDEBUG
fprintf(stderr, "WALK_HASH_*\n");
#endif
	// Just look up the necessary hash table values

	// This loop is a little complex because for "=" the key is
	// already set, otherwise it needs to be loaded from the index
	// list. This would actually be simpler with a goto. :)
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
	    if ((compareResult == TCL_CONTINUE) || (compareResult == TCL_OK))
		continue;

	    if (compareResult == TCL_BREAK)
		break;

	    if (compareResult == TCL_RETURN) {
		finalResult = TCL_RETURN;
		break;
	    }
	    if (compareResult == TCL_ERROR) {
		finalResult = TCL_ERROR;
		goto clean_and_return;
	    }
        }
    } else {
#ifdef INDEXDEBUG
fprintf(stderr, "WALK_SKIP\n");
#endif

        //
        // walk the skip list
        //
        // all walks are "tailored", meaning the first search term is of an
        // indexed row and it's of a type where we can cut off the search
        // past a point, see if we're past the cutoff point and if we are
        // terminate the search.
        //
#ifdef WITH_SHARED_TABLES
	struct restart_t main_restart;
	struct restart_t loop_restart;
	cell_t main_cycle = LOST_HORIZON;
	cell_t loop_cycle = LOST_HORIZON;

#ifdef SANITY_CHECKS
	creator->sanity_check_pointer(ctable, (void *)skipList, CTABLE_INDEX_NORMAL, "ctablePerformSearch : skipList");
#endif

	if(ctable->share_type == CTABLE_SHARED_READER) {
	    // Save the cycle at the time we started the search
	    main_cycle = ctable->share->map->cycle;
#ifdef SANITY_CHECKS
	    if(main_cycle == LOST_HORIZON)
		panic("Master is not updating the garbage collect cycle!");
#endif
	    // save the main restart condition
	    main_restart.row1 = row1;
	    main_restart.row2 = (ctable_BaseRow*)row2;
	    main_restart.skipStart = skipStart;
	    main_restart.skipEnd = skipEnd;
	    main_restart.compareFunction = compareFunction;

	    // clone the skiplist
	    skipListCopy = jsw_private_copy(skipList, getpid(), compareFunction);
	    if(skipListCopy)
		skipList = skipListCopy;
	}
#endif

	// Find the row to start walking on
	switch(skipStart) {

	    case SKIP_START_EQ_ROW1: {
if(!row1) panic("Can't happen! Row1 is null for '=' comparison.");
		jsw_sfind (skipList, row1);
		break;
	    }

	    case SKIP_START_GE_ROW1: {
if(!row1) panic("Can't happen! Row1 is null for '>=' comparison.");
		jsw_sfind_equal_or_greater (skipList, row1);
		break;
	    }

	    case SKIP_START_GT_ROW1: {
if(!row1) panic("Can't happen! Row1 is null for '>' comparison.");
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

#ifdef MEGADEBUG
#ifdef WITH_SHARED_TABLES
if(ctable->share_type == CTABLE_SHARED_READER)
    fprintf(stderr, "Following skiplist 0x%lX\n", (long)skipList);
#endif
#endif

	// Count is only to make sure we blow up on infinite loops
	// It's compared less than OR equal to the largest possible value
	// it could have.
	for(myCount = 0; myCount <= ctable->count; myCount++) {
	    if(skipNext == SKIP_NEXT_IN_LIST) {
		// We're looking at a list of entries rather than a range,
		// so we have to loop here searching for each in turn instead
		// of just following the skiplist
		while(1) {
		  // If we're at the end, game over.
		  if(inIndex >= inCount)
		      goto search_complete;

#ifdef WITH_SHARED_TABLES
		  if(main_cycle != LOST_HORIZON) {
	            // Save the cycle at the time we started the walk
	            main_cycle = ctable->share->map->cycle;
		  }
#endif

		  row = inListRows[inIndex++];
if(!row) panic("Can't happen, null row in 'in' comparison");

		  // If there's a match for this row, break out of the loop
                  if (jsw_sfind (skipList, row) != NULL)
		      break;
	        }
	    }

	    // Now we can fetch whatever we found.
            if ((row = jsw_srow (skipList)) == NULL)
		goto search_complete;
#ifdef SANITY_CHECKS
	creator->sanity_check_pointer(ctable, (void *)row, CTABLE_INDEX_NORMAL, "ctablePerformSearch : row");
#endif

#ifdef WITH_SHARED_TABLES
	    // If we're a reader and this row has changed since we started
	    // then check if it changed the skiplist we're following, if so...
	    // go back and restart the search
	    if(main_cycle != LOST_HORIZON) {
	        // Save the cycle at the time we started the loop
	        loop_cycle = ctable->share->map->cycle;
		if(row->_row_cycle != LOST_HORIZON) {
		    int delta = row->_row_cycle - main_cycle;
		    if(delta > 0) {
		        if(ctable_SearchRestartNeeded(row, &main_restart)) {
#ifdef MEGADEBUG
if(num_restarts == 0) fprintf(stderr, "%d: main restart: main_cycle=%ld; row->_row_cycle=%ld; delta %d\n", getpid(), (long)main_cycle, (long)row->_row_cycle, delta);
#endif
			    goto restart_search;
			}
		    }
#ifdef SANITY_CHECKS
		} else {
		    panic("Master is not copying the garbage collect cycle to the row!");
#endif
		}

	        // save the loop restart condition - exact match for this field
	        loop_restart.row1 = row;
	        loop_restart.row2 = row;
	        loop_restart.skipStart = SKIP_START_EQ_ROW1;
	        loop_restart.skipEnd = SKIP_END_NE_ROW1;
	        loop_restart.compareFunction = compareFunction;
	    }
#endif

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
	    // node. This is not the safe foreach routine because we don't
	    // change the skiplist during the search, and if someone else
	    // does it we need to restart the transaction anyway.

            CTABLE_LIST_FOREACH (row, walkRow, indexNumber) {

#ifdef WITH_SHARED_TABLES
		// If we're a reader and this row has changed since we started
		// then check if it changed the list we're following, if so...
		// go back and restart the search
	        if(loop_cycle != LOST_HORIZON) {
		    if(row->_row_cycle != LOST_HORIZON) {
		        int delta = row->_row_cycle - main_cycle;
		        if(delta > 0) {
		            if(ctable_SearchRestartNeeded(row, &loop_restart)) {
#ifdef MEGADEBUG
if(num_restarts == 0) fprintf(stderr, "%d: loop restart: loop_cycle=%ld; row->_row_cycle=%ld; delta=%d\n", getpid(), (long)loop_cycle, (long)row->_row_cycle, delta);
#endif
			        goto restart_search;
			    }
		        }
#ifdef SANITY_CHECKS
		    } else {
		        panic("Master is not copying the garbage collect cycle to the row!");
#endif
		    }
	        }
#endif

	        compareResult = ctable_SearchCompareRow (interp, ctable, search, walkRow);
	        if ((compareResult == TCL_CONTINUE) || (compareResult == TCL_OK)) continue;

	        if (compareResult == TCL_BREAK)
		    goto search_complete;

		if (compareResult == TCL_RETURN) {
		    finalResult = TCL_RETURN;
	            goto search_complete;
	        }

	        if (compareResult == TCL_ERROR) {
	            finalResult = TCL_ERROR;
	            goto clean_and_return;
	        }
	    }

	    if(skipNext == SKIP_NEXT_ROW)
		jsw_snext(skipList);
	}
	// Should never just fall out of the loop...
	Tcl_AppendResult (interp, "infinite search loop", (char *) NULL);
	finalResult = TCL_ERROR;
	goto clean_and_return;
    }

  // We only jump to this on success, so we got to the end of the loop
  // or we broke out of it early
  search_complete:

    // We're no longer walking a skiplist, so make a note of that so it can be re-used.
    search->searchField = -1;

    switch (ctable_PostSearchCommonActions (interp, ctable, search)) {
	case TCL_ERROR: {
	    finalResult = TCL_ERROR;
	    break;
	}
	case TCL_RETURN: {
	    finalResult = TCL_RETURN;
	    break;
	}
    }

  // We only jump to this on an error
  clean_and_return:
    if (search->tranTable != NULL) {
	ckfree ((char *)search->tranTable);
	search->tranTable = NULL;
    }

    if (finalResult != TCL_ERROR && (search->codeBody == NULL || finalResult != TCL_RETURN)) {
	if(search->cursor) {
	    // We got here so we can create the command
	    ctable_CreateCursorCommand(interp, search->cursor);
	    Tcl_SetObjResult (interp, ctable_CursorToName (search->cursor));
	} else if (search->cursorName) {
	    struct cursor *cursor = ctable_CreateEmptyCursor(interp, ctable, search->cursorName);
	    search->cursorName = NULL;
	    ctable_CreateCursorCommand(interp, cursor);
	    Tcl_SetObjResult (interp, ctable_CursorToName (cursor));
	} else {
	    Tcl_SetObjResult (interp, Tcl_NewIntObj (search->matchCount));
	}
    }

#ifdef WITH_SHARED_TABLES
    if(search->cursor)
	search->cursor->lockCycle = locked_cycle;
    else if(locked_cycle != LOST_HORIZON)
	read_unlock(ctable->share);

    if(skipListCopy)
	jsw_free_private_copy(skipListCopy);

#ifdef MEGADEBUG
if(num_restarts) fprintf(stderr, "%d: Restarted search %d times\n", getpid(), num_restarts);
#endif
#endif

    return finalResult;
}

//
// ctable_SetupSearch - prepare to search by parsing the command line arguments
// specified when the ctables "search" method is invoked.
//
//
static int
ctable_SetupSearch (Tcl_Interp *interp, CTable *ctable, Tcl_Obj *CONST objv[], int objc, CTableSearch *search, int indexField, CTableSearch *previous_search) {
    int             i;
    int             searchTerm = 0;
    CONST char    **fieldNames = ctable->creator->fieldNames;
    int		    quick_count;

    static int staticSequence = 0;

    static CONST char *searchOptions[] = {"-array", "-array_with_nulls", "-array_get", "-array_get_with_nulls", "-code", "-compare", "-countOnly", "-fields", "-get", "-glob", "-key", "-with_field_names", "-limit", "-nokeys", "-offset", "-sort", "-write_tabsep", "-tab", "-delete", "-update", "-buffer", "-index", "-poll_code", "-poll_interval", "-quote", "-null", "-filter", "-cursor", (char *)NULL};

    enum searchOptions {SEARCH_OPT_ARRAY_NAMEOBJ, SEARCH_OPT_ARRAYWITHNULLS_NAMEOBJ, SEARCH_OPT_ARRAYGET_NAMEOBJ, SEARCH_OPT_ARRAYGETWITHNULLS_NAMEOBJ, SEARCH_OPT_CODE, SEARCH_OPT_COMPARE, SEARCH_OPT_COUNTONLY, SEARCH_OPT_FIELDS, SEARCH_OPT_GET_NAMEOBJ, SEARCH_OPT_GLOB, SEARCH_OPT_KEYVAR_NAMEOBJ, SEARCH_OPT_WITH_FIELD_NAMES, SEARCH_OPT_LIMIT, SEARCH_OPT_DONT_INCLUDE_KEY, SEARCH_OPT_OFFSET, SEARCH_OPT_SORT, SEARCH_OPT_WRITE_TABSEP, SEARCH_OPT_TAB, SEARCH_OPT_DELETE, SEARCH_OPT_UPDATE, SEARCH_OPT_BUFFER, SEARCH_OPT_INDEX, SEARCH_OPT_POLL_CODE, SEARCH_OPT_POLL_INTERVAL, SEARCH_OPT_QUOTE_TYPE, SEARCH_OPT_NULL_STRING, SEARCH_OPT_FILTER, SEARCH_OPT_CURSOR};
    if (objc < 2) {
      wrong_args:
	Tcl_WrongNumArgs (interp, 2, objv, "?-array_get varName? ?-array_get_with_nulls varName? ?-code codeBody? ?-compare list? ?-filter list? ?-countOnly 0|1? ?-fields fieldList? ?-get varName? ?-glob pattern? ?-key varName? ?-with_field_names 0|1?  ?-limit limit? ?-nokeys 0|1? ?-offset offset? ?-sort {?-?field1..}? ?-write_tabsep channel? ?-tab value? ?-delete 0|1? ?-update {fields value...}? ?-buffer 0|1? ?-poll_interval interval? ?-poll_code codeBody? ?-quote type?");
	return TCL_ERROR;
    }

    // Quick count of table rows for early optimizations where ONLY the
    // number of rows is being used. This quick_count is a snapshot that
    // is safe to use for shared readers because reading it is an atomic
    // operation.
#ifdef WITH_SHARED_TABLES
    if (ctable->share_type == CTABLE_SHARED_READER)
	quick_count = ctable->share_ctable->count;
    else
#endif
	quick_count = ctable->count;

// TODO figure out how to handle the case where a cursor command is being used. In the meantime we can't use this shortcut
#if 0
    // if there are no rows in the table, the search won't turn up
    // anything, so skip all that
    if (quick_count == 0)
    {
	search->filters = NULL;
	search->components = NULL; // keep ctable_searchTeardown happy
	Tcl_SetObjResult (interp, Tcl_NewIntObj (0));
	return TCL_RETURN;
    }
#endif

    // initialize search control structure
    search->ctable = ctable;
    search->previousSearch = previous_search;
    search->action = CTABLE_SEARCH_ACTION_NONE;
    search->nComponents = 0;
    search->components = NULL;
    search->nFilters = 0;
    search->filters = NULL;
    search->countMax = 0;
    search->offset = 0;
    search->limit = 0;
    search->pattern = NULL;
    search->pollInterval = 0;
    search->nextPoll = -1;
    search->pollCodeBody = NULL;
    search->sortControl.fields = NULL;
    search->sortControl.directions = NULL;
    search->sortControl.nFields = 0;
    search->retrieveFields = NULL;
    search->nRetrieveFields = -1;   // -1 = all, 0 = none
    search->noKeys = 0;
    search->rowVarNameObj = NULL;
    search->keyVarNameObj = NULL;
    search->codeBody = NULL;
    search->writingTabsepIncludeFieldNames = 0;
    search->tranType = CTABLE_SEARCH_TRAN_NONE;
    search->tranData = NULL;
    search->reqIndexField = indexField;
    search->bufferResults = CTABLE_BUFFER_DEFAULT;
    search->sepstr = "\t";
    search->nullString = NULL;
    search->quoteType = CTABLE_QUOTE_NONE;
    search->matchCount = 0;
    search->alreadySearched = -1;
    search->tranTable = NULL;
    search->offsetLimit = search->offset + search->limit;
    search->cursorName = NULL;
    search->cursor = NULL;
    search->searchField = -1;

    // Give each search a unique non-zero sequence number
    if(++staticSequence == 0) ++staticSequence;
    search->sequence = staticSequence;

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
	        Tcl_AppendResult (interp, " while processing search -nokeys", (char *) NULL);
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

	  case SEARCH_OPT_ARRAY_NAMEOBJ: {
	    if (search->action != CTABLE_SEARCH_ACTION_NONE)
		goto actionOverload;
	    search->rowVarNameObj = objv[i++];
	    search->action = CTABLE_SEARCH_ACTION_ARRAY;
	    break;
	  }

	  case SEARCH_OPT_ARRAYWITHNULLS_NAMEOBJ: {
	    if (search->action != CTABLE_SEARCH_ACTION_NONE)
		goto actionOverload;
	    search->rowVarNameObj = objv[i++];
	    search->action = CTABLE_SEARCH_ACTION_ARRAY_WITH_NULLS;
	    break;
	  }

	  case SEARCH_OPT_ARRAYGET_NAMEOBJ: {
	    if (search->action != CTABLE_SEARCH_ACTION_NONE)
		goto actionOverload;
	    search->rowVarNameObj = objv[i++];
	    search->action = CTABLE_SEARCH_ACTION_ARRAY_GET;
	    break;
	  }

	  case SEARCH_OPT_ARRAYGETWITHNULLS_NAMEOBJ: {
	    if (search->action != CTABLE_SEARCH_ACTION_NONE)
		goto actionOverload;
	    search->rowVarNameObj = objv[i++];
	    search->action = CTABLE_SEARCH_ACTION_ARRAY_GET_WITH_NULLS;
	    break;
	  }

	  case SEARCH_OPT_KEYVAR_NAMEOBJ: {
	    search->keyVarNameObj = objv[i++];
	    break;
          }

	  case SEARCH_OPT_GET_NAMEOBJ: {
	    if (search->action != CTABLE_SEARCH_ACTION_NONE)
		goto actionOverload;
	    search->rowVarNameObj = objv[i++];
	    search->action = CTABLE_SEARCH_ACTION_GET;
	    break;
          }

	  case SEARCH_OPT_GLOB: {
	    search->pattern = Tcl_GetString (objv[i++]);
	    break;
	  }

	  case SEARCH_OPT_COMPARE: {
	    if (ctable_ParseSearch (interp, ctable, objv[i++], fieldNames, search) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search compare", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_FILTER: {
	    if (ctable_ParseFilters (interp, ctable, objv[i++], search) == TCL_ERROR) {
		Tcl_AppendResult (interp, " while processing search filter", (char *)NULL);
		return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_COUNTONLY: {
#if 0
	    int countOnly;

	    if (Tcl_GetBooleanFromObj (interp, objv[i++], &countOnly) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search countOnly", (char *) NULL);
	        return TCL_ERROR;
	    }

	    if (countOnly) {
		if (search->action != CTABLE_SEARCH_ACTION_NONE)
		    goto actionOverload;
		search->action = CTABLE_SEARCH_ACTION_COUNT;
	    }
#else
	    i++; // skip argument
#endif
	    break;
	  }

	  case SEARCH_OPT_OFFSET: {
	    if (Tcl_GetIntFromObj (interp, objv[i++], &search->offset) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search offset", (char *) NULL);
	        return TCL_ERROR;
	    }

	    if (search->offset < 0) {
	        Tcl_AppendResult (interp, "Search offset cannot be negative", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_LIMIT: {
	    if (Tcl_GetIntFromObj (interp, objv[i++], &search->limit) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing search limit", (char *) NULL);
	        return TCL_ERROR;
	    }

	    if (search->limit < 0) {
	        Tcl_AppendResult (interp, "Search limit cannot be negative", (char *) NULL);
	        return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_CODE: {
	      search->codeBody = objv[i++];
	      break;
	  }

	  case SEARCH_OPT_POLL_CODE: {
	      search->pollCodeBody = objv[i++];
	      if (!search->pollInterval)
		  search->pollInterval = CTABLE_DEFAULT_POLL_INTERVAL;
	      break;
	  }

	  case SEARCH_OPT_POLL_INTERVAL: {
	    int poll_interval;
	    if (Tcl_GetIntFromObj (interp, objv[i++], &poll_interval) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing poll_interval option", (char *) NULL);
	        return TCL_ERROR;
	    }

	    search->pollInterval = poll_interval;
	    break;
	  }
	
	  case SEARCH_OPT_DELETE: {
	    int do_delete;
	    if (Tcl_GetIntFromObj (interp, objv[i++], &do_delete) == TCL_ERROR) {
	        Tcl_AppendResult (interp, " while processing delete option", (char *) NULL);
	        return TCL_ERROR;
	    }

	    if(do_delete) {
	      if(ctable->cursors) {
	        Tcl_AppendResult(interp, "Can not delete while cursors are active.", NULL);
	        Tcl_SetErrorCode (interp, "speedtables", "no_delete_with_cursors", NULL);
	        return TCL_ERROR;
	      }
	      if(previous_search) {
	        Tcl_AppendResult(interp, "Can not delete in nested search.", NULL);
	        Tcl_SetErrorCode (interp, "speedtables", "no_delete_inside_search", NULL);
	        return TCL_ERROR;
	      }
#ifdef WITH_SHARED_TABLES
	      if(ctable->share_type == CTABLE_SHARED_READER) {
		Tcl_AppendResult (interp, "Can't modify read-only tables.", (char *)NULL);
		return TCL_ERROR;
	      }
#endif
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
#ifdef WITH_SHARED_TABLES
	    if(ctable->share_type == CTABLE_SHARED_READER) {
		Tcl_AppendResult (interp, "Can't modify read-only tables.", (char *)NULL);
		return TCL_ERROR;
	    }
#endif
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

	  case SEARCH_OPT_TAB: {
	    search->sepstr = Tcl_GetString(objv[i++]);
	    break;
	  }

	  case SEARCH_OPT_NULL_STRING: {
	    search->nullString = Tcl_GetString(objv[i++]);
	    break;
	  }

	  case SEARCH_OPT_QUOTE_TYPE: {
	    search->quoteType = ctable_parseQuoteType(interp, objv[i++]);
	    if(search->quoteType < 0) {
		Tcl_AppendResult (interp, "in argument to -quote", NULL);
		return TCL_ERROR;
	    }
	    break;
	  }

	  case SEARCH_OPT_WRITE_TABSEP: {
	    int        mode;
	    char      *channelName;

	    if (search->action != CTABLE_SEARCH_ACTION_NONE)
		goto actionOverload;

	    channelName = Tcl_GetString (objv[i++]);
	    if ((search->tabsepChannel = Tcl_GetChannel (interp, channelName, &mode)) == NULL) {
	        Tcl_AppendResult (interp, " while processing write_tabsep channel", (char *) NULL);
	        return TCL_ERROR;
	    }

	    if (!(mode & TCL_WRITABLE)) {
		Tcl_AppendResult (interp, "channel \"", channelName, "\" not writable", (char *)NULL);
		return TCL_ERROR;
	    }

	    search->action = CTABLE_SEARCH_ACTION_WRITE_TABSEP;

	    break;
	  }

	  case SEARCH_OPT_CURSOR: {
	    char *cursorName = NULL;
	    struct cursor *c;

            if(search->tranType != CTABLE_SEARCH_TRAN_NONE || search->action != CTABLE_SEARCH_ACTION_NONE) {
		Tcl_AppendResult (interp, "Can not combine -cursor with other operations", (char *)NULL);
	    }

	    cursorName = Tcl_GetString (objv[i++]);

	    if (strcmp (cursorName, "#auto") == 0) {
		char *tableName = NULL;
		int tableNameLength;
		static unsigned long int auto_cursor_id = 0;

		// use command name of the ctable as the base of the cursor name
		tableName = Tcl_GetStringFromObj (objv[0], &tableNameLength);
		tableNameLength += 42+2;
		cursorName = (char *) ckalloc (tableNameLength);
		snprintf(cursorName, tableNameLength, "%s_C%lu", tableName, ++auto_cursor_id);
	    } else {
		char *tmp = (char *)ckalloc (strlen(cursorName) + 1);
		strcpy(tmp, cursorName);
		cursorName = tmp;
	    }

	    for (c = ctable->cursors; c; c = c->nextCursor) {
		if(strcmp(c->cursorName, cursorName) == 0) {
		    Tcl_AppendResult (interp, "Cursor name must not duplicate an existing cursor on the same table", (char *)NULL);
		    ckfree(cursorName);
	            return TCL_ERROR;
		}
	    }

	    search->tranType = CTABLE_SEARCH_TRAN_CURSOR;
	    search->action = CTABLE_SEARCH_ACTION_CURSOR;
	    search->cursorName = cursorName;
	  }
	}
    }

    // If we have a code body, make sure we're not doing a write_tabsep or returning a cursor, make
    // sure we have a row variable or a key variable, and that we're not
    // leaving the search action "none"
    if (search->codeBody != NULL) {
	if (search->action == CTABLE_SEARCH_ACTION_WRITE_TABSEP || search->action == CTABLE_SEARCH_ACTION_CURSOR) {
	    Tcl_AppendResult (interp, "Both -code and -write_tabsep or -cursor specified", (char *)NULL);
	    goto errorReturn;
	}
	if (search->rowVarNameObj == NULL && search->keyVarNameObj == NULL) {
	    Tcl_AppendResult (interp, "Code block specified, but none of -key, -get, -array, -array_get, -array_with_nulls, or -array_get_with_nulls provided", NULL);
	    goto errorReturn;
	}
	if(search->action == CTABLE_SEARCH_ACTION_NONE)
	    search->action = CTABLE_SEARCH_ACTION_CODE;
    }

    // If we're doing a transaction, make sure we're not leaving the search
    // action "none"
    if(search->tranType != CTABLE_SEARCH_TRAN_NONE) {
	if(search->action == CTABLE_SEARCH_ACTION_NONE)
	    search->action = CTABLE_SEARCH_ACTION_TRANSACTION_ONLY;
    }

    // If there's nothing going on in the search, then skip the search and
    // return quick_count (calculated earlier).
    if(search->action == CTABLE_SEARCH_ACTION_NONE) {
	if(search->nComponents == 0 && search->nFilters == 0 && search->nRetrieveFields <= 0 && search->codeBody == NULL && search->pattern == NULL && search->rowVarNameObj == NULL && search->keyVarNameObj == NULL) {

	    if (search->offset) {
		quick_count -= search->offset;
		if (quick_count < 0) {
		    quick_count = 0;
		}
	    }

	    if (search->limit) {
		if (quick_count > search->limit) {
		    quick_count = search->limit;
		}
	    }

	    Tcl_SetObjResult (interp, Tcl_NewIntObj (quick_count));
	    return TCL_RETURN;
	}
    }

    if (search->action == CTABLE_SEARCH_ACTION_WRITE_TABSEP) {
	ctable_checkForKey(ctable, search);
    } else {
	if(search->writingTabsepIncludeFieldNames) {
	    Tcl_AppendResult (interp, "can't use -with_field_names without -write_tabsep", (char *) NULL);
	    return TCL_ERROR;
	}

        if (search->codeBody == NULL && search->sortControl.nFields) {
	    Tcl_AppendResult (interp, "Sorting must be accompanied by -code or -write_tabsep", (char *) NULL);
	    return TCL_ERROR;
        }
    }

    return TCL_OK;

  actionOverload: 

    Tcl_AppendResult (interp, "only one of -array, -array_with_nulls, -array_get, -array_get_with_nulls, or -write_tabsep must be specified", (char *) NULL);

  errorReturn:

    return TCL_ERROR;
}

//
// ctable_elapsed_time - calculate the time interval between two timespecs and store in a new
// timespec
//
void
ctable_elapsed_time (struct timespec *oldtime, struct timespec *newtime, struct timespec *elapsed) {
    elapsed->tv_sec = newtime->tv_sec - oldtime->tv_sec;
    elapsed->tv_nsec = newtime->tv_nsec - oldtime->tv_nsec;

    if (elapsed->tv_nsec < 0) {
	elapsed->tv_nsec += 1000000000;
	elapsed->tv_sec--;
    }
}

#ifdef CTABLES_CLOCK
//
// ctable_performance_callback - callback routine for performance of search calls
//
void
ctable_performance_callback (Tcl_Interp *interp, CTable *ctable, Tcl_Obj *CONST objv[], int objc, struct timespec *startTimeSpec, int loggingMatchCount) {
    struct timespec endTimeSpec;
    struct timespec elapsedTimeSpec;
    Tcl_Obj *cmdObjv[4];
    double cpu;
    int i;

    // calculate elapsed cpu

    clock_gettime (CTABLES_CLOCK, &endTimeSpec);
    ctable_elapsed_time (startTimeSpec, &endTimeSpec, &elapsedTimeSpec);
    cpu = (elapsedTimeSpec.tv_sec + (elapsedTimeSpec.tv_nsec / 1000000000.0));

    if (cpu < ctable->performanceCallbackThreshold) {
	return;
    }

    cmdObjv[0] = Tcl_NewStringObj (ctable->performanceCallback, -1);
    cmdObjv[1] = Tcl_NewListObj (objc, objv);
    cmdObjv[2] = Tcl_NewIntObj (loggingMatchCount);
    cmdObjv[3] = Tcl_NewDoubleObj (cpu);

    for (i = 0; i < 4; i++) {
	Tcl_IncrRefCount (cmdObjv[i]);
    }

    if (Tcl_EvalObjv (interp, 4, cmdObjv, 0) == TCL_ERROR) {
	Tcl_BackgroundError (interp);
    }

    for (i = 0; i < 4; i++) {
	Tcl_DecrRefCount (cmdObjv[i]);
    }

}
#endif

//
// ctable_TeardownSearch - tear down (free) a search structure and the
//  stuff within it.
//
static void
ctable_TeardownSearch (CTableSearch *search) {
    int i;

    if (search->filters) {
	ckfree((char*)search->filters);
	search->filters = NULL;
    }

    if (search->components == NULL) {
        return;
    }

    // teardown components
    for (i = 0; i < search->nComponents; i++) {
	CTableSearchComponent  *component = &search->components[i];

	if (component->row1 != NULL) {
	    search->ctable->creator->delete_row (search->ctable, component->row1, CTABLE_INDEX_PRIVATE);
	}

	if (component->row2 != NULL) {
	    search->ctable->creator->delete_row (search->ctable, component->row2, CTABLE_INDEX_PRIVATE);
	}

	if (component->row3 != NULL) {
	    search->ctable->creator->delete_row (search->ctable, component->row3, CTABLE_INDEX_PRIVATE);
	}

	if (component->clientData != NULL) {
	    // this needs to be pluggable
	    if ((component->comparisonType == CTABLE_COMP_MATCH) || (component->comparisonType == CTABLE_COMP_NOTMATCH) || (component->comparisonType == CTABLE_COMP_MATCH_CASE) || (component->comparisonType == CTABLE_COMP_NOTMATCH_CASE)) {
		struct ctableSearchMatchStruct *sm = (struct ctableSearchMatchStruct*) component->clientData;
		if (sm->type == CTABLE_STRING_MATCH_UNANCHORED) {
		    boyer_moore_teardown (sm);
		}
	    }

	    ckfree ((char*)component->clientData);
	}

	ctable_FreeInRows(search->ctable, component);
    }

    ckfree ((char *)search->components);
    search->components = NULL;

    if (search->sortControl.fields != NULL) {
        ckfree ((char *)search->sortControl.fields);
	search->sortControl.fields = NULL;
        ckfree ((char *)search->sortControl.directions);
	search->sortControl.directions = NULL;
    }

    if (search->retrieveFields != NULL) {
	ckfree ((char *)search->retrieveFields);
	search->retrieveFields = NULL;
    }

    if (search->tranTable != NULL) {
        ckfree ((char *)search->tranTable);
        search->tranTable = NULL;
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
CTABLE_INTERNAL int
ctable_SetupAndPerformSearch (Tcl_Interp *interp, Tcl_Obj *CONST objv[], int objc, CTable *ctable, int indexField) {
    CTableSearch    search;
    int result;
#ifdef CTABLES_CLOCK
    struct timespec startTimeSpec;
    int loggingMatchCount = 0;
#endif


#ifdef CTABLES_CLOCK
    if (ctable->performanceCallbackEnable) {
	clock_gettime (CTABLES_CLOCK, &startTimeSpec);
    }
#endif

    // flag this search in progress
    CTableSearch *previous_search = ctable->searches;
    ctable->searches = &search;

    result = ctable_SetupSearch (interp, ctable, objv, objc, &search, indexField, previous_search);
    if (result == TCL_ERROR) {
        ctable->searches = previous_search;
        return TCL_ERROR;
    }

    // return from "setup" means "search optimized away"
    if (result == TCL_RETURN) {
	result = TCL_OK;
    } else {
        result = ctable_PerformSearch (interp, ctable, &search);
    }

#ifdef CTABLES_CLOCK
    if (ctable->performanceCallbackEnable) {
	loggingMatchCount = search.matchCount;
    }
#endif

    ctable_TeardownSearch (&search);

    ctable->searches = previous_search;

#ifdef CTABLES_CLOCK
    if (ctable->performanceCallbackEnable) {
	Tcl_Obj *saveResultObj = Tcl_GetObjResult (interp);
	Tcl_IncrRefCount (saveResultObj);
	ctable_performance_callback (interp, ctable, objv, objc, &startTimeSpec, loggingMatchCount);
	Tcl_SetObjResult (interp, saveResultObj);
    }
#endif

    return result;
}

//
// ctable_DropIndex - delete all the rows in a row's index, free the
// structure and set the field's pointer to the skip list to NULL
//
// "final" means "we're destroying the ctable". This allows us to avoid
// deleting structures in shared memory that are going away anyway.
//
CTABLE_INTERNAL void
ctable_DropIndex (CTable *ctable, int field, int final) {
    jsw_skip_t *skip = ctable->skipLists[field];
    ctable_BaseRow *row;
    int listIndexNumber = ctable->creator->fields[field]->indexNumber;

    if (skip == NULL) return;

    // Forget I had a skiplist
    ctable->skipLists[field] = NULL;

    // Delete the skiplist
    jsw_sdelete_skiplist (skip, final);

    // Don't need to reset the bucket list if it's just going to be deleted
    if(final) return;

    // Walk the table and erase the bucket lists for the row
    // We're walking the main index for the table so it's safe to
    // clear the index for $field
    CTABLE_LIST_FOREACH (ctable->ll_head, row, 0) {
	row->_ll_nodes[listIndexNumber].next = NULL;
	row->_ll_nodes[listIndexNumber].prev = NULL;
	row->_ll_nodes[listIndexNumber].head = NULL;
    }
}

//
// ctable_DropAllIndexes - delete all of a table's indexes
//
CTABLE_INTERNAL void
ctable_DropAllIndexes (CTable *ctable, int final) {
    int field;

    for (field = 0; field < ctable->creator->nFields; field++) {
        ctable_DropIndex (ctable, field, final);
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
CTABLE_INTERNAL int
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

CTABLE_INTERNAL int
ctable_DumpIndex (CTable *ctable, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];
    ctable_BaseRow *row;
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
CTABLE_INTERNAL int
ctable_ListIndex (Tcl_Interp *interp, CTable *ctable, int fieldNum) {
    jsw_skip_t *skip = ctable->skipLists[fieldNum];
    ctable_BaseRow    *p;
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

CTABLE_INTERNAL INLINE void
ctable_RemoveFromIndex (CTable *ctable, void *vRow, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];
    ctable_BaseRow *row = (ctable_BaseRow*) vRow;
    int index = ctable->creator->fields[field]->indexNumber;

#ifdef SEARCHDEBUG
printf("ctable_RemoveFromIndex row 0x%lx, field %d (%s) skip == 0x%lx\n", (long)row, field, ctable->creator->fieldNames[field], (long unsigned int)skip);
if(field == TRACKFIELD) {
  printf("BEFORE=  ");
  ctable_DumpIndex (ctable, field);
}
#endif
    // jsw_dump_head(skip);

    if (skip == NULL) {
//printf("no skiplist\n");
        return;
    }

    // invariant: prev is never NULL if in list
    if(row->_ll_nodes[index].prev == NULL) {
//printf("not in list\n");
	return;
    }
    if (ctable_ListRemoveMightBeTheLastOne (row, index)) {
//printf("i might be the last one, field %d\n", field);
        // it might be the last one, see if it really was
//printf ("row->_ll_nodes[index].head %lx\n", (long unsigned int)row->_ll_nodes[index].head);
	if (*row->_ll_nodes[index].head == NULL) {
//printf("erasing last entry field %d\n", field);
            // put the pointer back so the compare routine will have
	    // something to match
            *row->_ll_nodes[index].head = row;
	    if (!jsw_serase (skip, row)) {
		fprintf (stderr, "Attempted to remove non-existent field %s\n", ctable->creator->fields[field]->name);
	    }
	    *row->_ll_nodes[index].head = NULL; // don't think this is needed, but do it anyway
	}
    }
#ifdef SEARCHDEBUG
if(field == TRACKFIELD) {
  printf("AFTER=  ");
  ctable_DumpIndex (ctable, field);
}
fflush(stdout);
#endif

    return;
}

//
// ctable_RemoveFromAllIndexes -- remove a row from all of the indexes it's
// in -- this does a bidirectional linked list remove for each 
//
//
//
CTABLE_INTERNAL void
ctable_RemoveFromAllIndexes (CTable *ctable, ctable_BaseRow *row) {
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
CTABLE_INTERNAL INLINE int
ctable_InsertIntoIndex (Tcl_Interp *interp, CTable *ctable, ctable_BaseRow *row, int field) {
    jsw_skip_t *skip = ctable->skipLists[field];
    ctable_FieldInfo *f;
    Tcl_Obj *utilityObj;
    ctable_CreatorTable *creator = ctable->creator;
    int index = creator->fields[field]->indexNumber;

    if (skip == NULL) {
    return TCL_OK;
    }

    // invariant: prev is always NULL if not in list
    if(row->_ll_nodes[index].prev != NULL) {
	panic ("Double insert row for field %s", ctable->creator->fields[field]->name);
    }

#ifdef SANITY_CHECKS
    creator->sanity_check_pointer(ctable, (void *)row, CTABLE_INDEX_NORMAL, "ctable_InsertIntoIndex : row");
    creator->sanity_check_pointer(ctable, (void *)skip, CTABLE_INDEX_NORMAL, "ctable_InsertIntoIndex : skip");
#endif

    f = creator->fields[field];

# ifdef SEARCHDEBUG
// dump info about row being inserted
utilityObj = Tcl_NewObj();
printf("ctable_InsertIntoIndex row 0x%lx, field %d, field name %s, index %d, value '%s'\n", (long)row, field, f->name, f->indexNumber, ctable->creator->get_string (row, field, NULL, utilityObj));
fflush(stdout);
Tcl_DecrRefCount (utilityObj);
if(field == TRACKFIELD) {
  printf("BEFORE=  ");
  ctable_DumpIndex (ctable, field);
}
#endif

    if (!jsw_sinsert_linked (skip, row, f->indexNumber, f->unique)) {

	utilityObj = Tcl_NewObj();
	Tcl_AppendResult (interp, "unique check failed for field \"", f->name, "\", value \"", ctable->creator->get_string (row, field, NULL, utilityObj), "\"", (char *) NULL);
	Tcl_DecrRefCount (utilityObj);
        return TCL_ERROR;
    }

# ifdef SEARCHDEBUG
    // ctable_verifyField(ctable, field, 0);
if(field == TRACKFIELD) {
  printf("AFTER=  ");
  ctable_DumpIndex (ctable, field);
}
fflush(stdout);
#endif

    return TCL_OK;
}

//
// ctable_CreateIndex - create an index on a specified field of a specified
// ctable.
//
CTABLE_INTERNAL int
ctable_CreateIndex (Tcl_Interp *interp, CTable *ctable, int field, int depth) {
    ctable_BaseRow *row;

    jsw_skip_t      *skip;

    // make sure the field has an index set up for it
    // in the linked list nodes of the row.
    if (ctable->creator->fields[field]->indexNumber < 0) {
	Tcl_AppendResult (interp, "can't create an index on field '", ctable->creator->fields[field]->name, "' that hasn't been defined as having an index", (char *)NULL);
	return TCL_ERROR;
    }

    // make sure we're allowed to do this
#ifdef WITH_SHARED_TABLES
    if(ctable->share_type == CTABLE_SHARED_READER) {
	Tcl_AppendResult (interp, "can't create an index on a read-only table", (char *)NULL);
	return TCL_ERROR;
    }
#endif

    // if there's already a skip list, just say "fine"
    if ((skip = ctable->skipLists[field]) != NULL) {
        return TCL_OK;
    }

#ifdef WITH_SHARED_TABLES
    if(ctable->share_type == CTABLE_SHARED_MASTER)
        skip = jsw_snew (depth, ctable->creator->fields[field]->compareFunction, ctable->share);
    else
#endif
        skip = jsw_snew (depth, ctable->creator->fields[field]->compareFunction, NULL);

    // we should plug the list in last, so that concurrent users don't
    // walk an incomplete skiplist, but ctable_InsertIntoIndex needs this
    // TODO: make ctable_InsertIntoIndex a wrapper around a new "ctable_InsertIntoSkiplist"?
    ctable->skipLists[field] = skip;

    // Walk the whole table to create the index
    CTABLE_LIST_FOREACH (ctable->ll_head, row, 0) {
	// we want to be able to call out to an error handler rather
	// than fail and unwind the stack.
	// (not here so much as in read_tabsep because here we just unwind
	// and undo the new index if we get an error)
	if (ctable_InsertIntoIndex (interp, ctable, row, field) == TCL_ERROR) {
	    // you can't leave them with a partial index or there will
	    // be heck to pay later when queries don't find all the
	    // rows, etc
	    jsw_sdelete_skiplist (skip, 0);
	    ctable->skipLists[field] = NULL;
	    Tcl_AppendResult (interp, " while creating index", (char *) NULL);
	    return TCL_ERROR;
	}
    }

    return TCL_OK;
}

CTABLE_INTERNAL int
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

CTABLE_INTERNAL int
ctable_DestroyCursor(Tcl_Interp *interp, struct cursor *cursor)
{
    if(!cursor->ownerTable) return TCL_OK; // being deleted
    CTable *ctable = cursor->ownerTable;
    cursor->ownerTable = NULL;

    struct cursor *prev = NULL;
    struct cursor *next = ctable->cursors;
    while(next && next != cursor) {
	prev = next;
	next = next->nextCursor;
    }
    if(!next) return TCL_OK; // already deleted

    // Remove from ctable
    if(prev)
	prev->nextCursor = next->nextCursor;
    else
	ctable->cursors = next->nextCursor;

    if(cursor->tranTable) {
	ckfree(cursor->tranTable);
	cursor->tranTable = NULL;
    }

    if(cursor->cursorName) {
	ckfree(cursor->cursorName);
	cursor->cursorName = NULL;
    }

    if(interp && cursor->commandInfo) {
	Tcl_Command tmp = cursor->commandInfo;
	cursor->commandInfo = NULL;
	Tcl_DeleteCommandFromToken(interp, tmp);
    }

#ifdef WITH_SHARED_TABLES
    // destroying a read-locked cursor? Tag the whole ctable as locked
    if(cursor->lockCycle != LOST_HORIZON)
	ctable->cursorLock = 1;

    if(!ctable->cursors) {
	// if the table was tagged as locked, and this is the last cursor, unlock it
	if(ctable->cursorLock) {
	    read_unlock(ctable->share);
	    ctable->cursorLock = 0;
	}
        end_write(ctable);
    }
#endif

    ckfree(cursor);

    return TCL_OK;
}

CTABLE_INTERNAL struct cursor *
ctable_CreateEmptyCursor(Tcl_Interp *interp, CTable *ctable, char *cursorName)
{
	// ALLOCATE and build new cursor
        struct cursor *cursor = (struct cursor *)ckalloc(sizeof (struct cursor));

	// CREATE empty transaction table (1 element, empty)
	cursor->tranTable = (ctable_BaseRow **)ckalloc (sizeof (ctable_BaseRow *));
	cursor->tranTable[0] = (ctable_BaseRow *)NULL;
	cursor->tranIndex = 0;

	// INITIALIZE default values
        cursor->cursorName = cursorName;
        cursor->offset = 0;
        cursor->offsetLimit = 0;
	cursor->commandInfo = NULL;
#ifdef WITH_SHARED_TABLES
	cursor->lockCycle = LOST_HORIZON;
#endif

	// INSERT cursor into cursor list
        cursor->nextCursor = ctable->cursors;
        ctable->cursors = cursor;

	// SAVE ctable link in cursor
        cursor->ownerTable = ctable;

	// MARK cursor as valid
	cursor->cursorState = CTABLE_CURSOR_OK;

	return cursor;
}

CTABLE_INTERNAL struct cursor *
ctable_CreateCursor(Tcl_Interp *interp, CTable *ctable, CTableSearch *search)
{
	// Defense - if it's already been created from this search, or the search doesn't need a cursor, drop it
	if (!search->tranTable || !search->cursorName) return NULL;

	// ALLOCATE and build new cursor
        struct cursor *cursor = (struct cursor *)ckalloc(sizeof (struct cursor));

	// MOVE transaction table naem cursor name to cursor
        cursor->tranTable = search->tranTable;
        search->tranTable = NULL;
        cursor->cursorName = search->cursorName;
	search->cursorName = NULL;

	// COPY search cursor info to cursor
        cursor->offset = cursor->tranIndex = search->offset;
        cursor->offsetLimit = search->offsetLimit;

	// INSERT cursor into cursor list
        cursor->nextCursor = ctable->cursors;
        ctable->cursors = cursor;

	// SAVE ctable link in cursor
        cursor->ownerTable = ctable;

	// MARK cursor as valid
	cursor->cursorState = CTABLE_CURSOR_OK;

	// INIT remaining feilds
	cursor->commandInfo = NULL;
#ifdef WITH_SHARED_TABLES
	cursor->lockCycle = LOST_HORIZON;
#endif

	return cursor;
}

CTABLE_INTERNAL void
ctable_DeleteCursorCommand(ClientData clientData)
{
	struct cursor *cursor = (struct cursor *)clientData;

	// Make sure we don't lead ourselves back here
	cursor->commandInfo = NULL;

	// Remove the cursor from the ctable and destroy it
	ctable_DestroyCursor(NULL, cursor);
}

CTABLE_INTERNAL int
ctable_CreateCursorCommand(Tcl_Interp *interp, struct cursor *cursor)
{
	if(cursor->commandInfo) return TCL_OK; // already exists

	Tcl_ObjCmdProc *commandProc = cursor->ownerTable->creator->cursor_command;

	cursor->commandInfo = Tcl_CreateObjCommand(interp, cursor->cursorName, commandProc, (ClientData)cursor, ctable_DeleteCursorCommand);

	return cursor->commandInfo ? TCL_OK : TCL_ERROR;
}

CTABLE_INTERNAL Tcl_Obj *
ctable_CursorToName(struct cursor *cursor)
{
	return Tcl_NewStringObj(cursor->cursorName, -1);
}


// vim: set ts=8 sw=4 sts=4 noet :
