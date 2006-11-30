

source dumb-data.tcl

proc search_test {name searchFields expect} {
    puts "running $name"
    set result ""
    set cmd [linsert $searchFields 0 t search -key key -get data -fields "" -code {lappend result $key}]
    #puts $cmd
    eval $cmd

    if {$result != $expect} {
	puts "error in test: $name"
	puts "got '$result', expected '$expect'"
	puts ""
    } else {
	puts "IT WORKED"
    }
}

search_test "case-insensitive match" {-compare {{match name *VENTURE*}}} {dean hank jonas jonas_jr rusty}

search_test "case-sensitive match" {-compare {{match_case name *VENTURE*}}} {}

search_test "case-sensitive match 2" {-compare {{match_case name *Tri*}}} {triana}

search_test "numeric expression" {-compare {{< age 10}}} {carr frylock meatwad shake inignot thundercleese ur}


search_test "sort ascending" {-sort age -compare {{< age 10}}} {ur carr inignot shake frylock meatwad thundercleese}

search_test "sort descending" {-sort -age -compare {{< age 10}}} {thundercleese frylock meatwad shake inignot carr ur}

search_test "unanchored match" {-sort name -compare {{match name *Doctor*}}} {doctor_girlfriend jonas jonas_jr orpheus}

search_test "anchored match" {-sort name -compare {{match name Doctor*}}} {doctor_girlfriend jonas jonas_jr orpheus}


