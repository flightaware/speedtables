#!/usr/local/bin/tclsh8.4

lappend auto_path [exec pwd]

package require st_server
package require st_postgres
package require ctable
set ::ctable::genCompilerDebug 1
set quick 1

# Get a list of columns.
set columns [
  ::stapi::from_table sc_ca_no_response device_id -index time -index ip
]
puts "\$columns = [list $columns]"

# Set up the ctable
::stapi::init_ctable sc_ca_no_response {} "" $columns

# Open and read it
set nr [::stapi::open_cached sc_ca_no_response -col time -index time]

# Check size
puts "\[$nr count] = [$nr count]"

puts "Most recent 3 values"
$nr search -sort {-time} -array_get _a -limit 3 -code {
  array set a $_a
  set last_time [::stapi::sql2clock $a(time)]
  puts "$a(device_id)\t$a(time)"
}

if $quick exit

puts "Sleeping for 10s"
sleep 10

::stapi::refresh_ctable $nr $last_time

puts "Most recent 3 values"
$nr search -sort {-time} -array_get _a -limit 3 -code {
  array set a $_a
  puts "$a(device_id)\t$a(time)"
}
