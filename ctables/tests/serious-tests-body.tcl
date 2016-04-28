#
# some tests that actually check their results
#
# $Id$
#

proc search_test {name searchFields expect} {
    puts -nonewline "running $name..."; flush stdout
    set result ""
    set cmd [linsert $searchFields 0 t search -key key -get data -fields "" -code {lappend result $key}]
    #puts $cmd
    eval $cmd

    if {$result != $expect} {
	puts "ERROR IN TEST: $name"
	puts "got '$result'"
	puts "expected '$expect'"
	puts "command '$cmd'"
	error "ERROR IN TEST: $name"
    } else {
	puts "ok"
    }
}

proc search_test_get {name searchFields expect} {
    puts -nonewline "running $name..."; flush stdout
    set result ""
    set cmd [linsert $searchFields 0 t search -key key -get data -fields "age coolness" -code {lappend result $data}]
    #puts $cmd
    eval $cmd

    if {$result != $expect} {
	puts "ERROR IN TEST: $name"
	puts "got '$result'"
	puts "expected '$expect'"
	puts "command '$cmd'"
	error "ERROR IN TEST: $name"
    } else {
	puts "ok"
    }
}

proc search_test_countonly {name searchFields expect} {
    puts -nonewline "running $name..."; flush stdout
    set cmd [linsert $searchFields 0 t search -countOnly 1]
    #puts $cmd
    set result [eval $cmd]

    if {$result != $expect} {
	puts "ERROR IN TEST: $name"
	puts "got '$result'"
	puts "expected '$expect'"
	puts "command '$cmd'"
	error "ERROR IN TEST: $name"
    } else {
	puts "ok"
    }

    puts -nonewline "running '$name' without -countOnly..."; flush stdout
    set cmd [linsert $searchFields 0 t search]

    set result [eval $cmd]
        
    if {$result != $expect} {
        puts "ERROR IN TEST: $name"
        puts "got '$result'"
        puts "expected '$expect'"
        puts "command '$cmd'"
	error "ERROR IN TEST: $name"
    } else {
        puts "ok"
    }
}


proc search_unsorted_test {name searchFields expect} {
    puts -nonewline "running $name..."; flush stdout
    set result ""
    set cmd [linsert $searchFields 0 t search -key key -get data -fields "" -code {lappend result $key}]
    #puts $cmd
    eval $cmd

    if {"[lsort $result]" != "[lsort $expect]"} {
	puts "ERROR IN TEST: $name"
	puts "got '$result'"
	puts "expected '$expect'"
	puts "command '$cmd'"
	error "ERROR IN TEST: $name"
    } else {
	puts "ok"
    }
}

proc search+_test {name searchFields expect} {
    puts -nonewline "running search+ test $name..."; flush stdout
    set result ""
    set cmd [linsert $searchFields 0 t search+ -get data -fields id -code {lappend result $data}]
    #puts $cmd
    eval $cmd

    if {[lsort $result] != [lsort $expect]} {
	puts "ERROR IN TEST: $name"
	puts "got '$result'"
	puts "expected '$expect'"
	puts "command '$cmd'"
	error "ERROR IN TEST: $name"
    } else {
	puts "ok"
    }
}


search_unsorted_test "case-insensitive match" {-compare {{match name *VENTURE*}}} {jonas_jr rusty jonas dean hank}

search_unsorted_test "case-sensitive match" {-compare {{match_case name *VENTURE*}}} {}

search_unsorted_test "case-sensitive match 2" {-compare {{match_case name *Tri*}}} {triana}

search_unsorted_test "numeric expression, age < 10" {-compare {{< age 10}}} {carr thundercleese ur inignot frylock shake meatwad}

search_test "sort ascending by age, age < 10" {-sort age -compare {{< age 10}}} {ur inignot carr meatwad frylock shake thundercleese}

search_test "sort descending by age, age < 10" {-sort -age -compare {{< age 10}}} {thundercleese frylock shake meatwad inignot carr ur}

search_test "unanchored match" {-sort name -compare {{match name *Doctor*}}} {doctor_girlfriend jonas jonas_jr orpheus}

search_test "anchored match" {-sort name -compare {{match name Doctor*}}} {doctor_girlfriend jonas jonas_jr orpheus}


search_test "sorted search with limit" {-sort name -limit 10} {angel baron brak brock carr carl clarence rick dad dean}

search_test "sorted search with offset 0 and limit 10" {-sort name -offset 0 -limit 10} {angel baron brak brock carr carl clarence rick dad dean}

search_test "sorted search with offset 5 and limit 5" {-sort name -offset 5 -limit 5} {carl clarence rick dad dean}

search_unsorted_test "unsorted search with offset 5 and limit 10" {-offset 5 -limit 10} {clarence thundercleese mom zorak brak dad ur inignot carl frylock}

search_unsorted_test "unsorted search with offset 5 and limit 5" {-offset 5 -limit 5} {clarence thundercleese mom zorak brak}

search_test "search where alive is false" {-compare {{false alive}}} {jonas}

search_test "search where name is null" {-compare {{null name}}} {}

search_test_get "search with -get" {-compare {{> coolness 64}}} {{51 99} {41 101} {30 80} {45 120} {35 100}}

search_test "search where name is notnullnull" {-sort name -limit 5 -compare {{notnull name}}} {angel baron brak brock carr}

search_test "search where age > 40 sort by boolean alive and name" {-sort "-alive name" -compare {{> age 40}}} {jonas carl rick dad jonas_jr orpheus mom phantom_limb rusty}

search_test_countonly "search countOnly no compare" {} {31}

search_test_countonly "search countOnly no compare limit" {-limit 10} {10}

search_test_countonly "search countOnly no compare offset" {-offset 25} {6}

search_test_countonly "search countOnly compare" {-compare {{false alive}}} {1}

puts -nonewline "testing 'search' with negative offset..."
if {[catch {t search -sort -age -offset -10 -limit 10} result] == 1} {
    if {$result == "Search offset cannot be negative"} {
    } else {
	error "t search with negative offset got '$result'"
    }
} else {
    error "should have gotten an error"
}
puts "ok"

puts -nonewline "testing 'search' with negative limit..."
if {[catch {t search -sort -age -offset 0 -limit -10} result] == 1} {
    if {$result == "Search limit cannot be negative"} {
    } else {
	error "t search with negative limit got '$result'"
    }
} else {
    error "should have gotten an error"
}
puts "ok"

t index create name
# Note, this one won't actually use skiplists.
search+_test "indexed search 1" {} {angel baron brak brock carr carl clarence rick dad dean doctor_girlfriend jonas jonas_jr orpheus frylock hank hoop inignot stroker shake meatwad mom 21 28 phantom_limb rusty the_monarch thundercleese triana ur zorak}

if 0 { # the order depends on too many variables
search+_test "indexed search with offset and limit" {-offset 5 -limit 5} {carl clarence rick dad dean}
}

t index drop name
t index create show

# Note, this one won't actually use skiplists.
search+_test "indexed search 2" {} {meatwad shake frylock carl inignot ur stroker hoop angel carr rick dad brak zorak mom thundercleese clarence brock hank dean jonas orpheus triana rusty jonas_jr doctor_girlfriend the_monarch 21 28 phantom_limb baron}

search+_test "indexed range" {-compare {{range show A M}}} {meatwad shake frylock carl inignot ur}
t index create show

# not accelerated
search+_test "sorted search+ with offset 0 and limit 10" {-sort name -offset 0 -limit 10} {angel baron brak brock carr carl clarence rick dad dean}

search_unsorted_test "search >=" {-compare {{>= show M}}} {rick carr angel hoop stroker clarence thundercleese mom zorak brak dad baron phantom_limb 28 21 the_monarch doctor_girlfriend jonas_jr rusty triana orpheus jonas dean hank brock}

search+_test "search+ >=" {-compare {{>= show M}}} {rick carr angel hoop stroker clarence thundercleese mom zorak brak dad baron phantom_limb 28 21 the_monarch doctor_girlfriend jonas_jr rusty triana orpheus jonas dean hank brock}

search_unsorted_test "search <" {-compare {{< show M}}} {ur inignot carl frylock shake meatwad}

search+_test "search+ <" {-compare {{< show M}}} {ur inignot carl frylock shake meatwad}

search+_test "using 'in'" {-compare {{in show {"The Brak Show" "Stroker and Hoop"}}}} {dad brak zorak mom thundercleese clarence stroker hoop angel carr rick}

search_unsorted_test "using index and 'in'" {-index show -compare {{in show {"The Brak Show" "Stroker and Hoop"}}}} {dad brak zorak mom thundercleese clarence stroker hoop angel carr rick}

t index drop name
search_test "unindexed in" {-index name -compare {{in name {"Brock Sampson" "Hank Venture"}}}} {hank brock}

puts -nonewline "testing 'fields'..."
if {[t fields] != {id name home show dad alive gender age coolness}} {
   error "t fields expected to return {id name home show dad alive gender age coolness}\nbut got {[t fields]}"
}
puts "ok"

puts -nonewline "testing 'methods'..."
set methlab [
  list get set store incr array_get array_get_with_nulls exists delete count batch search search+ type import_postgres_result import_cassandra_future fields field fieldtype needs_quoting names reset destroy statistics read_tabsep write_tabsep index foreach key makekey methods attach getprop share null isnull verify performance_callback
]
set methods [t methods]
if {"$methods" != "$methlab"} {
    error "t methods expected to return [list $methlab]\n\treturned [list $methods]"
}
puts "ok"

puts -nonewline "testing 'getprop'..."
set proplist "type anim_characters extension animinfo key _key quote {none uri escape strict_uri strict_escape}"
set prop [t getprop]
if {"$prop" != "$proplist"} {
    error "t getprop expected to return [list $proplist]\n\nreturned [list $prop]"
}
foreach {n v} $proplist {
    set i [lindex [t getprop $n] 0]
    if {"$i" != "$v"} {
	error "t getprop \"$n\" expected to return '$v', returned '$i'"
    }
}
puts "ok"

puts -nonewline "testing 'getprop' with invalid property..."
if {[catch {t getprop rumplestiltskin} result] == 1} {
    if {$result == "Unknown property 'rumplestiltskin'."} {
    } else {
	error "t getprop rumplestiltskin got '$result'"
    }
} else {
    error "should have gotten an error"
}
puts "ok"

puts -nonewline "testing 'fields'..."
if {[t fields] != {id name home show dad alive gender age coolness}} {
    error "t fields expected to return {id name home show dad alive gender age coolness}\nbut got {[t fields]}"
}
puts "ok"

puts -nonewline "testing 'fields' with wrong # args..."
if {[catch {t fields bork} result] == 1} {
    if {$result == "wrong # args: should be \"t fields\""} {
    } else {
	error "t fields bork got '$result'"
    }
} else {
    error "should have gotten an error"
}
puts "ok"

puts -nonewline "testing 'field'..."
if {[catch {t field} result] == 1} {
    if {$result == "wrong # args: should be \"t field fieldName opt ?arg?\""} {
    } else {
        puts $result
    }
} else {
    error "should have gotten an error"
}

if {[catch {t field asdf} result] == 1} {
    if {$result == "wrong # args: should be \"t field fieldName opt ?arg?\""} {
    } else {
        puts $result
    }
} else {
    error "should have gotten an error"
}

if {[catch {t field alive} result] == 1} {
    if {$result == "wrong # args: should be \"t field fieldName opt ?arg?\""} {
    } else {
        puts $result
    }
} else {
    error "should have gotten an error"
}

if {[catch {t field alive asdf} result] == 1} {
    if {$result == "bad suboption \"asdf\": must be getprop, properties, or proplist"} {
    } else {
        puts $result
    }
} else {
    error "should have gotten an error"
}

if {[catch {t field alive proplist} result] == 1} {
    error "didn't expect an error - $result"
} else {
    if {$result != "default 1 name alive notnull 1 type boolean"} {
       error "didn't get intended result - got $result"
    }
}

if {[catch {t field alive properties} result] == 1} {
    error "didn't expect an error - $result"
} else {
    if {$result != "default name notnull type"} {
       error "didn't get intended result - got $result"
    }
}

if {[catch {t field alive getprop} result] == 1} {
    if {$result == "wrong # args: should be \"t field alive fieldName propName\""} {
    } else {
        puts $result
    }
} else {
    error "should have gotten an error"
}

if {[catch {t field alive getprop type} result] == 1} {
    error "didn't expect an error - $result"
} else {
    if {$result != "boolean"} {
       error "didn't get intended result - got $result"
    }
}

if {[catch {t field alive getprop default} result] == 1} {
    error "didn't expect an error - $result"
} else {
    if {$result != "1"} {
       error "didn't get intended result - got $result"
    }
}
puts "ok"

puts -nonewline "testing 'index unique'..."
if {[t index unique name] != 1} {
    error "'t index unique name' should have been 1"
}

if {[t index unique show] != 0} {
    error "'t index unique show' should have been 0"
}
puts "ok"

puts -nonewline "testing 'search with array get'..."
t search -compare {{= name {Brock Sampson}}} -array_get foo -code {
    set expect [list id brock name {Brock Sampson} home {Venture Compound} show {Venture Bros} alive 1 gender male age 35 coolness 100 _key brock]
    if {$foo != $expect} {
        error "got '$foo' , expected '$expect'"
    }
}
puts "ok"

puts -nonewline "testing 'search with array get with nulls'..."
t search -compare {{= name {Brock Sampson}}} -array_get_with_nulls foo -code {
    set expect [list id brock name {Brock Sampson} home {Venture Compound} show {Venture Bros} dad {} alive 1 gender male age 35 coolness 100 _key brock]
    if {$foo != $expect} {
        error "got '$foo' , expected '$expect'"
    }
}
puts "ok"

puts -nonewline "testing 'search with array get and limited fields'..."
t search -compare {{= name {Rusty Venture}}} -fields {name age} -array_get_with_nulls foo -code {
    set expect [list name {Rusty Venture} age 45]
    if {$foo != $expect} {
        error "got '$foo' , expected '$expect'"
    }
}
puts "ok"

puts -nonewline "testing 'search with -array'..."
unset -nocomplain foo
set foo(probe2) dummy
t search -compare {{= name {Brock Sampson}}} -array foo -fields {id dad} -code {
    if [info exists foo(probe)] {
	error "test array not cleared"
    }
    if {[array names foo] != [list id]} {
        error "expected only 'id' element in test array"
    }
    set foo(probe) dummy
}
puts "ok"

puts -nonewline "testing 'search with -array_with_nulls'..."
unset -nocomplain foo
t search -compare {{= name {Brock Sampson}}} -array_with_nulls foo -fields {id dad} -code {
    if {[lsort [array names foo]] != [list dad id]} {
        error "expected each and only 'id' and 'dad' elements in test array"
    }
}
puts "ok"

puts -nonewline "testing delete..."
if {[t delete dean] != 1} {
    error "t delete dean should have returned 1 the first time"
}

if {[t delete dean] != 0} {
    error "t delete dene should have returned 0 the second time"
}
puts "ok"

puts -nonewline "return test..."
proc return_test {} {
    t search -compare {{= name {Doctor Orpheus}}} -array foo -code {
	puts -nonewline " found "
	return $foo(name)
    }
    return "loop ended"
}

if {"[set result [return_test]]" != "Doctor Orpheus"} {
    error "Return test returned '$result'"
}
puts "ok"

puts -nonewline "Testing 'set -nocomplain'..."
proc nocomplain_test {} {
    return [t set randomkey -nocomplain {name "Random Name" unknown unknown}]
}

if {"[set result [nocomplain_test]]" != ""} {
    error "Nocomplain test returned '$result'"
}
puts "ok"

puts -nonewline "Testing type command..."
set tType [t type]
set typeDef [$tType package]
set tabDef [t type package]

if {"$typeDef" != "$tabDef"} {
    error "Type and table mismatch" [list $typeDef != $tabDef]
}
puts "ok"

puts "Resetting test table..."
t reset

search_test_countonly "empty search countOnly no compare" {} {0}

search_test_countonly "empty search countOnly no compare, limit" {-limit 10} {0}

search_test_countonly "search countOnly no compare, offset" {-offset 25} {0}

search_test_countonly "search countOnly compare" {-compare {{false alive}}} {0}

