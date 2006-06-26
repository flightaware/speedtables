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

    variable boolsetsource

set boolSetSource {
	case $optname: {
	    int boolean;

	    if ((objc < 2) || (objc > 3)) {
	        Tcl_WrongNumArgs (interp, 2, objv, "?boolean?");
		return TCL_ERROR;
	    }

	    if (objc == 2) {
	        Tcl_SetObjResult (interp, Tcl_NewBooleanObj ($pointer->$field));
		return TCL_OK;
	    }

	    if (Tcl_GetBooleanFromObj (interp, objv[2], &boolean) == TCL_ERROR) {
	        return TCL_ERROR;
	    }

	    $pointer->$field = boolean;
	    return TCL_OK;
	}
}

set numberSetSource {
	case $optname: {
	    if ((objc < 2) || (objc > 3)) {
	        Tcl_WrongNumArgs (interp, 2, objv, "?$typeText?");
		return TCL_ERROR;
	    }

	    if (objc == 2) {
	        Tcl_SetObjResult (interp, $newObjCmd ($pointer->$field));
		return TCL_OK;
	    }

	    if ($getObjCmd (interp, objv[2], &$pointer->$field) == TCL_ERROR) {
	        return TCL_ERROR;
	    }

	    return TCL_OK;
	}
}

set realSetSource {
	case $optname: {
	    double value;

	    if ((objc < 2) || (objc > 3)) {
	        Tcl_WrongNumArgs (interp, 2, objv, "?real?");
		return TCL_ERROR;
	    }

	    if (objc == 2) {
	        Tcl_SetObjResult (interp, Tcl_NewDoubleObj ($pointer->$field));
		return TCL_OK;
	    }

	    if (Tcl_GetDoubleFromObj (interp, objv[2], &value) == TCL_ERROR) {
	        return TCL_ERROR;
	    }

	    $pointer->$field = (real)value;

	    return TCL_OK;
	}
}

set shortSetSource {
	case $optname: {
	    int value;

	    if ((objc < 2) || (objc > 3)) {
	        Tcl_WrongNumArgs (interp, 2, objv, "?short?");
		return TCL_ERROR;
	    }

	    if (objc == 2) {
	        Tcl_SetObjResult (interp, Tcl_NewIntObj ($pointer->$field));
		return TCL_OK;
	    }

	    if (Tcl_GetIntFromObj (interp, objv[2], &value) == TCL_ERROR) {
	        return TCL_ERROR;
	    }

	    $pointer->$field = (short)value;

	    return TCL_OK;
	}
}


set stringSetSource {
        char *string;
	int   length;

	case $optname: {
	    if ((objc < 2) || (objc > 3)) {
	        Tcl_WrongNumArgs (interp, 2, objv, "?string?");
		return TCL_ERROR;
	    }

	    if (objc == 2) {
	        Tcl_SetObjResult (interp, Tcl_NewStringObj ($pointer->$field, -1));
		return TCL_OK;
	    }

	    if ($pointer->$field != NULL) {
	        ckfree ($pointer->$field);
	    }

	    string = Tcl_GetStringFromObj (objv[2], length);
	    $pointer->$field = ckalloc (length + 1);
	    strncpy ($pointer->$field, string, length + 1);
	    return TCL_OK;
	}
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

proc real {name {default 0.0}} {
    deffield $name type real default $default
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

proc genstruct {} {
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

proc put_bool_opt {field pointer} {
    variable boolSetSource

    set optname "OPT_[string toupper $field]"

    puts [subst -nobackslashes -nocommands $boolSetSource]
}

proc put_num_opt {field pointer type} {
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
    }

    set optname "OPT_[string toupper $field]"

    puts [subst -nobackslashes -nocommands $numberSetSource]
}

proc put_varstring_opt {field pointer} {
    variable stringSetSource

    set optname "OPT_[string toupper $field]"

    puts [subst -nobackslashes -nocommands $stringSetSource]
}

proc put_short_opt {field pointer} {
    variable shortSetSource

    set optname "OPT_[string toupper $field]"

    puts [subst -nobackslashes -nocommands $shortSetSource]
}

proc put_real_opt {field pointer} {
    variable realSetSource

    set optname "OPT_[string toupper $field]"

    puts [subst -nobackslashes -nocommands $realSetSource]
}

proc gencode {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set fp stdout

    set pointer "${table}_ptr"

    puts $fp "int ${table}ObjCmd (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])\n$leftCurly"

    puts $fp "    struct $table *$pointer = (struct $table *)cData;"
    puts $fp "    int optIndex;"

    puts $fp "    static CONST char *options[] = $leftCurly"
    foreach myfield $fieldList {
	puts "    \"$myfield\","
    
    }
    puts $fp "    (char *)NULL"
    puts $fp "$rightCurly;\n"

    set options "enum options $leftCurly"
    foreach myField $fieldList {
	append options "\n    OPT_[string toupper $myField],"
    }

    set options "[string range $options 0 end-1]\n$rightCurly;\n"
    puts $fp $options

    puts $fp "    if (objc == 1) $leftCurly"
    puts $fp "        Tcl_WrongNumArgs (interp, 1, objv, \"option ?args?\");"
    puts $fp "        return TCL_ERROR;"
    puts $fp "    $rightCurly"
    puts $fp ""

    puts $fp "    if (Tcl_GetIndexFromObj (interp, objv\[1\], options, \"option\", TCL_EXACT, &optIndex) != TCL_OK) $leftCurly"
    puts $fp "        return TCL_ERROR;"
    puts $fp "    $rightCurly"
    puts $fp ""

    puts $fp "    switch ((enum options) optIndex) $leftCurly"

    foreach myfield $fieldList {
        catch {unset field}
	array set field $fields($myfield)

	switch $field(type) {
	    short {
		put_short_opt $myfield $pointer
	    }

	    int {
		put_num_opt $myfield $pointer int
	    }

	    long {
		put_num_opt $myfield $pointer long
	    }

	    wide {
		put_num_opt $myfield $pointer wide
	    }

	    double {
		put_num_opt $myfield $pointer double
	    }

	    real {
	        put_real_opt $myfield $pointer
	    }

	    string {
		put_varstring_opt $myfield $pointer
	    }

	    boolean {
	        put_bool_opt $myfield $pointer
	    }
	}
    }

    puts $fp "$rightCurly"
    puts $fp ""
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

	real {
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
	    return "Tcl_NewStringObj (&$pointer->$fieldName, $field(length))"
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

proc genlist {} {
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

proc genpickedlist {} {
    variable table
    variable booleans
    variable fields
    variable fieldList
    variable leftCurly
    variable rightCurly

    set pointer ${table}_ptr

    set fp stdout

    puts $fp "INCOMPLETE GEN PICKED CODE"

    puts $fp "    int fieldIndex;"

    puts $fp "    static CONST char *fields[] = $leftCurly"
    foreach myfield $fieldList {
	puts "    \"$myfield\","
    
    }
    puts $fp "    (char *)NULL"
    puts $fp "$rightCurly;\n"

    set fieldenum "enum fields $leftCurly"
    foreach myField $fieldList {
	append fieldenum "\n    FIELD_[string toupper $myField],"
    }

    set fieldenum "[string range $fieldenum 0 end-1]\n$rightCurly;\n"
    puts $fp $fieldenum

    puts $fp "    if (fieldc == 1) $leftCurly"
    puts $fp "        Tcl_WrongNumArgs (interp, 1, fieldv, \"field ?field...?\");"
    puts $fp "        return TCL_ERROR;"
    puts $fp "    $rightCurly"
    puts $fp ""

    puts $fp "    for (field = 1; field < fieldc; field++) $leftCurly"

    puts $fp "        if (Tcl_GetIndexFromObj (interp, fieldv\[field\], fields, \"field\", TCL_EXACT, &fieldIndex) != TCL_OK) $leftCurly"
    puts $fp "            return TCL_ERROR;"
    puts $fp "        $rightCurly"
    puts $fp ""

    puts $fp "    switch ((enum fields) fieldIndex) $leftCurly"

    foreach myField $fieldList {
        catch {unset field}
	array set field $fields($myField)

	puts $fp "        case FIELD_[string toupper $myField]: $leftCurly"
	puts $fp "            if ([append_list_element $field(type) $pointer $myField]) == TCL_ERROR) $leftCurly"
	puts $fp "                return TCL_ERROR;"
	puts $fp "            $rightCurly"
	puts $fp "            break;"
	puts $fp "        $rightCurly"
	puts $fp ""
    }

    puts $fp "    $rightCurly"

}


}

proc CTable {name data} {
::ctable::table $name
namespace eval ::ctable $data

::ctable::genstruct
::ctable::gencode
::ctable::genlist
::ctable::genpickedlist
}

CTable fa_position {
    long timestamp
    short latitude
    short longitude
    short groundspeed
    short altitude
    char altitudeStatus
    char updateType
    char altitudeChange
    fixedstring subident FA_SUBIDENT_SIZE
    fixedstring facility FA_FACILITY_SIZE
    tailq_entry position_link fa_position
    double testDouble
    real testReal
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

