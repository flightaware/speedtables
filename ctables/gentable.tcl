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
    variable fields

    variable leftCurly
    variable rightCurly

    set leftCurly \173
    set rightCurly \175

    variable boolsetsource

set boolsetsource {
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

proc table {name} {
    variable table
    variable booleans
    variable fields

    set table $name

    set booleans ""
    set fields ""
}

proc end_table {} {
}

proc boolean {name {default 0}} {
    variable booleans

    lappend booleans $name $default
}

proc fixedstring {name length {default ""}} {
    variable fields

    lappend fields [list type fixedstring name $name length $length default $default]
}

proc varstring {name {default ""}} {
    variable fields

    lappend fields [list name $name type string default $default]
}

proc char {name {default ""}} {
    variable fields

    lappend fields [list name $name type char default $default]
}

proc mac {name {default 00:00:00:00:00:00}} {
    variable fields

    lappend fields [list name $name type mac default $default]
}

proc short {name {default 0}} {
    variable fields

    lappend fields [list name $name type short default $default]
}

proc int {name {default 0}} {
    variable fields

    lappend fields [list name $name type int default $default]
}

proc long {name {default 0}} {
    variable fields

    lappend fields [list name $name type long default $default]
}

proc ulong {name {default 0}} {
    variable fields

    lappend fields [list name $name type "unsigned long" default $default]
}

proc real {name {default 0.0}} {
    variable fields

    lappend fields [list name $name type real default $default]
}

proc double {name {default 0.0}} {
    variable fields

    lappend fields [list name $name type double default $default]
}

proc inet {name {default 0.0.0.0}} {
    variable fields

    lappend fields [list name $name type inet default $default]
}

proc tailq_head {name structname structtype} {
    variable fields

    lappend fields [list name $name type tailq_head structname $structname structtype $structtype]
}

proc tailq_entry {name structname} {
    variable fields

    lappend fields [list name $name type tailq_entry structname $structname]
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
    variable fields

    set fp stdout

    puts $fp "struct $table {"

    foreach myfield $fields {
        catch {unset field}
	array set field $myfield

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

    foreach "name default" $booleans {
	putfield "unsigned int" "$name:1"
    }

    puts $fp "};"
    puts $fp ""
}

proc putboolopt {field pointer} {
    variable boolsetsource

    set optname "OPT_[string toupper $field]"

    puts [subst -nobackslashes -nocommands $boolsetsource]
}


proc gencode {} {
    variable table
    variable booleans
    variable fields
    variable leftCurly
    variable rightCurly

    set fp stdout

    puts $fp "int ${table}ObjCmd (ClientData cData, Tcl_Interp *interp, int objc, Tcl_Obj *CONST objv[])\n$leftCurly"

    puts $fp "    struct $table *${table}_ptr = (struct $table *)cData;"
    puts $fp "    int optIndex;"

    puts $fp "    static CONST char *options[] = $leftCurly"
    foreach myfield $fields {
        catch {unset field}
	array set field $myfield

	puts "    \"$field(name)\","
    
    }

    foreach "boolean default" $booleans {
	puts "    \"$boolean\","
    }
    puts $fp "    (char *)NULL"
    puts $fp "$rightCurly;\n"

    set options "enum options $leftCurly"
    foreach myfield $fields {
        catch {unset field}
	array set field $myfield

	append options "\n    OPT_[string toupper $field(name)],"
    
    }

    foreach "bool default" $booleans {
	append options "\n    OPT_[string toupper $bool],"
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

    foreach "name default" $booleans {
        putboolopt $name ${table}_ptr
    }

    foreach myfield $fields {
    }

    puts $fp "$rightCurly"
    puts $fp ""
}

}

proc CTable {name data} {
::ctable::table $name
namespace eval ::ctable $data

::ctable::genstruct
::ctable::gencode
}

CTable fa_position {
    ulong timestamp
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

