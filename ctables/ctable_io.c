// General I/O routines for ctables
// $Id$
//
#include <ctype.h>

//
// Quote a string, possibly reallocating the string, returns TRUE if the
// string was modified and needs to be freed.
//
CTABLE_INTERNAL int
ctable_quoteString(CONST char **stringPtr, int *stringLengthPtr, int quoteType, CONST char *quotedChars)
{
    int          i, j = 0;
    CONST char  *string = *stringPtr;
    int          length = (stringLengthPtr ? *stringLengthPtr : strlen(string));
    char        *newptr = NULL;
    int		 quoteChar = '\0'; // no quote by default
    int		 maxExpansion = 4; // worst possible worst case
    int		 strict = 0;

    static CONST char *special = "\b\f\n\r\t\v\\";
    static CONST char *replace = "bfnrtv\\";

    if(quoteType == CTABLE_QUOTE_STRICT_URI) {
	quoteType = CTABLE_QUOTE_URI;
	strict = 1;
    }
    if(quoteType == CTABLE_QUOTE_STRICT_ESCAPE) {
	quoteType = CTABLE_QUOTE_ESCAPE;
	strict = 1;
    }

    switch(quoteType) {
	case CTABLE_QUOTE_URI:
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

    if(!quotedChars) quotedChars = "\t"; // Default separator string

    for(i = 0; i < length; i++) {
	unsigned char c = string[i];
	if(c == quoteChar || strchr(quotedChars, c)
	|| c < 0x20 || (strict && (c & 0x80)) ) {
	    if(!newptr) {
	        newptr = (char *) ckalloc(maxExpansion * length + 1);
	        for(j = 0; j < i; j++)
		     newptr[j] = string[j];
	    }
	    switch(quoteType) {
		case CTABLE_QUOTE_URI:
		    snprintf(&newptr[j], 4, "%%%02x", c);
		    j += 3;
		    break;
		case CTABLE_QUOTE_ESCAPE: {
		    char *off = strchr(special, c);
		    newptr[j++] = '\\';
		    if(off) {
			newptr[j++] = replace[off - special];
		    } else {
			snprintf(&newptr[j], 4, "%03o", c);
			j += 3;
		    }
		    break;
		}
		case CTABLE_QUOTE_NONE: // can't happen
		    newptr[j++] = c;  // but do something sane anyway
		    break;
	    }
	} else if(newptr) {
	    newptr[j++] = c;
	}
    }

    if(newptr) {
	newptr[j] = '\0';
	*stringPtr = newptr;
	if(stringLengthPtr) *stringLengthPtr = j;
	return 1;
    }
    return 0;
}

//
// Dequote a string to a new copy. Returns the new length or -1 for a string
// format error.
//
CTABLE_INTERNAL int
ctable_copyDequoted(char *dst, CONST char *src, int length, int quoteType)
{
    int i = 0, j = 0;
    int strict = 0;

    if(length < 0) length = strlen(src);
    int dequoteType = quoteType;
    if(dequoteType == CTABLE_QUOTE_STRICT_URI) {
	dequoteType = CTABLE_QUOTE_URI;
	strict = 1;
    }
    if(quoteType == CTABLE_QUOTE_STRICT_ESCAPE) {
	quoteType = CTABLE_QUOTE_ESCAPE;
	strict = 1;
    }

    if(quoteType == CTABLE_QUOTE_NONE) {
	strncpy(dst, src, length);
	return length;
    }

    while(i < length) {
	if(dequoteType == CTABLE_QUOTE_URI && src[i] == '%') {
	    if(!isxdigit((unsigned char)src[i+1])
	    || !isxdigit((unsigned char)src[i+2])) {
		if(strict) return -1;
		else goto ignore;
	    } else {
	        char hextmp[3] = { src[i+1], src[i+2], '\0' };
		dst[j++] = strtol(hextmp, NULL, 16);
		i += 3;
	    }
	} else if(dequoteType == CTABLE_QUOTE_ESCAPE && src[i] == '\\') {
	    char c = src[++i];
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
    if(j < i || dst != src) {
	dst[j] = '\0';
    }

    return j;
}

//
// Dequote a string, in place. Returns the new length or -1 for a string
// format error. quoteType can be CTABLE_QUOTE_URI or CTABLE_QUOTE_STRICT_URI
//
CTABLE_INTERNAL int ctable_dequoteString(char *string, int length, int quoteType)
{
    return ctable_copyDequoted(string, string, length, quoteType);
}

static CONST char *ctable_quote_names[] = { "none", "uri", "escape", "strict_uri", "strict_escape", NULL };
static int         ctable_quote_types[] = { CTABLE_QUOTE_NONE, CTABLE_QUOTE_URI, CTABLE_QUOTE_ESCAPE, CTABLE_QUOTE_STRICT_URI, CTABLE_QUOTE_STRICT_ESCAPE };

//
// Convert a type name to a quote type
//
CTABLE_INTERNAL int ctable_parseQuoteType(Tcl_Interp *interp, Tcl_Obj *obj)
{
    int index;

    if (Tcl_GetIndexFromObj (interp, obj, ctable_quote_names, "type", TCL_EXACT, &index) != TCL_OK)
	return -1;
    else
	return ctable_quote_types[index];
}

//
// Return a list of ctable quote type names (cache it, too)
//
CTABLE_INTERNAL Tcl_Obj *ctable_quoteTypeList(CTable *ctable)
{
    if(!ctable->creator->quoteTypeList) {
	Tcl_Interp *interp = ctable->creator->interp;
	int index;
	Tcl_Obj *result = Tcl_NewObj();

	for(index = 0; ctable_quote_names[index]; index++) {
	    Tcl_ListObjAppendElement(interp, result, Tcl_NewStringObj(ctable_quote_names[index], -1));
	}

	ctable->creator->quoteTypeList = result;
	Tcl_IncrRefCount(ctable->creator->quoteTypeList);
    }

    return ctable->creator->quoteTypeList;
}

// vim: set ts=8 sw=4 sts=4 noet :
