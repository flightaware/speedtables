#
# CTables - code to generate Tcl C extensions that implement tables out of
# C structures
#
#
# $Id$
#

namespace eval ctable {
    variable table
    variable booleans
    variable nonBooleans
    variable fields
    variable fieldList

    variable leftCurly
    variable rightCurly

    set leftCurly \173
    set rightCurly \175

set boolSetSource {
	      case $optname: {
	        int boolean;

	        if (Tcl_GetBooleanFromObj (interp, objv[i+1], &boolean) == TCL_ERROR) {
	            Tcl_AppendResult (interp, " while converting $field", NULL);
	            return TCL_ERROR;
	        }

	        $pointer->$field = boolean;
	        break;
	      }
}

set numberSetSource {
	      case $optname: {
		if ($getObjCmd (interp, objv[i+1], &$pointer->$field) == TCL_ERROR) {
		    Tcl_AppendResult (interp, " while converting $field", NULL);
		    return TCL_ERROR;
		}
		break;
	      }
}

set floatSetSource {
	      case $optname: {
		double value;

		if (Tcl_GetDoubleFromObj (interp, objv[i+1], &value) == TCL_ERROR) {
		    Tcl_AppendResult (interp, " while converting $field", NULL);
		    return TCL_ERROR;
		}

		$pointer->$field = (float)value;
		break;
	      }
}

set shortSetSource {
	      case $optname: {
		int value;

		if (Tcl_GetIntFromObj (interp, objv[i+1], &value) == TCL_ERROR) {
		    Tcl_AppendResult (interp, " while converting $field", NULL);
		    return TCL_ERROR;
		}

		$pointer->$field = (short)value;
		break;
	      }
}

set stringSetSource {
	      case $optname: {
		char *string;
		int   length;

		if ($pointer->$field != NULL) {
		    ckfree ($pointer->$field);
		}

		string = Tcl_GetStringFromObj (objv[i+1], &length);
		$pointer->$field = ckalloc (length + 1);
		strncpy ($pointer->$field, string, length + 1);
		break;
	      }
}

set cmdBodyHeader {
int ${table}ObjCmd (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])
$leftCurly
    struct $table *$pointer = (struct $table *)cData;
    int optIndex;

    static CONST char *options[] = {"get", "set", (char *)NULL};

    enum options {OPT_GET, OPT_SET};

}

set cmdBodySource {

    if (objc == 1) {
        Tcl_WrongNumArgs (interp, 1, objv, "option ?args?");
	return TCL_ERROR;
    }

    if (Tcl_GetIndexFromObj (interp, objv[1], options, "option", TCL_EXACT, &optIndex) != TCL_OK) {
        return TCL_ERROR;
    }

    switch ((enum options) optIndex) $leftCurly
      case OPT_SET: $leftCurly
        int i;
	int fieldIndex;

	if ((objc < 4) || (objc % 2)) {
	    Tcl_WrongNumArgs (interp, 2, objv, "field value ?field value...?");
	    return TCL_ERROR;
	}

	for (i = 2; i < objc; i += 2) $leftCurly
            if (Tcl_GetIndexFromObj (interp, objv[i], fields, "field", TCL_EXACT, &fieldIndex) != TCL_OK) {
		return TCL_ERROR;
	    }

	    switch ((enum fields) fieldIndex) $leftCurly
}

set cmdBodyGetSource {
      case OPT_GET: $leftCurly
        int i;
	int fieldIndex;

	if (objc < 3) {
	    Tcl_WrongNumArgs (interp, 2, objv, "field ?field...?");
	    return TCL_ERROR;
	}

	for (i = 2; i < objc; i++) $leftCurly
            if (Tcl_GetIndexFromObj (interp, objv[i], fields, "field", TCL_EXACT, &fieldIndex) != TCL_OK) {
		return TCL_ERROR;
	    }

	    switch ((enum fields) fieldIndex) $leftCurly
}

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

proc end_table {} {
}

proc deffield {name args} {
    variable fields
    variable fieldList
    variable nonBooleans

    lappend args name $name

    set fields($name) $args
    lappend fieldList $name
    lappend nonBooleans $name
}

proc boolean {name {default 0}} {
    variable booleans
    variable fields
    variable fieldList

    lappend args name $name type boolean

    set fields($name) $args
    lappend fieldList $name
    lappend booleans $name
}

proc fixedstring {name length {default ""}} {
    deffield $name type fixedstring length $length default $default
}

proc varstring {name {default ""}} {
    deffield $name type string default $default
}

proc char {name {default ""}} {
    deffield $name type char default $default
}

proc mac {name {default 00:00:00:00:00:00}} {
    deffield $name type mac default $default
}

proc short {name {default 0}} {
    deffield $name type short default $default
}

proc int {name {default 0}} {
    deffield $name type int default $default
}

proc long {name {default 0}} {
    deffield $name type long default $default
}

proc wide {name {default 0}} {
    deffield $name type "wide" default $default
}

proc float {name {default 0.0}} {
    deffield $name type float default $default
}

proc double {name {default 0.0}} {
    deffield $name type double default $default
}

proc inet {name {default 0.0.0.0}} {
    deffield $name type inet default $default
}

proc tailq_head {name structname structtype} {
     deffield $name type tailq_head structname $structname structtype $structtype
}

proc tailq_entry {name structname} {
    deffield $name type tailq_entry structname $structname
}

proc putfield {type name {comment ""}} {
    if {[string index $name 0] != "*"} {
        set name " $name"
    }

    if {$comment != ""} {
        set comment " /* $comment */"
    }
    puts stdout [format "    %-13s %s;%s" $type $name $comment]
}

proc gen_struct {} {
    variable table
    variable booleans
    variable nonBooleans
    variable fields
    variable fieldList

    set fp stdout

    puts $fp "struct $table {"

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

    puts $fp "};"
    puts $fp ""
}

proc put_bool_field {field pointer} {
    variable boolSetSource

    set optname "FIELD_[string toupper $field]"

    puts [subst -nobackslashes -nocommands $boolSetSource]
}

proc put_num_field {field pointer type} {
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

    puts [subst -nobackslashes -nocommands $numberSetSource]
}

proc put_varstring_field {field pointer} {
    variable stringSetSource

    set optname "FIELD_[string toupper $field]"

    puts [subst -nobackslashes -nocommands $stringSetSource]
}

proc put_short_field {field pointer} {
    variable shortSetSource

    set optname "FIELD_[string toupper $field]"

    puts [subst -nobackslashes -nocommands $shortSetSource]
}

proc put_float_field {field pointer} {
    variable floatSetSource

    set optname "FIELD_[string toupper $field]"

    puts [subst -nobackslashes -nocommands $floatSetSource]
}

proc gen_sets {pointer} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly
    variable cmdBodyHeader
    variable cmdBodySource

    foreach myfield $fieldList {
        catch {unset field}
	array set field $fields($myfield)

	switch $field(type) {
	    short {
		put_short_field $myfield $pointer
	    }

	    int {
		put_num_field $myfield $pointer int
	    }

	    long {
		put_num_field $myfield $pointer long
	    }

	    wide {
		put_num_field $myfield $pointer wide
	    }

	    double {
		put_num_field $myfield $pointer double
	    }

	    float {
	        put_float_field $myfield $pointer
	    }

	    string {
		put_varstring_field $myfield $pointer
	    }

	    boolean {
	        put_bool_field $myfield $pointer
	    }
	}
    }
}

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

    set fp stdout

    set pointer "${table}_ptr"

    puts [subst -nobackslashes -nocommands $cmdBodyHeader]

    gen_field_names

    puts [subst -nobackslashes -nocommands $cmdBodySource]
    gen_sets $pointer
    puts $fp "          $rightCurly"
    puts $fp "        $rightCurly"
    puts $fp "      $rightCurly"
    puts $fp ""

    puts [subst -nobackslashes -nocommands $cmdBodyGetSource]
    gen_gets
    puts $fp "          $rightCurly"
    puts $fp "        $rightCurly"
    puts $fp "      $rightCurly"

    # finish out the command switch and the command itself
    puts $fp "    $rightCurly"
    puts $fp "$rightCurly"
}

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
	    return "Tcl_NewStringObj ($pointer->$fieldName, -1)"
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

proc set_list_obj {position type pointer field} {
    puts "    listObjv\[$position] = [gen_new_obj $type $pointer $field];"
}

proc append_list_element {type pointer field} {
    return "Tcl_ListObjAppendElement (interp, Tcl_GetObjResult (interp), [gen_new_obj $type $pointer $field])"
}

proc gen_list {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set pointer ${table}_ptr

    puts "INCOMPLETE LIST CODE"
    puts ""
    set length [llength $fieldList]

    puts "    Tcl_Obj *listObjv\[$length];"
    puts ""

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

    puts "    Tcl_SetObjResult (interp, Tcl_NewListObj ($length, listObjv));"
}

proc gen_field_names {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set fp stdout

    puts $fp "    static CONST char *fields\[] = $leftCurly"
    foreach myfield $fieldList {
	puts "        \"$myfield\","
    
    }
    puts $fp "        (char *)NULL"
    puts $fp "    $rightCurly;\n"

    set fieldenum "enum fields $leftCurly"
    foreach myField $fieldList {
	append fieldenum "\n    FIELD_[string toupper $myField],"
    }

    set fieldenum "[string range $fieldenum 0 end-1]\n$rightCurly;\n"
    puts $fp $fieldenum

    puts $fp ""
}


proc gen_gets {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set pointer ${table}_ptr

    set fp stdout

    foreach myField $fieldList {
        catch {unset field}
	array set field $fields($myField)

	puts $fp "              case FIELD_[string toupper $myField]: $leftCurly"
	puts $fp "                if ([append_list_element $field(type) $pointer $myField] == TCL_ERROR) $leftCurly"
	puts $fp "                    return TCL_ERROR;"
	puts $fp "                $rightCurly"
	puts $fp "                break;"
	puts $fp "              $rightCurly"
	puts $fp ""
    }
}

proc gen_preamble {} {
    puts stdout "/* autogenerated [clock format [clock seconds]] */"
    puts stdout ""
    puts stdout "#include <tcl.h>"
    puts stdout "#include <string.h>"
    puts stdout "#include \"queue.h\""
    puts stdout ""
}

}

proc CTable {name data} {
    ::ctable::table $name
    namespace eval ::ctable $data

    ::ctable::gen_struct
    ::ctable::gen_code

    #::ctable::gen_list
}

::ctable::gen_preamble

CTable fa_position {
    long timestamp
    short latitude
    short longitude
    short groundspeed
    short altitude
    char altitudeStatus
    char updateType
    char altitudeChange
    fixedstring subident 4
    fixedstring facility 3
    tailq_entry position_link fa_position
    double testDouble
    float testFloat
}

CTable fa_trackstream {
    tailq_head positions positionhead fa_position
    boolean inAir
    boolean debug
    boolean blocked
    boolean trackArchived

    varstring name
    varstring prefix
    varstring type
    varstring suffix
    varstring origin
    varstring destination

    long departureTime
    long arrivalTime
    long oldestTimeSeen
    long newestTimeSeen
    long newestTimeSaved

    short lowLatitude
    short lowLongitude
    short highLatitude
    short highLongitude
}

