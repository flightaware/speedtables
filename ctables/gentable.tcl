#
# CTables - code to generate Tcl C extensions that implement tables out of
# C structures
#
#
# $Id$
#

namespace eval ctable {
    variable table
    variable tables
    variable booleans
    variable nonBooleans
    variable fields
    variable fieldList
    variable ctableTypes

    variable leftCurly
    variable rightCurly

    set leftCurly \173
    set rightCurly \175

    set tables ""

    set cvsID {CTable generator ID: $Id$}

set ctableTypes "boolean fixedstring varstring char mac short int long wide float double inet tclobj"

if {![info exists srcDir]} {
    set srcDir .
}

set fp [open $srcDir/template.c-subst]
set metaTableSource [read $fp]
close $fp

set fp [open $srcDir/init-exten.c-subst]
set initExtensionSource [read $fp]
close $fp

set fp [open $srcDir/exten-frag.c-subst]
set extensionFragmentSource [read $fp]
close $fp

#
# emit - emit a string to the file being generated
#
proc emit {text} {
    variable ofp

    puts $ofp $text
}

#
# cquote -- quote a string so the C compiler will see the same thing
#  if it occurs inside double-quotes
#
proc cquote {string} {
  # first, escape the metacharacters \ and "
  regsub -all {["\\]} $string {\\&} string

  # Now loop over the string looking for nonprinting characters
  set quoted ""
  while {
    [regexp {([[:graph:]]*)([^[:graph:]])(.*)} $string _ plain char string]
  } {
    append quoted $plain
    # gratuitously make \n and friends look nice
    set index [string first $char "\r\n\t\b\f"]
    if {$index == -1} {
      scan $char %c decimal
      set plain [format {\%03o} $decimal]
    } else {
      set plain [lindex {{\r} {\n} {\t} {\b} {\f}} $index]
    }
    append quoted $plain
  }
  append quoted $string
  return $quoted
}

#
# field_to_enum - return a field mapped to the name we'll use when
#  creating or referencing an enumerated list of field names.
#
#  for example, creating table fa_position and field longitude, this
#   routine will return FIELD_FA_POSITION_LONGITUDE
#
proc field_to_enum {field} {
    variable table

    return "FIELD_[string toupper $table]_[string toupper $field]"
}

#
# boolSetSource - code we run subst over to generate a set of a boolean (bit)
#
set boolSetSource {
      case $optname: {
        int boolean;

	if (${table}_obj_is_null (obj)) {
	    $pointer->_${field}IsNull = 1;
	    break;
	}

        if (Tcl_GetBooleanFromObj (interp, obj, &boolean) == TCL_ERROR) {
            Tcl_AppendResult (interp, " while converting $field", (char *)NULL);
            return TCL_ERROR;
        }

        $pointer->$field = boolean;
	$pointer->_${field}IsNull = 0;
        break;
      }
}

#
# numberSetSource - code we run subst over to generate a set of a standard
#  number such as an integer, long, double, and wide integer.  (We have to 
#  handle shorts and floats specially due to type coercion requirements.)
#
set numberSetSource {
      case $optname: {

	if (${table}_obj_is_null (obj)) {
	    $pointer->_${field}IsNull = 1;
	    break;
	}

	if ($getObjCmd (interp, obj, &$pointer->$field) == TCL_ERROR) {
	    Tcl_AppendResult (interp, " while converting $field", (char *)NULL);
	    return TCL_ERROR;
	}

	$pointer->_${field}IsNull = 0;
	break;
      }
}

#
# floatSetSource - code we run subst over to generate a set of a float.
#
set floatSetSource {
      case $optname: {
	double value;

	if (${table}_obj_is_null (obj)) {
	    $pointer->_${field}IsNull = 1;
	    break;
	}

	if (Tcl_GetDoubleFromObj (interp, obj, &value) == TCL_ERROR) {
	    Tcl_AppendResult (interp, " while converting $field", (char *)NULL);
	    return TCL_ERROR;
	}

	$pointer->$field = (float)value;
	$pointer->_${field}IsNull = 0;
	break;
      }
}

#
# shortSetSource - code we run subst over to generate a set of a float.
#
set shortSetSource {
      case $optname: {
	int value;

	if (${table}_obj_is_null (obj)) {
	    $pointer->_${field}IsNull = 1;
	    break;
	}

	if (Tcl_GetIntFromObj (interp, obj, &value) == TCL_ERROR) {
	    Tcl_AppendResult (interp, " while converting $field", (char *)NULL);
	    return TCL_ERROR;
	}

	$pointer->$field = (short)value;
	$pointer->_${field}IsNull = 0;
	break;
      }
}

#
# varstringSetSource - code we run subst over to generate a set of a string.
#
# strings are char *'s that we manage automagically.
#
# Get the string from the passed-in object.  If the length of the string
# matches the length of the default string, see if the length of the
# default string is zero or if obj's string matches the default string.
# If so, set the char * field in the row to NULL.  Upon a fetch of the
# field, we'll provide the default string.
#
# Otherwise allocate space for the new string value and copy it in.
#
set varstringSetSource {
      case $optname: {
	char *string;
	int   length;

	if ($pointer->$field != (char *) NULL) {
	    ckfree ($pointer->$field);
	    $pointer->$field = NULL;
	}

	if (${table}_obj_is_null (obj)) {
	    $pointer->_${field}IsNull = 1;
	    break;
	}

	string = Tcl_GetStringFromObj (obj, &length);
	if (length == $defaultLength) {
	    if (($defaultLength == 0) || (strncmp (string, "$default", $defaultLength) == 0)) {
	        $pointer->$field = NULL;
		$pointer->_${field}Length = 0;
		break;
	    }
	}
	$pointer->$field = ckalloc (length + 1);
	strncpy ($pointer->$field, string, length + 1);
	$pointer->_${field}Length = length;
	break;
      }
}

#
# charSetSource - code we run subst over to generate a set of a single char.
#
set charSetSource {
      case $optname: {
	char *string;

	if (${table}_obj_is_null (obj)) {
	    $pointer->_${field}IsNull = 1;
	    break;
	}

	string = Tcl_GetString (obj);
	$pointer->$field = string[0];
	$pointer->_${field}IsNull = 0;
	break;
      }
}

#
# fixedstringSetSource - code we run subst over to generate a set of a 
# fixed-length string.
#
set fixedstringSetSource {
      case $optname: {
	char *string;

	if (${table}_obj_is_null (obj)) {
	    $pointer->_${field}IsNull = 1;
	    break;
	}

	string = Tcl_GetString (obj);
	strncpy ($pointer->$field, string, $length);
	$pointer->_${field}IsNull = 0;
	break;
      }
}

#
# inetSetSource - code we run subst over to generate a set of an IPv4
# internet address.
#
set inetSetSource {
      case $optname: {

	if (${table}_obj_is_null (obj)) {
	    $pointer->_${field}IsNull = 1;
	    break;
	}

	if (!inet_aton (Tcl_GetString (obj), &$pointer->$field)) {
	    Tcl_AppendResult (interp, "expected IP address but got \"", Tcl_GetString (obj), "\" parsing field \"$field\"", (char *)NULL);
	    return TCL_ERROR;
	}

	$pointer->_${field}IsNull = 0;
	break;
      }
}

#
# macSetSource - code we run subst over to generate a set of an ethernet
# MAC address.
#
set macSetSource {
      case $optname: {
        struct ether_addr *mac;

	if (${table}_obj_is_null (obj)) {
	    $pointer->_${field}IsNull = 1;
	    break;
	}

	mac = ether_aton (Tcl_GetString (obj));
	if (mac == (struct ether_addr *) NULL) {
	    Tcl_AppendResult (interp, "expected MAC address but got \"", Tcl_GetString (obj), "\" parsing field \"$field\"", (char *)NULL);
	    return TCL_ERROR;
	}

	$pointer->$field = *mac;
	$pointer->_${field}IsNull = 0;

	break;
      }
}

#
# tclobjSetSource - code we run subst over to generate a set of a tclobj.
#
# tclobjs are Tcl_Obj *'s that we manage automagically.
#
set tclobjSetSource {
      case $optname: {

	if ($pointer->$field != (Tcl_Obj *) NULL) {
	    Tcl_DecrRefCount ($pointer->$field);
	    $pointer->$field = NULL;
	}

	if (${table}_obj_is_null (obj)) {
	    $pointer->_${field}IsNull = 1;
	    break;
	}

	$pointer->$field = obj;
	Tcl_IncrRefCount (obj);
	$pointer->_${field}IsNull = 0;
	break;
      }
}

#
# cmdBodyHeader - code we run subst over to generate the header of the
#  code body that implements the methods that work on the table.
#
set cmdBodyHeader {
void ${table}_delete_all_rows(struct ${table}StructTable *tbl_ptr) {
    Tcl_HashSearch hashSearch;
    Tcl_HashEntry *hashEntry;
    struct ${table} *$pointer;

    for (hashEntry = Tcl_FirstHashEntry (tbl_ptr->keyTablePtr, &hashSearch); hashEntry != (Tcl_HashEntry *) NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {
	$pointer = (struct $table *) Tcl_GetHashValue (hashEntry);
	${table}_delete($pointer);
    }
    Tcl_DeleteHashTable (tbl_ptr->keyTablePtr);

    tbl_ptr->count = 0;
}

int ${table}ObjCmd (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])
$leftCurly
    struct $rowStructTable *tbl_ptr = (struct $rowStructTable *)cData;
    struct $table *$pointer;
    int optIndex;
    Tcl_HashEntry *hashEntry;
    int new;

    static CONST char *options[] = {"get", "set", "array_get", "exists", "delete", "null_value", "count", "foreach", "type", "import", "fields", "fieldtype", "needs_quoting", "names", "reset", "destroy", "statistics", (char *)NULL};

    enum options {OPT_GET, OPT_SET, OPT_ARRAYGET, OPT_EXISTS, OPT_DELETE, OPT_NULLVALUE, OPT_COUNT, OPT_FOREACH, OPT_TYPE, OPT_IMPORT, OPT_FIELDS, OPT_FIELDTYPE, OPT_NEEDSQUOTING, OPT_NAMES, OPT_RESET, OPT_DESTROY, OPT_STATISTICS};

}

#
# cmdBodySource - code we run subst over to generate the second chunk of the
#  body that implements the methods that work on the table.
#
set cmdBodySource {

    if (objc == 1) {
        Tcl_WrongNumArgs (interp, 1, objv, "option ?args?");
	return TCL_ERROR;
    }

    if (Tcl_GetIndexFromObj (interp, objv[1], options, "option", TCL_EXACT, &optIndex) != TCL_OK) {
	Tcl_Obj      **calloutObjv;
	int           i;
	int           result;

	hashEntry = Tcl_FindHashEntry (tbl_ptr->registeredProcTablePtr, Tcl_GetString (objv[1]));

	if (hashEntry == (Tcl_HashEntry *) NULL) {
	    Tcl_HashSearch hashSearch;

	    Tcl_AppendResult (interp, ", or one of the registered methods:", (char *)NULL);

	    for (hashEntry = Tcl_FirstHashEntry (tbl_ptr->registeredProcTablePtr, &hashSearch); hashEntry != (Tcl_HashEntry *) NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {
	        char *key = Tcl_GetHashKey (tbl_ptr->registeredProcTablePtr, hashEntry);
		Tcl_AppendResult (interp, " ", key, (char *)NULL);
	    }
	    return TCL_ERROR;
	}

	calloutObjv = (Tcl_Obj **)ckalloc (sizeof (Tcl_Obj *) * objc);
	calloutObjv[0] = (Tcl_Obj *)Tcl_GetHashValue (hashEntry);
	calloutObjv[1] = objv[0];
	for (i = 2; i < objc; i++) {
	    calloutObjv[i] = objv[i];
	}
	result = Tcl_EvalObjv (interp, objc, calloutObjv, 0);
	ckfree ((void *)calloutObjv);
	return result;
    }

    switch ((enum options) optIndex) $leftCurly
      case OPT_TYPE: {
          Tcl_SetObjResult (interp, Tcl_NewStringObj ("$table", -1));
	  return TCL_OK;
      }

      case OPT_FIELDS: {
          int i;
	  Tcl_Obj *resultObj = Tcl_GetObjResult(interp);

	  for (i = 0; ${table}_fields[i] != (char *) NULL; i++) {
	      if (Tcl_ListObjAppendElement (interp, resultObj, Tcl_NewStringObj (${table}_fields[i], -1)) == TCL_ERROR) {
	          return TCL_ERROR;
	      }
	  }
          return TCL_OK;
      }

      case OPT_FIELDTYPE: {
        int fieldIndex;

	if (objc != 3) {
            Tcl_WrongNumArgs (interp, 2, objv, "fieldName");
	    return TCL_ERROR;
	}

	if (Tcl_GetIndexFromObj (interp, objv[2], ${table}_fields, "field", TCL_EXACT, &fieldIndex) != TCL_OK) {
	    return TCL_ERROR;
	}
	Tcl_SetStringObj (Tcl_GetObjResult (interp), ctableTypes[(int)${table}_types[fieldIndex]], -1);
	return TCL_OK;
      }

      case OPT_NEEDSQUOTING: {
        int fieldIndex;

	if (objc != 3) {
            Tcl_WrongNumArgs (interp, 2, objv, "fieldName");
	    return TCL_ERROR;
	}

	if (Tcl_GetIndexFromObj (interp, objv[2], ${table}_fields, "field", TCL_EXACT, &fieldIndex) != TCL_OK) {
	    return TCL_ERROR;
	}
	Tcl_SetBooleanObj (Tcl_GetObjResult (interp), ${table}_needs_quoting[fieldIndex]);
	return TCL_OK;
      }


      case OPT_STATISTICS: {
          CONST char *stats = Tcl_HashStats (tbl_ptr->keyTablePtr);
	  Tcl_SetStringObj (Tcl_GetObjResult (interp), stats, -1);
	  ckfree ((char *)stats);
	  return TCL_OK;
      }

      case OPT_FOREACH: {
	  Tcl_HashSearch  hashSearch;
	  char           *pattern = (char *) NULL;
	  char           *key;

	  if ((objc < 4) || (objc > 5)) {
	      Tcl_WrongNumArgs (interp, 2, objv, "varName codeBody ?pattern?");
	      return TCL_ERROR;
	  }

	  if (objc == 5) {
	      pattern = Tcl_GetString (objv[4]);
	  }

	  for (hashEntry = Tcl_FirstHashEntry (tbl_ptr->keyTablePtr, &hashSearch); hashEntry != (Tcl_HashEntry *) NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {
	      key = Tcl_GetHashKey (tbl_ptr->keyTablePtr, hashEntry);
	      if ((pattern != (char *) NULL) && (!Tcl_StringCaseMatch (key, pattern, 1))) continue;
	      if (Tcl_ObjSetVar2 (interp, objv[2], (Tcl_Obj *)NULL, Tcl_NewStringObj (key, -1), TCL_LEAVE_ERR_MSG) == (Tcl_Obj *) NULL) {
	          return TCL_ERROR;
	      }
	      switch (Tcl_EvalObjEx (interp, objv[3], 0)) {
	        case TCL_ERROR:
		  Tcl_AppendResult (interp, " while processing foreach code body", (char *) NULL);
		  return TCL_ERROR;

		case TCL_OK:
		case TCL_CONTINUE:
		  break;

		case TCL_BREAK:
		  return TCL_OK;

		case TCL_RETURN:
		  return TCL_RETURN;
	      }
	  }
	  return TCL_OK;
      }


      case OPT_NAMES: {
          Tcl_Obj        *resultObj = Tcl_GetObjResult (interp);
	  Tcl_HashSearch  hashSearch;
	  char           *pattern = (char *) NULL;
	  char           *key;

	  if (objc > 3) {
	      Tcl_WrongNumArgs (interp, 2, objv, "varName codeBody ?pattern?");
	      return TCL_ERROR;
	  }

	  if (objc == 3) {
	      pattern = Tcl_GetString (objv[2]);
	  }

	  for (hashEntry = Tcl_FirstHashEntry (tbl_ptr->keyTablePtr, &hashSearch); hashEntry != (Tcl_HashEntry *) NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {
	      key = Tcl_GetHashKey (tbl_ptr->keyTablePtr, hashEntry);
	      if ((pattern != (char *) NULL)  && (!Tcl_StringCaseMatch (key, pattern, 1))) continue;
	      if (Tcl_ListObjAppendElement (interp, resultObj, Tcl_NewStringObj (key, -1)) == TCL_ERROR) {
	          return TCL_ERROR;
	      }
	  }
	  return TCL_OK;
      }

      case OPT_RESET: {
	  ${table}_delete_all_rows (tbl_ptr);
	  Tcl_InitCustomHashTable (tbl_ptr->keyTablePtr, TCL_STRING_KEYS, (Tcl_HashKeyType *)NULL);
	  TAILQ_INIT (&tbl_ptr->rows);
	  return TCL_OK;
      }

      case OPT_DESTROY: {
	  ${table}_delete_all_rows (tbl_ptr);
          Tcl_DeleteCommandFromToken (interp, tbl_ptr->commandInfo);
	  return TCL_OK;
      }

      case OPT_DELETE: {
	hashEntry = Tcl_FindHashEntry (tbl_ptr->keyTablePtr, Tcl_GetString (objv[2]));

	if (hashEntry == (Tcl_HashEntry *) NULL) {
	    Tcl_SetBooleanObj (Tcl_GetObjResult (interp), 0);
	    return TCL_OK;
	}

	$pointer = (struct $table *) Tcl_GetHashValue (hashEntry);
	${table}_delete($pointer);
	Tcl_DeleteHashEntry (hashEntry);
	tbl_ptr->count--;
	Tcl_SetBooleanObj (Tcl_GetObjResult (interp), 1);
	return TCL_OK;
      }

      case OPT_NULLVALUE: {
	  return TCL_OK;
      }


      case OPT_COUNT: {
          Tcl_SetIntObj (Tcl_GetObjResult (interp), tbl_ptr->count);
	  return TCL_OK;
      }

      case OPT_EXISTS: {
	hashEntry = Tcl_FindHashEntry (tbl_ptr->keyTablePtr, Tcl_GetString (objv[2]));

	if (hashEntry == (Tcl_HashEntry *) NULL) {
	    Tcl_SetBooleanObj (Tcl_GetObjResult (interp), 0);
	} else {
	    Tcl_SetBooleanObj (Tcl_GetObjResult (interp), 1);
	}
	return TCL_OK;
      }

      case OPT_IMPORT: {
        int    fieldIds[$nFields];
	int    i;
	int    nFields = 0;

	if (objc < 3) {
	  Tcl_WrongNumArgs (interp, 2, objv, "proc ?field field...?");
	  return TCL_ERROR;
	}

	if (objc > $nFields + 3) {
	  Tcl_WrongNumArgs (interp, 2, objv, "proc ?field field...?");
          Tcl_AppendResult (interp, " More fields requested than exist in record", (char *)NULL);
	  return TCL_ERROR;
	}

	if (objc == 3) {
	    nFields = $nFields;
	    for (i = 0; i < $nFields; i++) {
	        fieldIds[i] = i;
	    }
	} else {
	    for (i = 3; i < objc; i++) {
	        if (Tcl_GetIndexFromObj (interp, objv[i], ${table}_fields, "field", TCL_EXACT, &fieldIds[nFields++]) != TCL_OK) {
		    return TCL_ERROR;
		}
	    }
	}

	while (1) {
	    switch (Tcl_EvalObjEx (interp, objv[2], 0)) {
	      int       new;
	      int       listObjc;
	      Tcl_Obj **listObjv;

	      case TCL_ERROR:
	        Tcl_AppendResult (interp, " while processing import code body", (char *)NULL);
	        return TCL_ERROR;

	      case TCL_OK:
	      case TCL_CONTINUE:
	        if (Tcl_ListObjGetElements (interp, Tcl_GetObjResult (interp), &listObjc, &listObjv) == TCL_ERROR) {
		    Tcl_AppendResult (interp, " while processing code result", (char *)NULL);
	            return TCL_ERROR;
	        }

	        if (listObjc == 0) {
	            return TCL_OK;
	        }

	        if (nFields + 1 != listObjc) {
		    Tcl_SetObjResult (interp, Tcl_NewStringObj ("number of fields in list does not match what was expected", -1));
	            return TCL_ERROR;
	        }

	        $pointer = ${table}_find_or_create (tbl_ptr, Tcl_GetString (listObjv[0]), &new);
	        for (i = 1; i <= nFields; i++) {
	            if (${table}_set (interp, listObjv[i], $pointer, fieldIds[i - 1]) == TCL_ERROR) {
		        return TCL_ERROR;
		    }
	        }
	        break;

	      case TCL_BREAK:
	        return TCL_OK;

	      case TCL_RETURN:
	        return TCL_RETURN;
	    }
	}
      }

      case OPT_SET: {
        int       i;

	if ((objc < 3) || (objc % 2) != 1) {
	    Tcl_WrongNumArgs (interp, 2, objv, "key field value ?field value...?");
	    return TCL_ERROR;
	}

        $pointer = ${table}_find_or_create (tbl_ptr, Tcl_GetString (objv[2]), &new);

	for (i = 3; i < objc; i += 2) {
	    // printf ("i = %d\n", i);
	    if (${table}_set_fieldobj (interp, objv[i+1], $pointer, objv[i]) == TCL_ERROR) {
	        return TCL_ERROR;
	    }
	}
        break;
      }

}

set tableHeadSource {
struct ${table}StructHeadTable {
    Tcl_HashTable     *registeredProcTablePtr;
    long unsigned int  nextAutoCounter;
};

struct ${table}StructTable {
    Tcl_HashTable *registeredProcTablePtr;
    Tcl_HashTable *keyTablePtr;
    Tcl_Command    commandInfo;
    long           count;
    TAILQ_HEAD (${table}Head, $table) rows;
};
}

set fieldObjSetSource {
struct $table *${table}_find_or_create (struct ${table}StructTable *tbl_ptr, char *key, int *newPtr) {
    struct $table *${table}_ptr;

    Tcl_HashEntry *hashEntry = Tcl_CreateHashEntry (tbl_ptr->keyTablePtr, key, newPtr);

    if (*newPtr) {
        ${table}_ptr = (struct $table *)ckalloc (sizeof (struct $table));
	${table}_init (${table}_ptr);
	Tcl_SetHashValue (hashEntry, (ClientData)${table}_ptr);
	tbl_ptr->count++;
	// printf ("created new entry for '%s'\n", key);
    } else {
        ${table}_ptr = (struct $table *) Tcl_GetHashValue (hashEntry);
	// printf ("found existing entry for '%s'\n", key);
    }

    return ${table}_ptr;
}

int
${table}_set_fieldobj (Tcl_Interp *interp, Tcl_Obj *obj, struct $table *$pointer, Tcl_Obj *fieldObj)
{
    int fieldIndex;

    if (Tcl_GetIndexFromObj (interp, fieldObj, ${table}_fields, "field", TCL_EXACT, &fieldIndex) != TCL_OK) {
        return TCL_ERROR;
    }

    return ${table}_set (interp, obj, $pointer, fieldIndex);
}
}

set fieldSetSource {
int
${table}_set (Tcl_Interp *interp, Tcl_Obj *obj, struct $table *$pointer, int field) $leftCurly

    switch ((enum ${table}_fields) field) $leftCurly
}

set fieldObjGetSource {
struct $table *${table}_find (struct ${table}StructTable *tbl_ptr, char *key) {
    Tcl_HashEntry *hashEntry;

    hashEntry = Tcl_FindHashEntry (tbl_ptr->keyTablePtr, key);
    if (hashEntry == (Tcl_HashEntry *) NULL) {
        return (struct $table *) NULL;
    }
    
    return (struct $table *) Tcl_GetHashValue (hashEntry);
}

Tcl_Obj *
${table}_get_fieldobj (Tcl_Interp *interp, struct $table *$pointer, Tcl_Obj *fieldObj)
{
    int fieldIndex;

    if (Tcl_GetIndexFromObj (interp, fieldObj, ${table}_fields, "field", TCL_EXACT, &fieldIndex) != TCL_OK) {
        return (Tcl_Obj *)NULL;
    }

    return ${table}_get (interp, $pointer, fieldIndex);
}

int
${table}_lappend_fieldobj (Tcl_Interp *interp, struct $table *$pointer, Tcl_Obj *fieldObj)
{
    Tcl_Obj *obj = ${table}_get_fieldobj (interp, $pointer, fieldObj);

    if (obj == NULL) {
        return TCL_ERROR;
    }

    if (Tcl_ListObjAppendElement (interp, Tcl_GetObjResult (interp), obj) == TCL_ERROR) {
        return TCL_ERROR;
    }

    return TCL_OK;
}
}

set fieldAndNameObjGetSource {
int
${table}_lappend_field_and_nameobj (Tcl_Interp *interp, struct $table *$pointer, Tcl_Obj *fieldObj)
{
    int        fieldIndex;
    Tcl_Obj   *obj;

    if (Tcl_GetIndexFromObj (interp, fieldObj, ${table}_fields, "field", TCL_EXACT, &fieldIndex) != TCL_OK) {
        return TCL_ERROR;
    }

    if (Tcl_ListObjAppendElement (interp, Tcl_GetObjResult (interp), ${table}_NameObjList[fieldIndex]) == TCL_ERROR) {
        return TCL_ERROR;
    }

    obj = ${table}_get (interp, $pointer, fieldIndex);
    if (Tcl_ListObjAppendElement (interp, Tcl_GetObjResult (interp), obj) == TCL_ERROR) {
        return TCL_ERROR;
    }

    return TCL_OK;
}

}

set fieldGetSource {
Tcl_Obj *
${table}_get (Tcl_Interp *interp, struct $table *$pointer, int field) $leftCurly

    switch ((enum ${table}_fields) field) $leftCurly
}

set fieldGetStringSource {
CONST char *
${table}_get_string (struct $table *$pointer, int field, int *lengthPtr, Tcl_Obj *utilityObj) $leftCurly
    int length;

    if (lengthPtr == (int *) NULL) {
        lengthPtr = &length;
    }

    switch ((enum ${table}_fields) field) $leftCurly
}


#
# cmdBodyGetSource - chunk of the code that we run subst over to generate
#  part of the body of the code that handles the "get" method
#
set cmdBodyGetSource {
      case OPT_GET: {
        int i;

	if (objc < 3) {
	    Tcl_WrongNumArgs (interp, 2, objv, "key ?field...?");
	    return TCL_ERROR;
	}

	$pointer = ${table}_find (tbl_ptr, Tcl_GetString (objv[2]));
	if ($pointer == (struct $table *) NULL) {
	    return TCL_OK;
	}

	if (objc == 3) {
	    return ${table}_genlist (interp, $pointer);
	}

	for (i = 3; i < objc; i++) {
	    if (${table}_lappend_fieldobj (interp, $pointer, objv[i]) == TCL_ERROR) {
	        return TCL_ERROR;
	    }
	}
        break;
      }
}

#
# cmdBodyArrayGetSource - chunk of the code that we run subst over to generate
#  part of the body of the code that handles the "array_get" method
#
set cmdBodyArrayGetSource {
      case OPT_ARRAYGET: {
        int i;

	if (objc < 3) {
	    Tcl_WrongNumArgs (interp, 2, objv, "key ?field...?");
	    return TCL_ERROR;
	}

	$pointer = ${table}_find (tbl_ptr, Tcl_GetString (objv[2]));
	if ($pointer == (struct $table *) NULL) {
	    return TCL_OK;
	}

	if (objc == 3) {
	    return ${table}_gen_keyvalue_list (interp, $pointer);
	}

	for (i = 3; i < objc; i++) {
	    if (${table}_lappend_field_and_nameobj (interp, $pointer, objv[i]) == TCL_ERROR) {
	        return TCL_ERROR;
	    }
	}
        break;
      }
}

#
# table - the proc that starts defining a table, really, a meta table, and
#  also following it will be the definition of the structure itself
#
proc table {name} {
    variable table
    variable booleans
    variable nonBooleans
    variable fields
    variable fieldList

    set table $name

    set booleans ""
    catch {unset fields}
    set fieldList ""
    set nonBooleans ""
}

#
# end_table - proc that declares the end of defining a table - currently does
#  nothing
#
proc end_table {} {
}

#
# deffield - helper for defining fields -- all of the field-defining procs
#  use this except for boolean that subsumes its capabilities, since we
#  need to keep booleans separately for sanity of the C structures
#
#  NB do we really?  i don't know
#
proc deffield {name args} {
    variable fields
    variable fieldList
    variable nonBooleans

    if {![regexp {^[a-zA-Z][_a-zA-Z0-9]*$} $name]} {
        error "field name \"$name\" must start with a letter and can only contain letters, numbers, and underscores"
    }

    lappend args name $name

    set fields($name) $args
    lappend fieldList $name
    lappend nonBooleans $name
}

#
# boolean - define a boolean field -- same contents as deffield except it
#  appends to the booleans list instead of the nonBooleans list NB kludge
#
proc boolean {name {default 0}} {
    variable booleans
    variable fields
    variable fieldList

    if {![regexp {^[a-zA-Z][_a-zA-Z0-9]*$} $name]} {
        error "field name \"$name\" must start with a letter and can only contain letters, numbers, and underscores"
    }

    set fields($name) [list name $name type boolean default $default]
    lappend fieldList $name
    lappend booleans $name
}

#
# fixedstring - define a fixed-length string field
#
proc fixedstring {name length {default ""}} {
    if {[string length $default] != $length} {
        error "fixedstring \"$name\" default string \"$default\" must match length \"$length\""
    }
    deffield $name type fixedstring length $length default $default needsQuoting 1
}

#
# varstring - define a variable-length string field
#
proc varstring {name {default ""}} {
    deffield $name type varstring default $default needsQuoting 1
}

#
# char - define a single character field -- this should probably just be
#  fixedstring[1] but it's simpler.  shrug.
#
proc char {name {default " "}} {
    deffield $name type char default $default needsQuoting 1
}

#
# mac - define a mac address field
#
proc mac {name {default 00:00:00:00:00:00}} {
    deffield $name type mac default $default
}

#
# short - define a short integer field
#
proc short {name {default 0}} {
    deffield $name type short default $default
}

#
# int - define an integer field
#
proc int {name {default 0}} {
    deffield $name type int default $default
}

#
# long - define a long integer field
#
proc long {name {default 0}} {
    deffield $name type long default $default
}

#
# wide - define a wide integer field -- should always be at least 64 bits
#
proc wide {name {default 0}} {
    deffield $name type wide default $default
}

#
# float - define a floating point field
#
proc float {name {default 0.0}} {
    deffield $name type float default $default
}

#
# double - define a double-precision floating point field
#
proc double {name {default 0.0}} {
    deffield $name type double default $default
}

#
# inet - define an IPv4 address field
#
proc inet {name {default 0.0.0.0}} {
    deffield $name type inet default $default
}

#
# tclobj - define an straight-through Tcl_Obj
#
proc tclobj {name} {
    deffield $name type tclobj needsQuoting 1
}

#
# putfield - write out a field definition when emitting a C struct
#
proc putfield {type name {comment ""}} {
    if {[string index $name 0] != "*"} {
        set name " $name"
    }

    if {$comment != ""} {
        set comment " /* $comment */"
    }
    emit [format "    %-20s %s;%s" $type $name $comment]
}

#
# ctable_type_to_enum - return a type mapped to the name we use when
#  creating or referencing an enumerated list of ctable types.
#
proc ctable_type_to_enum {type} {
    return "CTABLE_TYPE_[string toupper $type]"
}

#
# gen_ctable_type_stuff - generate enumerated type for all of the supported
# ctable fields and generated an array of char pointers to the type names
#
proc gen_ctable_type_stuff {} {
    variable ctableTypes
    variable leftCurly
    variable rightCurly

    set typeEnum "enum ctable_types $leftCurly"
    foreach type $ctableTypes {
        append typeEnum "\n    [ctable_type_to_enum $type],"
    }
    emit "[string range $typeEnum 0 end-1]\n$rightCurly;\n"

    emit "char *ctableTypes\[\] = $leftCurly"
    foreach type $ctableTypes {
        emit "    \"$type\","
    }
    emit "    (char *) NULL"
    emit "$rightCurly;"
    emit ""
}

set ctableTypes "boolean fixedstring varstring char mac short int long wide float double inet tclobj"

#
# gen_defaults_subr - gen code to set a row to default values
#
proc gen_defaults_subr {subr struct pointer} {
    variable table
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set baseCopy ${struct}_basecopy

    emit "void ${subr}(struct $struct *$pointer) $leftCurly"
    emit "    static int firstPass = 1;"
    emit "    static struct $struct $baseCopy;"
    emit ""
    emit "    if (firstPass) $leftCurly"
    emit "        firstPass = 0;"

    foreach myfield $fieldList {
        catch {unset field}
	array set field $fields($myfield)

	switch $field(type) {
	    varstring {
	        emit "        $baseCopy.$myfield = (char *) NULL;"
		emit "        $baseCopy._${myfield}Length = 0;"
	    }

	    fixedstring {
	        emit "        strncpy ($baseCopy.$myfield, \"$field(default)\", $field(length));"
	    }

	    mac {
	        emit "        $baseCopy.$myfield = *ether_aton (\"$field(default)\");"
	    }

	    inet {
	        emit "        inet_aton (\"$field(default)\", &$baseCopy.$myfield);"
	    }

	    char {
	        emit "        $baseCopy.$myfield = '[string index $field(default) 0]';"
	    }

	    tclobj {
	        emit "        $baseCopy.$myfield = (Tcl_Obj *) NULL;"
	    }

	    default {
	        emit "        $baseCopy.$myfield = $field(default);"
	    }
	}
    }

    foreach myfield $fieldList {
        emit "        $baseCopy._${myfield}IsNull = 1;"
    }

    emit "    $rightCurly"
    emit ""
    emit "    *$pointer = $baseCopy;"

    emit "$rightCurly"
    emit ""
}

#
# gen_delete_subr - gen code to delete (free) a row
#
proc gen_delete_subr {subr struct pointer} {
    variable table
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    emit "void ${subr}(struct $struct *$pointer) {"

    foreach myfield $fieldList {
        catch {unset field}
	array set field $fields($myfield)

	switch $field(type) {
	    varstring {
	        emit "    if ($pointer->$myfield != (char *) NULL) ckfree ($pointer->$myfield);"
	    }
	}
    }
    emit "    ckfree ((char *)$pointer);"

    emit "}"
    emit ""
}


set isNullSubrSource {
int ${table}_obj_is_null(Tcl_Obj *obj) {
    char     *nullValueString;
    int       nullValueLength;

    char     *objString;
    int       objStringLength;

     nullValueString = Tcl_GetStringFromObj (${table}_NullValueObj, &nullValueLength);
     objString = Tcl_GetStringFromObj (obj, &objStringLength);

    if (nullValueLength != objStringLength) {
        return 0;
    }

    if (nullValueLength == 0) {
        return 1;
    }

    if (*nullValueString != *objString) {
        return 0;
    }

    return (strncmp (nullValueString, objString, nullValueLength) == 0);
}
}

#
# gen_is_null_subr - gen code to determine if an object contains the null value
#
proc gen_obj_is_null_subr {} {
    variable table
    variable isNullSubrSource

    emit [subst -nobackslashes -nocommands $isNullSubrSource]
}


#
# gen_struct - gen the table being defined's C structure
#
proc gen_struct {} {
    variable table
    variable booleans
    variable nonBooleans
    variable fields
    variable fieldList

    emit "struct $table {"
    #putfield TAILQ_ENTRY($table) ${table}_link
    putfield TAILQ_ENTRY($table) _link

    foreach myfield $nonBooleans {
        catch {unset field}
	array set field $fields($myfield)

	switch $field(type) {
	    varstring {
		putfield char "*$field(name)"
		putfield int  "_$field(name)Length"
	    }

	    fixedstring {
		putfield char "$field(name)\[$field(length)]"
	    }

	    mac {
		putfield "struct ether_addr" $field(name)
	    }

	    inet {
		putfield "struct in_addr" $field(name)
	    }

	    tclobj {
		putfield "struct Tcl_Obj" "*$field(name)"
	    }

	    default {
		putfield $field(type) $field(name)
	    }
	}
    }

    foreach myfield $booleans {
	putfield "unsigned int" "$myfield:1"
    }

    foreach myfield $fieldList {
        putfield "unsigned int" _${myfield}IsNull:1
    }

    emit "};"
    emit ""
}

#
# emit_set_num_field - emit code to set a numeric field
#
proc emit_set_num_field {field pointer type} {
    variable numberSetSource
    variable table

    set typeText $type

    switch $type {
        short {
	    set newObjCmd Tcl_NewIntObj
	    set getObjCmd Tcl_GetIntFromObj
	}

        int {
	    set newObjCmd Tcl_NewIntObj
	    set getObjCmd Tcl_GetIntFromObj
	}

	long {
	    set newObjCmd Tcl_NewLongObj
	    set getObjCmd Tcl_GetLongFromObj

	}

	wide {
	    set type "Tcl_WideInt"
	    set newObjCmd Tcl_NewWideIntObj
	    set getObjCmd Tcl_GetWideIntFromObj
	    set typeText "wide int"
	}

	double {
	    set newObjCmd Tcl_NewDoubleObj
	    set getObjCmd Tcl_GetDoubleFromObj
	    set typeText "double"
	}

	default {
	    error "unknown numeric field type: $type"
	}
    }

    set optname [field_to_enum $field]

    emit [subst -nobackslashes -nocommands $numberSetSource]
}

#
# emit_set_standard_field - emit code to set a field that has a
# "set source" string to go with it and gets managed in a standard
#  way
#
proc emit_set_standard_field {field pointer setSourceVarName} {
    variable $setSourceVarName
    variable table

    set optname [field_to_enum $field]

    emit [subst -nobackslashes -nocommands [set $setSourceVarName]]
}

#
# emit_set_varstring_field - emit code to set a varstring field
#
proc emit_set_varstring_field {table field pointer default defaultLength} {
    variable varstringSetSource

    set default [cquote $default]

    set optname [field_to_enum $field]

    emit [subst -nobackslashes -nocommands $varstringSetSource]
}

#           
# emit_set_fixedstring_field - emit code to set a fixedstring field
#
proc emit_set_fixedstring_field {field pointer length} {
    variable fixedstringSetSource
    variable table
      
    set optname [field_to_enum $field]

    emit [subst -nobackslashes -nocommands $fixedstringSetSource]
} 

#
# gen_sets - emit code to set all of the fields of the table being defined
#
proc gen_sets {pointer} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly
    variable cmdBodyHeader

    foreach myfield $fieldList {
        catch {unset field}
	array set field $fields($myfield)

	switch $field(type) {
	    int {
		emit_set_num_field $myfield $pointer int
	    }

	    long {
		emit_set_num_field $myfield $pointer long
	    }

	    wide {
		emit_set_num_field $myfield $pointer wide
	    }

	    double {
		emit_set_num_field $myfield $pointer double
	    }

	    fixedstring {
		emit_set_fixedstring_field $myfield $pointer $field(length)
	    }

	    short {
		emit_set_standard_field $myfield $pointer shortSetSource
	    }

	    float {
	        emit_set_standard_field $myfield $pointer floatSetSource
	    }

	    varstring {
		emit_set_varstring_field $table $myfield $pointer $field(default) [string length $field(default)]
	    }

	    boolean {
		emit_set_standard_field $myfield $pointer boolSetSource
	    }

	    char {
		emit_set_standard_field $myfield $pointer charSetSource
	    }

	    inet {
	        emit_set_standard_field $myfield $pointer inetSetSource
	    }

	    mac {
	        emit_set_standard_field $myfield $pointer macSetSource
	    }

	    tclobj {
	        emit_set_standard_field $myfield $pointer tclobjSetSource
	    }

	    default {
	        error "attempt to emit set field of unknown type $field(type)"
	    }
	}
    }
}

#
# gen_table_head_source - emit the code to define the head structures
#
proc gen_table_head_source {table} {
    variable tableHeadSource

    emit [subst -nobackslashes -nocommands $tableHeadSource]
}

#
# put_metatable_source - emit the code to define the meta table (table-defining
# command)
#
proc put_metatable_source {table} {
    variable metaTableSource

    set Id {CTable template Id}

    emit [subst -nobackslashes -nocommands $metaTableSource]
}

#
# put_init_command_source - emit the code to initialize create within Tcl
# the command that will invoke the C command defined by 
# put_metatable_source
#
proc put_init_command_source {table} {
    variable extensionFragmentSource

    set Id {init extension Id}

    emit [subst -nobackslashes -nocommands $extensionFragmentSource]
}

#
# put_init_extension_source - emit the code to create the C functions that
# Tcl will expect to find when loading the shared library.
#
proc put_init_extension_source {extension extensionVersion} {
    variable initExtensionSource
    variable tables

    set structHeadTablePointers ""
    foreach name $tables {
        append structHeadTablePointers "    struct ${name}StructHeadTable *${name}StructHeadTablePtr;\n";
    }

    set Id {init extension Id}

    emit [subst -nobackslashes -nocommands $initExtensionSource]
}

#
# gen_set_function - create a *_set routine that takes a pointer to the
# tcl interp, an object, a pointer to a table row and a field number,
# and sets the value extracted from the obj into the field of the row
#
proc gen_set_function {table pointer} {
    variable fieldObjSetSource
    variable fieldSetSource
    variable leftCurly
    variable rightCurly

    emit [subst -nobackslashes -nocommands $fieldSetSource]

    gen_sets $pointer

    emit "    $rightCurly"
    emit "    return TCL_OK;"
    emit "$rightCurly"

    emit [subst -nobackslashes -nocommands $fieldObjSetSource]

}

#
# gen_get_function - create a *_get routine that takes a pointer to the
#  tcl interp, an object pointer, a pointer to a table row and a field number,
#  and gets the value from the field of the row and store it into the
#  object.
#
#  Also create a *_get_fieldobj function that takes pointers to the same
#  tcl interpreter, object, and table row but takes an object containg
#  a string identifying the field, which is then looked up to identify
#  the field number and used in a call to the *_get function.
#
proc gen_get_function {table pointer} {
    variable fieldObjGetSource
    variable fieldAndNameObjGetSource
    variable fieldGetSource
    variable fieldGetStringSource
    variable leftCurly
    variable rightCurly

    emit [subst -nobackslashes -nocommands $fieldGetSource]
    gen_gets_cases $pointer
    emit "    $rightCurly"
    emit "    return TCL_OK;"
    emit "$rightCurly"

    emit [subst -nobackslashes -nocommands $fieldObjGetSource]

    emit [subst -nobackslashes -nocommands $fieldAndNameObjGetSource]

    emit [subst -nobackslashes -nocommands $fieldGetStringSource]
    gen_gets_string_cases $pointer
    emit "    $rightCurly"
    emit "    return TCL_OK;"
    emit "$rightCurly"


}

#
# gen_setup_routine - emit code to be run for this table type at shared 
#  libary load time
#
proc gen_setup_routine {table} {
    variable fieldList
    variable fields
    variable leftCurly
    variable rightCurly

    emit "void ${table}_setup (void) $leftCurly"

    # create and initialize all of the NameObj objects containing field
    # names as Tcl objects and increment their reference counts so 
    # (hopefully, heh) they'll never be deleted.
    #
    # also populate the *_NameObjList table
    #
    set position 0
    foreach field $fieldList {
	set nameObj ${table}_${field}NameObj
        emit "    ${table}_NameObjList\[$position\] = $nameObj = Tcl_NewStringObj (\"$field\", -1);"
	emit "    Tcl_IncrRefCount ($nameObj);"
	emit ""
	incr position
    }
    emit "    ${table}_NameObjList\[$position\] = (Tcl_Obj *) NULL;"
    emit ""

    set defaultEmptyStringCreated 0
    #
    # create and initialize string objects for varstring defaults
    #
    emit "    // defaults for varstring objects, if any"
    foreach fieldName $fieldList {
        catch {unset field}
	array set field $fields($fieldName)

	if {$field(type) != "varstring"} continue

	set defObj ${table}_${fieldName}DefaultStringObj

	if {$field(default) == ""} {
	    if {!$defaultEmptyStringCreated} {
	        set defaultEmptyStringCreated 1
		set emptyObj ${table}_DefaultEmptyStringObj
		emit "    $emptyObj = Tcl_NewObj ();"
		emit "    Tcl_IncrRefCount ($emptyObj);"
		emit ""
	    }
	} else {
	    emit "    $defObj = Tcl_NewStringObj (\"[cquote $field(default)]\", -1);"
	    emit "    Tcl_IncrRefCount ($defObj);"
	    emit ""
	}
    }

    emit "    // initialize the null string object to the default (empty) value"
    emit "    ${table}_NullValueObj = Tcl_NewObj ();"
    emit "    Tcl_IncrRefCount (${table}_NullValueObj);"

    emit "$rightCurly"
    emit ""
}

#
# gen_code - generate all of the code for the underlying methods for
#  managing a created table
#
proc gen_code {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly
    variable cmdBodyHeader
    variable cmdBodySource
    variable cmdBodyGetSource
    variable cmdBodyArrayGetSource

    set pointer "${table}_ptr"

    set nFields [string toupper $table]_NFIELDS

    set rowStructTable ${table}StructTable
    set rowStructHeadTable ${table}StructHeadTable
    set rowStruct $table

    gen_set_function $table $pointer

    gen_get_function $table $pointer

    emit [subst -nobackslashes -nocommands $cmdBodyHeader]

    emit [subst -nobackslashes -nocommands $cmdBodySource]

    emit [subst -nobackslashes -nocommands $cmdBodyGetSource]

    emit [subst -nobackslashes -nocommands $cmdBodyArrayGetSource]

    # finish out the command switch and the command itself
    emit "    $rightCurly"
    emit "    return TCL_OK;"
    emit "$rightCurly"
}

#
# gen_new_obj - given a data type, pointer name and field name, return
#  the C code to generate a Tcl object containing that element from the
#  pointer pointing to the named field.
#
proc gen_new_obj {type pointer fieldName} {
    variable fields
    variable table

    switch $type {
	short {
	    return "$pointer->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewIntObj ($pointer->$fieldName)"
	}

	int {
	    return "$pointer->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewIntObj ($pointer->$fieldName)"
	}

	long {
	    return "$pointer->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewLongObj ($pointer->$fieldName)"
	}

	wide {
	    return "$pointer->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewWideIntObj ($pointer->$fieldName)"
	}

	double {
	    return "$pointer->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewDoubleObj ($pointer->$fieldName)"
	}

	float {
	    return "$pointer->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewDoubleObj ($pointer->$fieldName)"
	}

	boolean {
	    return "$pointer->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewBooleanObj ($pointer->$fieldName)"
	}

	varstring {
	    catch {unset field}
	    array set field $fields($fieldName)

	    if {$field(default) == ""} {
		set defObj ${table}_DefaultEmptyStringObj
	    } else {
		set defObj ${table}_${fieldName}DefaultStringObj
	    }

	    return "(($pointer->$fieldName == (char *) NULL) ? $defObj  : Tcl_NewStringObj ($pointer->$fieldName, $pointer->_${fieldName}Length))"
	}

	char {
	    return "$pointer->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewStringObj (&$pointer->$fieldName, 1)"
	}

	fixedstring {
	    catch {unset field}
	    array set field $fields($fieldName)
	    return "$pointer->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewStringObj ($pointer->$fieldName, $field(length))"
	}

	inet {
	    return "$pointer->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewStringObj (inet_ntoa ($pointer->$fieldName), -1)"
	}

	mac {
	    return "$pointer->_${fieldName}IsNull ? ${table}_NullValueObj : Tcl_NewStringObj (ether_ntoa (&$pointer->$fieldName), -1)"
	}

	tclobj {
	    return "(($pointer->$fieldName == (Tcl_Obj *) NULL) ? Tcl_NewObj () : $pointer->$fieldName)"
	}

	default {
	    error "no code to gen obj for type $type"
	}
    }
}

#
# gen_set_obj - given an object, a data type, pointer name and field name, 
#  return the C code to set a Tcl object to contain that element from the
#  pointer pointing to the named field.
#
# note: this is an inefficient way to get the value of varstrings,
# fixedstrings and chars, and can't even do tclobjs.  
#
# do what gen_get_string_cases does, or call its parent anyway *_get_string,
# to get string representations of those efficiently.
#
proc gen_set_obj {obj type pointer fieldName} {
    variable fields
    variable table

    switch $type {
	short {
	    return "Tcl_SetIntObj ($obj, $pointer->$fieldName)"
	}

	int {
	    return "Tcl_SetIntObj ($obj, $pointer->$fieldName)"
	}

	long {
	    return "Tcl_SetLongObj ($obj, $pointer->$fieldName)"
	}

	wide {
	    return "Tcl_SetWideIntObj ($obj, $pointer->$fieldName)"
	}

	double {
	    return "Tcl_SetDoubleObj ($obj, $pointer->$fieldName)"
	}

	float {
	    return "Tcl_SetDoubleObj ($obj, $pointer->$fieldName)"
	}

	boolean {
	    return "Tcl_SetBooleanObj ($obj, $pointer->$fieldName)"
	}

	varstring {
	    return "Tcl_SetStringObj ($obj, $pointer->$fieldName, $pointer->_${fieldName}Length)"
	}

	char {
	    return "Tcl_SetStringObj ($obj, &$pointer->$fieldName, 1)"
	}

	fixedstring {
	    catch {unset field}
	    array set field $fields($fieldName)
	    return "Tcl_SetStringObj ($obj, $pointer->$fieldName, $field(length))"
	}

	inet {
	    return "Tcl_SetStringObj ($obj, inet_ntoa ($pointer->$fieldName), -1)"
	}

	mac {
	    return "Tcl_SetStringObj ($obj, ether_ntoa (&$pointer->$fieldName), -1)"
	}

	tclobj {
	    error "can't set a string to a tclobj (field \"$fieldName\") -- you have to handle this outside of gen_set_obj"
	}

	default {
	    error "no code to gen obj for type $type"
	}
    }
}

#
# set_list_obj - generate C code to emit a Tcl obj containing the named
#  field into a list that's being cons'ed up
#
proc set_list_obj {position type pointer field} {
    emit "    listObjv\[$position] = [gen_new_obj $type $pointer $field];"
}

#
# append_list_element - generate C code to append a list element to the
#  output object.  used by code that lets you get one or more named fields.
#
proc append_list_element {type pointer field} {
    return "Tcl_ListObjAppendElement (interp, Tcl_GetObjResult (interp), [gen_new_obj $type $pointer $field])"
}

#
# gen_list - generate C code to emit an entire row into a Tcl list
#
proc gen_list {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set pointer ${table}_ptr

    set lengthDef [string toupper $table]_NFIELDS

    emit "int ${table}_genlist (Tcl_Interp *interp, struct $table *$pointer) $leftCurly"

    emit "    Tcl_Obj *listObjv\[$lengthDef];"
    emit ""

    set position 0
    foreach fieldName $fieldList {
        catch {unset field}
	array set field $fields($fieldName)

	set_list_obj $position $field(type) $pointer $fieldName

	incr position
    }

    emit "    Tcl_SetObjResult (interp, Tcl_NewListObj ($lengthDef, listObjv));"
    emit "    return TCL_OK;"
    emit "$rightCurly"
    emit ""
}

#
# gen_keyvalue_list - generate C code to emit an entire row into a Tcl list in
#  "array set" format
#
proc gen_keyvalue_list {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set pointer ${table}_ptr

    set lengthDef [string toupper $table]_NFIELDS

    emit "int ${table}_gen_keyvalue_list (Tcl_Interp *interp, struct $table *$pointer) $leftCurly"

    emit "    Tcl_Obj *listObjv\[$lengthDef * 2];"
    emit ""

    set position 0
    foreach fieldName $fieldList {
        catch {unset field}
	array set field $fields($fieldName)

	emit "    listObjv\[$position] = ${table}_${fieldName}NameObj;"
	incr position

	set_list_obj $position $field(type) $pointer $fieldName
	incr position

	emit ""
    }

    emit "    Tcl_SetObjResult (interp, Tcl_NewListObj ($lengthDef * 2, listObjv));"
    emit "    return TCL_OK;"
    emit "$rightCurly"
    emit ""
}


#
# gen_field_names - generate C code containing an array of pointers to strings
#  comprising the names of all of the fields in a row of the table being
#  defined.  Also generate an enumerated type of all of the field names
#  mapped to uppercase and prepended with FIELD_ for use with
#  Tcl_GetIndexFromObj in figuring out what fields are wanted
#
proc gen_field_names {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    emit "#define [string toupper $table]_NFIELDS [llength $fieldList]"
    emit ""

    emit "static CONST char *${table}_fields\[] = $leftCurly"
    foreach myfield $fieldList {
	emit "    \"$myfield\","
    
    }
    emit "    (char *) NULL"
    emit "$rightCurly;\n"

    set fieldenum "enum ${table}_fields $leftCurly"
    foreach myField $fieldList {
	append fieldenum "\n    [field_to_enum $myField],"
    }
    set fieldenum "[string range $fieldenum 0 end-1]\n$rightCurly;\n"
    emit $fieldenum

    set typeList "enum ctable_types ${table}_types\[\] = $leftCurly"
    foreach myField $fieldList {
        catch {unset field}
	array set field $fields($myField)

	append typeList "\n    [ctable_type_to_enum $field(type)],"
    }
    emit "[string range $typeList 0 end-1]\n$rightCurly;\n"

    set needsQuoting "int ${table}_needs_quoting\[\] = $leftCurly"
    foreach myField $fieldList {
        catch {unset field}
	array set field $fields($myField)
	if {[info exists field(needsQuoting)] && $field(needsQuoting)} {
	    set quoting 1
	} else {
	    set quoting 0
	}
	append needsQuoting "\n    $quoting,"
    }
    emit "[string range $needsQuoting 0 end-1]\n$rightCurly;\n"

    emit "// define objects that will be filled with the corresponding field names"
    foreach myfield $fieldList {
        emit "Tcl_Obj *${table}_${myfield}NameObj;"
    }
    emit ""

    emit "Tcl_Obj *${table}_NameObjList\[[string toupper $table]_NFIELDS + 1\];"
    emit ""

    set defaultStringObjCreated 0

    emit "// define the null value object"
    emit "Tcl_Obj *${table}_NullValueObj;"
    emit ""

    emit "// define default objects for varstring fields, if any"
    foreach myField $fieldList {
        catch {unset field}
	array set field $fields($myField)

	if {$field(type) == "varstring"} {
	    if {$field(default) == ""} {
	        if {!$defaultStringObjCreated} {
		    set defaultStringObjCreated 1
		    emit "Tcl_Obj *${table}_DefaultEmptyStringObj;"
		}
	    } else {
		emit "Tcl_Obj *${table}_${myField}DefaultStringObj;"
	    }
	}
    }
    emit ""
}

#
# gen_gets_cases - generate case statements for each field, each case fetches
#  field from row and returns a new Tcl_Obj set with that field's value
#
proc gen_gets_cases {pointer} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    foreach myField $fieldList {
        catch {unset field}
	array set field $fields($myField)

	emit "      case [field_to_enum $myField]:"
	emit "        return [gen_new_obj $field(type) $pointer $myField];"
	emit ""
    }
}

#
# gen_gets_string_cases - generate case statements for each field, each case
#  generates a return of a char * to a string representing that field's
#  value and sets a passed-in int * to the length returned.
#
proc gen_gets_string_cases {pointer} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    foreach myField $fieldList {
        catch {unset field}
	array set field $fields($myField)

	emit "      case [field_to_enum $myField]:"

	switch $field(type) {
	  "varstring" {
	    emit "        if ($pointer->$myField == NULL) $leftCurly"

	    if {$field(default) == ""} {
	        set source ${table}_DefaultEmptyStringObj
	    } else {
	        set source ${table}_${myField}DefaultStringObj
	    }
	    emit "            return Tcl_GetStringFromObj ($source, lengthPtr);"
	    emit "        $rightCurly"
	    emit "        *lengthPtr = ${pointer}->_${myField}Length;"
	    emit "        return $pointer->$myField;"
	  }

	  "fixedstring" {
	      emit "        *lengthPtr = $field(length);"
	      emit "        return $pointer->$myField;"
	  }

	  "char" {
	      emit "        *lengthPtr = 1;"
	      emit "        return &$pointer->$myField;"
	  }

	  "tclobj" {
	    emit "        if ($pointer->$myField == NULL) $leftCurly"
	    emit "            return Tcl_GetStringFromObj (${table}_DefaultEmptyStringObj, lengthPtr);"
	    emit "        $rightCurly"
	    emit "        return Tcl_GetStringFromObj ($pointer->$myField, lengthPtr);"
	  }

	  default {
	      emit "        [gen_set_obj utilityObj $field(type) $pointer $myField];"
	      emit "        return Tcl_GetStringFromObj (utilityObj, lengthPtr);"
	  }
	}
	emit ""
    }
}

#
# gen_preamble - generate stuff that goes at the head of the C file
#  we're generating
#
proc gen_preamble {} {
    emit "/* autogenerated [clock format [clock seconds]] */"
    emit ""
    emit "#include <tcl.h>"
    emit "#include <string.h>"
    emit "#include \"queue.h\""
    emit ""
    emit "#include <sys/types.h>"
    emit "#include <sys/socket.h>"
    emit "#include <netinet/in.h>"
    emit "#include <arpa/inet.h>"
    emit "#include <net/ethernet.h>"
    emit ""
}

#
# compile - compile and link the shared library
#
proc compile {fileFragName version} {
    global tcl_platform
    variable buildPath

    set debug 0

    set buildFragName $buildPath/$fileFragName-$version
    set sourceFile $buildFragName.c
    set objFile $buildFragName.o

    switch $tcl_platform(os) {
	"FreeBSD" {
	    if {$debug} {
		set optflag "-g"
		set stub "-ltclstub84g"
		set lib "-ltcl84g"
	    } else {
		set optflag "-O3"
		set stub "-ltclstub84"
		set lib "-ltcl84"
	    }

	    exec gcc -pipe $optflag -fPIC -I/usr/local/include/tcl8.4 -I$buildPath -Wall -Wno-implicit-int -fno-common -c $sourceFile -o $objFile

	    exec ld -Bshareable $optflag -x -o $buildPath/lib${fileFragName}.so $objFile -L/usr/local/lib $stub
	}

	"Darwin" {
	    if {$debug} {
		set optflag "-g"
		set stub "-ltclstub8.4g"
		set lib "-ltcl8.4g"
	    } else {
		set optflag "-O3"
		set stub "-ltclstub8.4"
		set lib "-ltcl8.4"
	    }

	    exec gcc -pipe $optflag -fPIC -Wall -Wno-implicit-int -fno-common -I$buildPath -c $sourceFile -o $objFile

	    exec gcc -pipe $optflag -fPIC -dynamiclib  -Wall -Wno-implicit-int -fno-common  -Wl,-single_module -o $buildPath/${fileFragName}${version}.dylib $objFile -L/sc/lib $stub $lib
	}

	default {
	    error "unknown OS $tcl_platform(os)"
	}
    }

    pkg_mkIndex $buildPath
}

proc EndExtension {} {
    variable tables
    variable extension
    variable extensionVersion
    variable rightCurly
    variable ofp

    put_init_extension_source [string totitle $extension] $extensionVersion

    foreach name $tables {
	put_init_command_source $name
    }

    emit "    return TCL_OK;"
    emit $rightCurly

    close $ofp

    compile $extension $::ctable::extensionVersion
}

#
# extension_already_built - see if the extension already exists unchanged
#  from what's being asked for
#
proc extension_already_built {name version code} {
    variable buildPath
    variable cvsID

    set ctFile $buildPath/$name-$version.ct

    # if open of the stash file fails, it ain't built
    if {[catch {open $ctFile} fp] == 1} {
        #puts ".ct file not there, build required"
        return 0
    }

    # read the first line for the prior CVS ID, if failed, report not built
    if {[gets $fp priorCvsID] < 0} {
        #puts "first line read of .ct file failed, build required"
        close $fp
	return 0
    }

    # see if this file's cvs id matches the cvs id we saved in the .ct file
    # if not, rebuilt not built
    if {$cvsID != $priorCvsID} {
        #puts "prior cvs id does not match, build required"
	return 0
    }

    set priorCode [read -nonewline $fp]
    close $fp

    # if the prior code and current code aren't identical, report not built
    if {$priorCode != $code} {
        #puts "extension code changed, build required"
	return 0
    }

    #puts "prior code and generator cvs match, build not required"
    return 1
}

#
# save_extension_code - after a successful build, cache the extension
#  definition so extension_already_built can see if it's necessary to
#  generate, compile and link the shared library next time we're run
#
proc save_extension_code {name version code} {
    variable buildPath
    variable cvsID
    variable leftCurly
    variable rightCurly

    set ctFile $buildPath/$name-$version.ct

    set fp [open $ctFile w]
    puts $fp $cvsID
    puts $fp $code
    close $fp
}

#
# install_queue_h - install queue.h in the target dir if something like it
#  isn't there already
#
proc install_queue_h {targetDir} {
    variable srcDir

    if {![file readable $targetDir/queue.h]} {
        file copy $srcDir/queue.h $targetDir
    }
}

}

#
# CExtension - define a C extension
#
proc CExtension {name version code} {
    global tcl_platform

    if {![info exists ::ctable::buildPath]} {
        CTableBuildPath build
    }

    file mkdir $::ctable::buildPath

    ::ctable::install_queue_h $::ctable::buildPath

    if {[::ctable::extension_already_built $name $version $code]} {
        #puts stdout "extension $name $version unchanged"
	return
    }

    set ::ctable::ofp [open $::ctable::buildPath/$name-$version.c w]

    ::ctable::gen_preamble
    ::ctable::gen_ctable_type_stuff

    set ::ctable::extension $name
    set ::ctable::extensionVersion $version
    set ::ctable::tables ""

    namespace eval ::ctable $code

    ::ctable::EndExtension

    ::ctable::save_extension_code $name $version $code
}

#
# CTable - define a C meta table
#
proc CTable {name data} {
    ::ctable::table $name
    lappend ::ctable::tables $name
    namespace eval ::ctable $data

    ::ctable::gen_struct

    ::ctable::gen_table_head_source $name

    ::ctable::gen_field_names

    ::ctable::gen_setup_routine $name

    ::ctable::gen_defaults_subr ${name}_init $name ${name}_ptr

    ::ctable::gen_delete_subr ${name}_delete $name ${name}_ptr

    ::ctable::gen_obj_is_null_subr

    ::ctable::gen_list

    ::ctable::gen_keyvalue_list

    ::ctable::gen_code

    ::ctable::put_metatable_source $name

}

#
# CTableBuildPath - set the path for where we're building CTable stuff
#
proc CTableBuildPath {dir} {
    global auto_path

    set ::ctable::buildPath $dir

    if {[lsearch -exact $auto_path $dir] < 0} {
        lappend auto_path $dir
    }
}

package provide ctable 1.1

