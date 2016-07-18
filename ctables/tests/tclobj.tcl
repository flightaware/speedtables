#

source test_common.tcl

CExtension Objecttest 1.0 {

CTable objtable {
    tclobj value
    varstring copy
}

}

package require Objecttest

objtable create o

for {set i 0} {$i < 4} {incr i} {
	set a($i) [expr {rand() * 10}]
}
for {set n 0} {$n < 100} {incr n} {
	set in {}
	for {set i 0} {$i < 4} {incr i} {
		set a($i) [expr {$a($i) + rand() * 2 - 1}]
		lappend in $a($i)
	}

	o set $n value $in copy $in

	set out [o get $n value]

	if {"$out" != "[list $in]"} {
		error "Expected value [list $in] got $out in pass $n"
	}

	set out [o get $n copy]

	if {"$out" != "[list $in]"} {
		error "Expected value [list $in] got $out in pass $n"
	}
}

# for {set n 0} {$n < 100} {incr n} {
# 	puts [o array_get $n]
# }
