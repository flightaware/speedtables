#

package require ctable

CExtension Objecttest 1.0 {

CTable objtable {
    tclobj value
    varstring copy
}

}

package require Objecttest

objtable create o

set in [list [expr "-23.21"] [expr "-91.14"] [expr "23.31"]]
o set k1 value $in copy $in

set out [o get k1 value]

if {"$out" != "[list $in]"} {
	error "Expected [list $in] got $out"
}

set out [o get k1 copy]

if {"$out" != "[list $in]"} {
	error "Expected [list $in] got $out"
}

# puts [o array_get k1]
