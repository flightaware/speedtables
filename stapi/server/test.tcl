#!/usr/local/bin/tclsh8.4

lappend auto_path [exec pwd]

package require st_server
package require st_postgres
package require ctable
set ::ctable::genCompilerDebug 1
set quick 1

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

