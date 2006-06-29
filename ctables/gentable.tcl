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

    variable leftCurly
    variable rightCurly

    set leftCurly \173
    set rightCurly \175

    set tables ""

set fp [open template.c-subst]
set metaTableSource [read $fp]
close $fp

set fp [open init-exten.c-subst]
set initExtensionSource [read $fp]
close $fp

set fp [open exten-frag.c-subst]
set extensionFragmentSource [read $fp]
close $fp

proc emit {text} {
    variable ofp

    puts $ofp $text
}

#
# boolSetSource - code we run subst over to generate a set of a boolean (bit)
#
set boolSetSource {
      case $optname: {
        int boolean;

        if (Tcl_GetBooleanFromObj (interp, obj, &boolean) == TCL_ERROR) {
            Tcl_AppendResult (interp, " while converting $field", NULL);
            return TCL_ERROR;
        }

        $pointer->$field = boolean;
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
	if ($getObjCmd (interp, obj, &$pointer->$field) == TCL_ERROR) {
	    Tcl_AppendResult (interp, " while converting $field", NULL);
	    return TCL_ERROR;
	}
	break;
      }
}

#
# floatSetSource - code we run subst over to generate a set of a float.
#
set floatSetSource {
      case $optname: {
	double value;

	if (Tcl_GetDoubleFromObj (interp, obj, &value) == TCL_ERROR) {
	    Tcl_AppendResult (interp, " while converting $field", NULL);
	    return TCL_ERROR;
	}

	$pointer->$field = (float)value;
	break;
      }
}

#
# shortSetSource - code we run subst over to generate a set of a float.
#
set shortSetSource {
      case $optname: {
	int value;

	if (Tcl_GetIntFromObj (interp, obj, &value) == TCL_ERROR) {
	    Tcl_AppendResult (interp, " while converting $field", NULL);
	    return TCL_ERROR;
	}

	$pointer->$field = (short)value;
	break;
      }
}

#
# stringSetSource - code we run subst over to generate a set of a string.
#
# strings are char *'s that we manage automagically.
#
set stringSetSource {
      case $optname: {
	char *string;
	int   length;

	if ($pointer->$field != NULL) {
	    ckfree ($pointer->$field);
	}

	string = Tcl_GetStringFromObj (obj, &length);
	$pointer->$field = ckalloc (length + 1);
	strncpy ($pointer->$field, string, length + 1);
	break;
      }
}

#
# charSetSource - code we run subst over to generate a set of a single char.
#
set charSetSource {
      case $optname: {
	char *string;

	string = Tcl_GetStringFromObj (obj, NULL);
	$pointer->$field = string[0];
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

	string = Tcl_GetStringFromObj (obj, NULL);
	strncpy ($pointer->$field, string, $length);
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

    for (hashEntry = Tcl_FirstHashEntry (tbl_ptr->keyTablePtr, &hashSearch); hashEntry != NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {
	$pointer = (struct $table *) Tcl_GetHashValue (hashEntry);
	${table}_delete($pointer);
    }
    Tcl_DeleteHashTable (tbl_ptr->keyTablePtr);
}

int ${table}ObjCmd (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])
$leftCurly
    struct $rowStructTable *tbl_ptr = (struct $rowStructTable *)cData;
    struct $table *$pointer;
    int optIndex;
    Tcl_HashEntry *hashEntry;
    int new;

    static CONST char *options[] = {"get", "set", "exists", "delete", "foreach", "type", "import", "fields", "names", "reset", "destroy", "statistics", (char *)NULL};

    enum options {OPT_GET, OPT_SET, OPT_EXISTS, OPT_DELETE, OPT_FOREACH, OPT_TYPE, OPT_IMPORT, OPT_FIELDS, OPT_NAMES, OPT_RESET, OPT_DESTROY, OPT_STATISTICS};

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

	if (hashEntry == NULL) {
	    Tcl_HashSearch hashSearch;

	    Tcl_AppendResult (interp, ", or one of the registered methods:", (char *)NULL);

	    for (hashEntry = Tcl_FirstHashEntry (tbl_ptr->registeredProcTablePtr, &hashSearch); hashEntry != NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {
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

	  for (i = 0; ${table}_fields[i] != NULL; i++) {
	      if (Tcl_ListObjAppendElement (interp, resultObj, Tcl_NewStringObj (${table}_fields[i], -1)) == TCL_ERROR) {
	          return TCL_ERROR;
	      }
	  }
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
	  int             doMatch = 0;
	  char           *pattern;
	  char           *key;

	  if ((objc < 4) || (objc > 5)) {
	      Tcl_WrongNumArgs (interp, 2, objv, "varName codeBody ?pattern?");
	      return TCL_ERROR;
	  }

	  if (objc == 5) {
	      doMatch = 1;
	      pattern = Tcl_GetString (objv[4]);
	  }

	  for (hashEntry = Tcl_FirstHashEntry (tbl_ptr->keyTablePtr, &hashSearch); hashEntry != NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {
	      key = Tcl_GetHashKey (tbl_ptr->keyTablePtr, hashEntry);
	      if (doMatch && !Tcl_StringCaseMatch (key, pattern, 1)) continue;
	      if (Tcl_ObjSetVar2 (interp, objv[2], NULL, Tcl_NewStringObj (key, -1), TCL_LEAVE_ERR_MSG) == NULL) {
	          return TCL_ERROR;
	      }
	      switch (Tcl_EvalObjEx (interp, objv[3], 0)) {
	        case TCL_ERROR:
		  Tcl_AppendResult (interp, " while processing foreach code body", NULL);
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
	  int             doMatch = 0;
	  char           *pattern;
	  char           *key;

	  if (objc > 3) {
	      Tcl_WrongNumArgs (interp, 2, objv, "varName codeBody ?pattern?");
	      return TCL_ERROR;
	  }

	  if (objc == 3) {
	      doMatch = 1;
	      pattern = Tcl_GetString (objv[2]);
	  }

	  for (hashEntry = Tcl_FirstHashEntry (tbl_ptr->keyTablePtr, &hashSearch); hashEntry != NULL; hashEntry = Tcl_NextHashEntry (&hashSearch)) {
	      key = Tcl_GetHashKey (tbl_ptr->keyTablePtr, hashEntry);
	      if (doMatch && !Tcl_StringCaseMatch (key, pattern, 1)) continue;
	      if (Tcl_ListObjAppendElement (interp, resultObj, Tcl_NewStringObj (key, -1)) == TCL_ERROR) {
	          return TCL_ERROR;
	      }
	  }
	  return TCL_OK;
      }

      case OPT_RESET: {
	  ${table}_delete_all_rows (tbl_ptr);
	  Tcl_InitCustomHashTable (tbl_ptr->keyTablePtr, TCL_STRING_KEYS, NULL);
	  return TCL_OK;
      }

      case OPT_DESTROY: {
	  ${table}_delete_all_rows (tbl_ptr);
          Tcl_DeleteCommandFromToken (interp, tbl_ptr->commandInfo);
	  return TCL_OK;
      }

      case OPT_DELETE: {
	hashEntry = Tcl_FindHashEntry (tbl_ptr->keyTablePtr, Tcl_GetString (objv[2]));

	if (hashEntry == NULL) {
	    Tcl_SetBooleanObj (Tcl_GetObjResult (interp), 0);
	    return TCL_OK;
	}

	$pointer = (struct $table *) Tcl_GetHashValue (hashEntry);
	${table}_delete($pointer);
	Tcl_DeleteHashEntry (hashEntry);
	Tcl_SetBooleanObj (Tcl_GetObjResult (interp), 1);
	return TCL_OK;
      }

      case OPT_EXISTS: {
	hashEntry = Tcl_FindHashEntry (tbl_ptr->keyTablePtr, Tcl_GetString (objv[2]));

	if (hashEntry == NULL) {
	    Tcl_SetBooleanObj (Tcl_GetObjResult (interp), 0);
	} else {
	    Tcl_SetBooleanObj (Tcl_GetObjResult (interp), 1);
	}
	return TCL_OK;
      }

      case OPT_IMPORT: {
      }

      case OPT_SET: $leftCurly
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
    // TAILQ_HEAD (${table}Head, $table) rows;
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

#
# cmdBodyGetSource - chunk of the code that we run subst over to generate
#  part of the body of the code that handles the "get" method
#
set cmdBodyGetSource {
      case OPT_GET: $leftCurly
        int i;
	int fieldIndex;

	if (objc < 3) {
	    Tcl_WrongNumArgs (interp, 2, objv, "key ?field...?");
	    return TCL_ERROR;
	}

	hashEntry = Tcl_FindHashEntry (tbl_ptr->keyTablePtr, Tcl_GetString (objv[2]));

	if (hashEntry == NULL) {
	    return TCL_OK;
	}
	$pointer = (struct $table *) Tcl_GetHashValue (hashEntry);

	if (objc == 3) {
	    return ${table}_genlist (interp, $pointer);
	}

	for (i = 3; i < objc; i++) $leftCurly
            if (Tcl_GetIndexFromObj (interp, objv[i], ${table}_fields, "field", TCL_EXACT, &fieldIndex) != TCL_OK) {
		return TCL_ERROR;
	    }

	    switch ((enum ${table}_fields) fieldIndex) $leftCurly
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

    lappend args name $name

    set fields($name) $args
    lappend fieldList $name
    lappend nonBooleans $name
}

#
# boolean - define a boolean field
#
proc boolean {name {default 0}} {
    variable booleans
    variable fields
    variable fieldList

    set fields($name) [list name $name type boolean default $default]
    lappend fieldList $name
    lappend booleans $name
}

#
# fixedstring - define a fixed-length string field
#
proc fixedstring {name length {default ""}} {
    deffield $name type fixedstring length $length default $default
}

#
# varstring - define a variable-length string field
#
proc varstring {name {default ""}} {
    deffield $name type string default $default
}

#
# char - define a single character field -- this should probably just be
#  fixedstring[1] but it's simpler.  shrug.
#
proc char {name {default " "}} {
    deffield $name type char default $default
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
    deffield $name type "wide" default $default
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
# tailq_head - define a queue head - will probably become hidden
#
proc tailq_head {name structname structtype} {
     deffield $name type tailq_head structname $structname structtype $structtype
}

#
# tailq_entry - define a queue entry - will probably become hidden
#
proc tailq_entry {name structname} {
    deffield $name type tailq_entry structname $structname
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
    emit [format "    %-13s %s;%s" $type $name $comment]
}

#
# gen_defaults_subr - gen code to set a row to default values
#
proc gen_defaults_subr {subr struct pointer} {
    variable table
    variable fields
    variable fieldList

    emit "void ${subr}(struct $struct *$pointer) {"

    foreach myfield $fieldList {
        catch {unset field}
	array set field $fields($myfield)

	switch $field(type) {
	    string {
	        emit "    $pointer->$myfield = NULL;"
	    }

	    fixedstring {
	        emit "    strncpy ($pointer->$myfield, \"$field(default)\", $field(length));"
	    }

	    mac {
	        emit "    strncpy ($pointer->$myfield, \"$field(default)\", $field(length));"
	    }

	    inet {
	        emit "    strncpy ($pointer->$myfield, \"$field(default)\", $field(length));"
	    }

	    char {
	        emit "    $pointer->$myfield = '[string index $field(default) 0]';"
	    }

	    tailq_entry {
	    }

	    tailq_head {
	    }

	    default {
	        emit "    $pointer->$myfield = $field(default);"
	    }
	}
    }

    emit "}"
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
	    string {
	        emit "    if ($pointer->$myfield != NULL) ckfree ($pointer->$myfield);"
	    }
	}
    }
    emit "    ckfree ((char *)$pointer);"

    emit "}"
    emit ""
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

    foreach myfield $nonBooleans {
        catch {unset field}
	array set field $fields($myfield)

	switch $field(type) {
	    string {
		putfield char "*$field(name)"
	    }

	    fixedstring {
		putfield char "$field(name)\[$field(length)]"
	    }

	    mac {
		putfield char "$field(name)[6]"
	    }

	    inet {
		putfield char "$field(name)[4]"
	    }

	    tailq_entry {
		putfield "TAILQ_ENTRY($field(structname))" $field(name)
	    }

	    tailq_head {
		putfield "TAILQ_HEAD($field(structname), $field(structtype))" $field(name)
	    }

	    default {
		putfield $field(type) $field(name)
	    }
	}
    }

    foreach name $booleans {
	putfield "unsigned int" "$name:1"
    }

    emit "};"
    emit ""
}

#
# emit_set_bool_field - emit code to set a boolean field
#
proc emit_set_bool_field {field pointer} {
    variable boolSetSource

    set optname "FIELD_[string toupper $field]"

    emit [subst -nobackslashes -nocommands $boolSetSource]
}

#
# emit_set_num_field - emit code to set a numeric field
#
proc emit_set_num_field {field pointer type} {
    variable numberSetSource

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

    set optname "FIELD_[string toupper $field]"

    emit [subst -nobackslashes -nocommands $numberSetSource]
}

#
# emit_set_varstring_field - emit code to set a variable-length string (char *)
#  field
#
proc emit_set_varstring_field {field pointer} {
    variable stringSetSource

    set optname "FIELD_[string toupper $field]"

    emit [subst -nobackslashes -nocommands $stringSetSource]
}

#
# emit_set_char_field - emit code to set a single char field
#
proc emit_set_char_field {field pointer} {
    variable charSetSource

    set optname "FIELD_[string toupper $field]"

    emit [subst -nobackslashes -nocommands $charSetSource]
}

#
# emit_set_fixedstring_field - emit code to set a fixedstring field
#
proc emit_set_fixedstring_field {field pointer length} {
    variable fixedstringSetSource

    set optname "FIELD_[string toupper $field]"

    emit [subst -nobackslashes -nocommands $fixedstringSetSource]
}

#
# emit_set_short_field - emit code to set a short integer field
#
proc emit_set_short_field {field pointer} {
    variable shortSetSource

    set optname "FIELD_[string toupper $field]"

    emit [subst -nobackslashes -nocommands $shortSetSource]
}

#
# emit_set_float_field - emit code to set a floating point field
#
proc emit_set_float_field {field pointer} {
    variable floatSetSource

    set optname "FIELD_[string toupper $field]"

    emit [subst -nobackslashes -nocommands $floatSetSource]
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
	    short {
		emit_set_short_field $myfield $pointer
	    }

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

	    float {
	        emit_set_float_field $myfield $pointer
	    }

	    string {
		emit_set_varstring_field $myfield $pointer
	    }

	    boolean {
	        emit_set_bool_field $myfield $pointer
	    }

	    char {
		emit_set_char_field $myfield $pointer
	    }

	    fixedstring {
		emit_set_fixedstring_field $myfield $pointer $field(length)
	    }

	    tailq_entry {
	    }

	    tailq_head {
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

    set pointer "${table}_ptr"

    set rowStructTable ${table}StructTable
    set rowStructHeadTable ${table}StructHeadTable
    set rowStruct $table

    gen_set_function $table $pointer

    emit [subst -nobackslashes -nocommands $cmdBodyHeader]

    emit [subst -nobackslashes -nocommands $cmdBodySource]
    emit "        break;"
    emit "      $rightCurly"
    emit ""

    emit [subst -nobackslashes -nocommands $cmdBodyGetSource]
    gen_gets
    emit "          $rightCurly"
    emit "        $rightCurly"
    emit "        break;"
    emit "      $rightCurly"

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

    switch $type {
	short {
	    return "Tcl_NewIntObj ($pointer->$fieldName)"
	}

	int {
	    return "Tcl_NewIntObj ($pointer->$fieldName)"
	}

	long {
	    return "Tcl_NewLongObj ($pointer->$fieldName)"
	}

	wide {
	    return "Tcl_NewWideIntObj ($pointer->$fieldName)"
	}

	double {
	    return "Tcl_NewDoubleObj ($pointer->$fieldName)"
	}

	float {
	    return "Tcl_NewDoubleObj ($pointer->$fieldName)"
	}

	boolean {
	    return "Tcl_NewBooleanObj ($pointer->$fieldName)"
	}

	string {
	    catch {unset field}
	    array set field $fields($fieldName)
	    #return "Tcl_NewStringObj ($pointer->$fieldName, -1)"
	    if {$field(default) == ""} {
	        set nullBody "Tcl_NewObj ()"
	    } else {
	        set nullBody "Tcl_NewStringObj (\"$field(default)\",[string length $field(default)])"
	    }
	    return "(($pointer->$fieldName == NULL) ? $nullBody : Tcl_NewStringObj ($pointer->$fieldName, -1))"
	}

	char {
	    return "Tcl_NewStringObj (&$pointer->$fieldName, 1)"
	}

	fixedstring {
	    catch {unset field}
	    array set field $fields($fieldName)
	    return "Tcl_NewStringObj ($pointer->$fieldName, $field(length))"
	}

	tailq_entry {
	}

	tailq_head {
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

	switch $field(type) {
	    default {
	        set_list_obj $position $field(type) $pointer $fieldName
	    }
	}

	incr position
    }

    emit "    Tcl_SetObjResult (interp, Tcl_NewListObj ($lengthDef, listObjv));"
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
	append fieldenum "\n    FIELD_[string toupper $myField],"
    }

    set fieldenum "[string range $fieldenum 0 end-1]\n$rightCurly;\n"
    emit $fieldenum

    emit ""
}

#
# gen_gets - generate code to fetch fields of a row, appending each requested
#  field as a Tcl object to Tcl's result object
#
proc gen_gets {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set pointer ${table}_ptr

    foreach myField $fieldList {
        catch {unset field}
	array set field $fields($myField)

	emit "              case FIELD_[string toupper $myField]: $leftCurly"
	emit "                if ([append_list_element $field(type) $pointer $myField] == TCL_ERROR) $leftCurly"
	emit "                    return TCL_ERROR;"
	emit "                $rightCurly"
	emit "                break;"
	emit "              $rightCurly"
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
}

#
# compile - compile and link the shared library
#
proc compile {fileFragName version} {
    cd build

    exec gcc -pipe -g -Wall -Wno-implicit-int -fno-common -c $fileFragName.c -o $fileFragName.o

    #exec gcc -pipe -g -dynamiclib  -Wall -Wno-implicit-int -fno-common  -Wl,-single_module -o ${fileFragName}${version}.dylib ${fileFragName}.o -L/System/Library/Frameworks/Tcl.framework/Versions/8.4 -ltclstub8.4 -ltcl

    exec gcc -pipe -g -dynamiclib  -Wall -Wno-implicit-int -fno-common  -Wl,-single_module -o ${fileFragName}${version}.dylib ${fileFragName}.o -L/sc/lib -ltclstub8.4g -ltcl8.4g

    cd ..
}

}

#
# CExtension - define a C extension
#
proc CExtension {name {version 1.0}} {
    file mkdir build
    set ::ctable::ofp [open build/$name.c w]
    ::ctable::gen_preamble
    set ::ctable::extension $name
    set ::ctable::extensionVersion $version
    set ::ctable::tables ""
}

proc EndExtension {} {
    ::ctable::put_init_extension_source [string totitle $::ctable::extension] $::ctable::extensionVersion

    foreach name $::ctable::tables {
	::ctable::put_init_command_source $name
    }

    ::ctable::emit "    return TCL_OK;"
    ::ctable::emit $::ctable::rightCurly

    close $::ctable::ofp

    ::ctable::compile $::ctable::extension $::ctable::extensionVersion
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

    ::ctable::gen_defaults_subr ${name}_init $name ${name}_ptr

    ::ctable::gen_delete_subr ${name}_delete $name ${name}_ptr

    ::ctable::gen_list

    ::ctable::gen_code

    ::ctable::put_metatable_source $name

}

