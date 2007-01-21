#
# very simple client/server tests
#
# this one checks results of search and search+ to match expected or not
#
# $Id$
#

set expectKey(0) jonas_jr
set expect(jonas_jr) [list id jonas_jr name {Doctor Jonas Venture Junior} home {Spider Skull Island} show {Venture Bros} dad jonas alive 1 gender male age 45 coolness 120]

set expectKey(1) mom
set expect(mom) [list id mom name Mom home {} show {The Brak Show} dad {} alive 1 gender female age 41 coolness 101]

set expectKey(2) brock
set expect(brock) [list id brock name {Brock Sampson} home {Venture Compound} show {Venture Bros} dad {} alive 1 gender male age 35 coolness 100]

set expectKey(3) rick
set expect(rick) [list id rick name {Coroner Rock} home {} show {Stroker and Hoop} dad {} alive 1 gender male age 51 coolness 99]

set expectKey(4) doctor_girlfriend
set expect(doctor_girlfriend) [list id doctor_girlfriend name {Doctor Girlfriend} home {The Cocoon} show {Venture Bros} dad {} alive 1 gender female age 30 coolness 80]

package require ctable_client

remote_ctable ctable://127.0.0.1/dumbData t

# use to test redirect
#remote_ctable ctable://127.0.0.1:11112/dumbData t

puts "search of t in descending coolness limit 5 / code body..."
set i 0
t search -sort -coolness -limit 5 -key key -array_get_with_nulls data -code {
    if {$key != $expectKey($i)} {
	error "got key '$key' expected '$expectKey($i)'"
    }

    if {$data != $expect($key)} {
	error "got data of '$data' expected '$expect($key)'"
    }

    incr i
}
puts "OK"

puts "search of t in descending coolness limit 5 / -fields {id name show} / code body..."
set i 0
t search -sort -coolness -limit 5 -fields {id name show} -key key -array_get_with_nulls data -code {
puts $data
    if {$key != $expectKey($i)} {
	error "got key '$key' expected '$expectKey($i)'"
    }

if 0 {
    if {$data != $expect($key)} {
	error "got data of '$data' expected '$expect($key)'"
    }
}

    incr i
}
puts "OK"

puts "search+ of t in descending coolness limit 5 / code body..."
t index create show

set i 0
t search -sort -coolness -limit 5 -key key -array_get_with_nulls data -code {
    if {$key != $expectKey($i)} {
	error "got key '$key' expected '$expectKey($i)'"
    }

    if {$data != $expect($key)} {
	error "got data of '$data' expected '$expect($key)'"
    }

    incr i
}
puts "OK"

