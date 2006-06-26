#
#
#
#
#
#

namespace eval ctable {
    variable table
    variable booleans
    variable fields

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

proc string {name {default ""}} {
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
    if {[::string index $name 0] != "*"} {
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

    foreach "name default" $booleans {
        putfield "unsigned int" "$name:1"
    }

    foreach myfield $fields {
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

    puts $fp "};"
    puts $fp ""
}

}

proc CTable {name data} {
    ::ctable::table $name
    namespace eval ::ctable $data

    ::ctable::genstruct
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

    string name
    string prefix
    string type
    string suffix
    string origin
    string destination

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

