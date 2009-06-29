# Proc to test index search, compares loop over table with internal count

proc test_index {table args} {
  puts -nonewline [info level 0]...; flush stdout
  set comp [list $args]
  set longway 0
  $table search -compare $comp -key dummy -code { incr longway }
  set shortway [$table search -compare $comp]
  if {"$shortway" != "$longway"} {
    puts "FAIL"
    error "$table search -compare $comp - Longway was '$longway' shortway was '$shortway'"
  }
  puts "OK"
}

