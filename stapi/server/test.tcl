#!/usr/local/bin/tclsh8.4

# put new directories first to make sure we're testing this version of
# stapi and speedtables
set __new_path {}
if [info exists env(ST_PREFIX)] {
  lappend __new_path $env(ST_PREFIX)
}
if [info exists env(STAPI_PREFIX)] {
  lappend __new_path $env(STAPI_PREFIX)
} else {
  lappend __new_path [exec pwd]
}
set auto_path [concat $__new_path $auto_path]

package require st_server
package require st_postgres
package require ctable
set ::ctable::genCompilerDebug 1
set quick 1
if [info exists env(PG_DB)] {
  ::stapi::set_conn [pg_connect $env(PG_DB)]
}

# Get a list of columns.
set columns [
  ::stapi::from_table stapi_test isbn -index author -index pages
]
puts "\$columns = [list $columns]"

# Set up the ctable
::stapi::init_ctable stapi_test {} "" $columns

# Open and read it
set nr [::stapi::open_cached stapi_test -col isbn -index pages]

# Check size
puts "\[$nr count] = [$nr count]"

puts "Highest page count"
puts [format "%-13s %-28s %-28s %-5s" ISBN AUTHOR TITLE PAGES]
$nr search -sort {-pages} -array_get _a -limit 1 -code {
  array set a $_a
  puts [format "%13s %-28s %-28s %5d" $a(isbn) $a(author) $a(title) $a(pages)]
}

