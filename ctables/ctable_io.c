// General I/O routines for ctables
// $Id$
//
#include <ctype.h>

//
// Quote a string, possibly reallocating the string, returns TRUE if the
// string was modified and needs to be freed.
//
int ctable_quoteString(CONST char **stringPtr, int *stringLengthPtr, int quoteType, char *quotedChars)
{
    int          i, j = 0;
    CONST char  *string = *stringPtr;
    int          length = stringLengthPtr ? *stringLengthPtr : strlen(string);
    char        *new = NULL;
    int		 quoteChar = '\0'; // no quote by default
    int		 maxExpansion = 4; // worst possible worst case

    static char *special = "\b\f\n\r\t\v\\";
    static char *replace = "bfnrtv\\";

    switch(quoteType) {
	case CTABLE_QUOTE_URI:
	case CTABLE_QUOTE_STRICT_URI:
	    quoteChar = '%';
	    maxExpansion = 3; // %xx
	    break;
	case CTABLE_QUOTE_ESCAPE:
	    quoteChar = '\\';
	    maxExpansion = 4; // \nnn
	    break;
	case CTABLE_QUOTE_NONE:
	    return 0;
    }

    if(!quotedChars) quotedChars = "\t";

    for(i = 0; i < length; i++) {
	char c = string[i];
	if(c == '\n' || c == quoteChar || strchr(quotedChars, c)) {
	    if(!new) {
	        new = ckalloc(maxExpansion * length + 1);
	        for(j = 0; j < i; j++)
		     new[j] = string[j];
	    }
	    switch(quoteType) {
		case CTABLE_QUOTE_URI:
		case CTABLE_QUOTE_STRICT_URI:
		    sprintf(&new[j], "%%%02x", c);
		    j += 3;
		    break;
		case CTABLE_QUOTE_ESCAPE: {
		    char *off = strchr(special, c);
		    new[j++] = '\\';
		    if(off) {
			new[j++] = replace[off - special];
		    } else {
			sprintf(&new[j], "%03o", c);
			j += 3;
		    }
		    break;
		}
		case CTABLE_QUOTE_NONE: // can't happen
		    new[j++] = c;  // but do something sane anyway
		    break;
	    }
	} else if(new) {
	    new[j++] = c;
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
    int dequoteType = quoteType;
    if(dequoteType == CTABLE_QUOTE_STRICT_URI)
	dequoteType = CTABLE_QUOTE_URI;

    if(quoteType == CTABLE_QUOTE_NONE) {
	strncpy(dst, src, length);
	return length;
    }

    while(i < length) {
	if(dequoteType == CTABLE_QUOTE_URI && src[i] == '%') {
	    if(!isxdigit(src[i+1]) || !isxdigit(src[i+2])) {
		if(quoteType == CTABLE_QUOTE_STRICT_URI) return -1;
		else goto ignore;
	    }

	    c = src[i+3];
	    src[i+3] = '\0';
	    dst[j++] = strtol(&src[i+1], NULL, 16);
	    src[i+3] = c;
	    i += 3;
	} else if(dequoteType == CTABLE_QUOTE_ESCAPE && src[i] == '\\') {
	    c = src[++i];
	    if(c >= '0' && c <= '7') {
		int digit;
		// Doing this longhand because I need to get to the end
		// of the octal string anyway, but I don't know how long
		// it is.
		dst[j] = 0;
		for(digit = 0; digit < 3; digit++) {
			dst[j] = dst[j] * 8 + c - '0';
			c = src[i];
			if(c < '0' || c > '7') break;
			i++;
		}
		j++;
	    } else {
	        switch(c) {
		    case 'n': c = '\n'; break;
		    case 't': c = '\t'; break;
		    case 'r': c = '\r'; break;
		    case 'b': c = '\b'; break;
		    case 'f': c = '\f'; break;
		    case 'v': c = '\v'; break;
	        }
		dst[j++] = c;
		i++;
	    }
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

static CONST char *ctable_quote_names[] = { "none", "uri", "escape", NULL };
static int         ctable_quote_types[] = { CTABLE_QUOTE_NONE, CTABLE_QUOTE_URI, CTABLE_QUOTE_ESCAPE };

//
// Convert a type name to a quote type
//
int ctable_parseQuoteType(Tcl_Interp *interp, Tcl_Obj *obj) {
    int index;

    if (Tcl_GetIndexFromObj (interp, obj, ctable_quote_names, "type", TCL_EXACT, &index) != TCL_OK)
	return -1;
    else
	return ctable_quote_types[index];
}

//
// Return a list of ctable quote type names (cache it, too)
//
Tcl_Obj *ctable_quoteTypeList(Tcl_Interp *interp) {
    static Tcl_Obj *result = NULL;

    if (!result) {
        int index;
	result = Tcl_NewObj();
        for(index = 0; ctable_quote_names[index]; index++)
	    Tcl_ListObjAppendElement(interp, result, Tcl_NewStringObj(ctable_quote_names[index], -1));
	Tcl_IncrRefCount(result);
    }
    return result;
}

