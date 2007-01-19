#!/usr/local/bin/tclsh8.4

lappend auto_path [exec pwd]

package require scache
package require sc_postgres
package require scache_client
package require scache_sql_client

# Open a sql ctable
set ctable [::scache::connect sql:///sc_ca_jobs]
puts "\[::scache::connect sql:///sc_ca_jobs] = $ctable"

set fields [$ctable fields]
puts "\$ctable fields = [$ctable fields]"

$ctable search -compare {{= status complete} {= report_id "CMTS Direct Scan"}} -key k -array_get_with_nulls _a -code {
  array set a $_a
  foreach field $fields {
    puts "$field{$k} = $a($field)"
  }
}
