#
# incr test - test ctable "incr" method
#
# $Id$
#

source searchtest-def.tcl

source dumb-data.tcl

#package require Tclx
#cmdtrace on

puts -nonewline "incr test 1..."
if {[catch {t incr brock} result] == 1} {
    error "t incr brocks should not have been an error"
} else {
    if {$result != ""} {
        error "t incr brock should have returned an empty result"
    }
}
puts "ok"

puts -nonewline "incr test 2..."
if {[t incr brock age 1 coolness 10] != [list 36 110]} {
    error "t incr brock age 1 coolness 10 failed"
}
puts "ok"

puts -nonewline "incr test 3..."
if {[catch {t incr brock foo} result] == 1} {
    if {$result == "key-value list must contain an even number of elements"} {
    } else {
	puts $result
    }
} else {
    error "should have gotten an error"
}
puts "ok"

puts -nonewline "incr test 4..."
if {[t incr inignot age 2] != 4} {
    error "t incr inignot age 2 failed"
}
puts "ok"

puts -nonewline "incr test 5..."
if {[catch {t incr frammistan foo 1} result] == 1} {
    # Remove reserved field names from result
    regsub -all ", or " $result ", " result
    regsub -all ", _\[a-z]+" $result "" result
    if {$result == {bad field "foo": must be id, name, home, show, dad, alive, gender, age, coolness}} {
    } else {
	error "got '$result' doing t incr frammistan foo 1"
    }
} else {
    error "should have gotten an error"
}
puts "ok"

