# Proc to test index search, compares loop over table with internal count

proc test_index {table args} {
  set verbose 0
  if {"$table" == "-v"} {
    set table [lindex $args 0]
    set args [lrange $args 1 end]
  }
  if {$verbose} {puts -nonewline [info level 0]...; flush stdout}
  set comp [list $args]
  set longway 0
  $table search -compare $comp -key dummy -code { incr longway }
  set shortway [$table search -compare $comp]
  if {"$shortway" != "$longway"} {
    if {$verbose} {puts "FAIL"}
    error "$table search -compare $comp - Longway was '$longway' shortway was '$shortway'"
  }
  if {$verbose} {puts "OK"}
}

