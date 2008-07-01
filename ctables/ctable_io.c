// General I/O routines for ctables
// $Id$
//

//
// Quote a string, possibly reallocating the string, returns TRUE if the
// string was modified and needs to be freed.
//
int ctable_quoteString(CONST char **stringPtr, int *stringLengthPtr, int quoteType, char *quotedChars)
{
    int i, j = 0;
    CONST char *string = *stringPtr;
    int length = stringLengthPtr ? *stringLengthPtr : strlen(string);
    char *new = NULL;

    if(!quotedChars) quotedChars = "\t";

    for(i = 0; i < length; i++) {
	if(string[i] == '\n' || string[i] == '%' || strchr(quotedChars, string[i])) {
	    if(!new) {
	        new = ckalloc(3 * length + 1);
	        for(j = 0; j < i; j++)
		     new[j] = string[j];
	    }
	    // If more quote types are defined this will need to be modified
	    sprintf(new+j, "%%%02x", string[i]);
	    j += 3;
	} else if(new) {
	    new[j++] = string[i];
	}
    }

    if(new) {
	new[j] = '\0';
	*stringPtr = new;
	if(stringLengthPtr) *stringLengthPtr = j;
	return 1;
    }
    return 0;
}

//
// Dequote a string to a new copy. Returns the new length or -1 for a string
// format error. quoteType can be CTABLE_QUOTE_URI or CTABLE_QUOTE_STRICT_URI
//
int ctable_copyDequoted(char *dst, char *src, int length, int quoteType)
{
    int i = 0, j = 0, c;
    if(length < 0) length = strlen(src);

    while(i < length) {
	if(src[i] == '%') {
	    if(!isxdigit(src[i+1]) || !isxdigit(src[i+2])) {
		if(quoteType == CTABLE_QUOTE_STRICT_URI) return -1;
		else goto ignore;
	    }

	    c = src[i+3];
	    dst[j++] = strtol(&src[i+1], NULL, 16);
	    src[i+3] = c;
	    i += 3;
	} else {
ignore:	    dst[j++] = src[i++];
	}
    }

    // Only add a null terminator to original if it's truncated.
    if(j < i || dst != src)
	dst[j] = '\0';

    return j;
}

//
// Dequote a string, in place. Returns the new length or -1 for a string
// format error. quoteType can be CTABLE_QUOTE_URI or CTABLE_QUOTE_STRICT_URI
//
int ctable_dequoteString(char *string, int length, int quoteType)
{
    return ctable_copyDequoted(string, string, length, quoteType);
}

//
// Convert a type name to a quote type
//
int ctable_parseQuoteType(Tcl_Interp *interp, Tcl_Obj *obj) {
    int                index;
    static CONST char *names[] = { "none", "uri", NULL };

    if (Tcl_GetIndexFromObj (interp, obj, names, "type", TCL_EXACT, &index) != TCL_OK)
	return -1;
    else
	return index;
}
