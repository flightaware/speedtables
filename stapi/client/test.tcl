#!/usr/local/bin/tclsh8.4

lappend auto_path [exec pwd]

package require st_server
package require st_client
package require st_client_postgres

# Open a sql ctable
set ctable [::stapi::connect sql:///sc_ca_jobs]
puts "\[::stapi::connect sql:///sc_ca_jobs] = $ctable"

set fields [$ctable fields]
puts "\$ctable fields = [$ctable fields]"

$ctable search -compare {{= status complete} {= report_id "CMTS Direct Scan"}} -key k -array_get_with_nulls _a -code {
  array set a $_a
  foreach field $fields {
    puts "$field{$k} = $a($field)"
  }
}
