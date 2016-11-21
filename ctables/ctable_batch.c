
/*
 * Ctable batch routines
 *
 * $Id$
 *
 */

//
// ctable_RunBatch - Run a batch of ctable commands without invoking the
//     Tcl interpreter.  
//
// Any commands that return non-empty results or have error results get
// accumulated into a result list that gets returned.
//
// Returned is a list of lists, one per non-empty or error result, where
// the first element is the index number of the list element that got
// the error or non-empty result, whether it's an error or OK return,
// (the actual Tcl result code as in return -code), and the result or
// error message.
//
static int
ctable_RunBatch (CTable *ctable, Tcl_Obj *tableCmdObj, Tcl_Obj *batchListObj) {
    int          listObjc;
    Tcl_Obj    **listObjv;
    Tcl_Interp  *interp = ctable->creator->interp;

    int          i;
    int          commandResult = TCL_ERROR;

    Tcl_Obj     *resultListObj = Tcl_NewObj ();

    Tcl_Obj     *commandResultObj;

    Tcl_Obj     *oneResultObj[2];
    Tcl_Obj     *oneResultValueObj[2];

    if (Tcl_ListObjGetElements (interp, batchListObj, &listObjc, &listObjv) == TCL_ERROR) {
	Tcl_AppendResult (interp, " while processing batch list", (char *)NULL);
	return TCL_ERROR;
    }

    // nothing to do?  ok, you get a nice, pristine, empty result
    if (listObjc == 0) {
        return TCL_OK;
    }

    for (i = 0; i < listObjc; i++) {
        int          cmdObjc;
        Tcl_Obj    **cmdObjv;

	Tcl_Obj     *batchCmdObj;

	batchCmdObj = listObjv[i];
	if (Tcl_IsShared (batchCmdObj)) {
	    batchCmdObj = Tcl_DuplicateObj (batchCmdObj);
	}

	if (Tcl_ListObjReplace (interp, batchCmdObj, 0, 0, 1, &tableCmdObj) == TCL_ERROR) {
	    commandResult = TCL_ERROR;
	    goto accumulate_result;
	}

	if (Tcl_ListObjGetElements (interp, batchCmdObj, &cmdObjc, &cmdObjv) == TCL_ERROR) {
	    commandResult = TCL_ERROR;
	    goto accumulate_result;
	}

        // reset the result since the command we're about to invoke sets
	// stuff into the result.  we make arrangements to copy out the
	// result if anything's there after executing the command.

        Tcl_ResetResult (interp);
        commandResult = ctable->creator->command (ctable, interp, cmdObjc, cmdObjv);
	commandResultObj = Tcl_GetObjResult (interp);

        // if we got an OK result and nothing in the result object, there's
	// nothing to accumulate in our result list
	if ((commandResult == TCL_OK) && (commandResultObj->typePtr == NULL && commandResultObj->length == 0)) continue;

      accumulate_result:

        // each result sublist is {indexNumber {tclResultNumber tclResultValue}}

        oneResultObj[0] = Tcl_NewIntObj (i);

	oneResultValueObj[0] = Tcl_NewIntObj (commandResult);
	oneResultValueObj[1] = Tcl_GetObjResult (interp);

	oneResultObj[1] = Tcl_NewListObj (2, oneResultValueObj);

	if (Tcl_ListObjAppendElement (interp, resultListObj, Tcl_NewListObj (2, oneResultObj))) {
	    Tcl_AppendResult (interp, " while appending a command result", (char *)NULL);
	    return TCL_ERROR;
	}
    }

    Tcl_SetObjResult (interp, resultListObj);
    return TCL_OK;
}

// vim: set ts=8 sw=4 sts=4 noet :
