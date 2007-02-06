#!/usr/local/bin/tclsh8.4

lappend auto_path [exec pwd]

package require sttp_server
package require sttp_client
package require sttp_client_postgres

# Open a sql ctable
set ctable [::sttp::connect sql:///sc_ca_jobs]
puts "\[::sttp::connect sql:///sc_ca_jobs] = $ctable"

set fields [$ctable fields]
puts "\$ctable fields = [$ctable fields]"

$ctable search -compare {{= status complete} {= report_id "CMTS Direct Scan"}} -key k -array_get_with_nulls _a -code {
  array set a $_a
  foreach field $fields {
    puts "$field{$k} = $a($field)"
  }
}
