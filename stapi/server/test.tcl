#!/usr/local/bin/tclsh8.4

lappend auto_path [exec pwd]

package require scache
package require sc_postgres

# Get a list of columns.
set columns [
  ::scache::from_table sc_ca_no_response device_id -index time -index ip
]
puts "\$columns = [list $columns]"

# Set up the ctable
::scache::init_ctable sc_ca_no_response {} "" $columns

# Open and read it
set nr [::scache::open_cached sc_ca_no_response -col time -index time -index ip]

# Check size
puts "\[$nr count] = [$nr count]"

puts "Most recent 3 values"
$nr search -sort {-time} -array_get _a -limit 3 -code {
  array set a $_a
  set last_time [::sc_pg::sql_time_to_clock $a(time)]
  puts "$a(device_id)\t$a(time)"
}

puts "Sleeping for 10s"
sleep 10

::scache::refresh_ctable $nr $last_time

puts "Most recent 3 values"
$nr search -sort {-time} -array_get _a -limit 3 -code {
  array set a $_a
  puts "$a(device_id)\t$a(time)"
}
