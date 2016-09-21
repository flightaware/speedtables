#!/usr/local/bin/tclsh8.4

set d [exec pwd]
if [file exists $d/pkgIndex.tcl] {
  puts stderr "auto path is $d"
  lappend auto_path $d
}
set d [file dirname $d]
if [file exists $d/pkgIndex.tcl] {
  puts stderr "auto path is $d"
  lappend auto_path $d
}

package require st_server
package require st_client
package require st_client_postgres
source pgsql.tcl

if [file exists postgres.tcl] {
  source postgres.tcl
  pgconn
}

if [file exists ../postgres.tcl] {
  source ../postgres.tcl
  pgconn
}

# Open a sql ctable
set ctable [::stapi::connect sql:///stapi_test]
puts "\[::stapi::connect sql:///stapi_test] = $ctable"

set fields [$ctable fields]
puts "\$ctable fields = [$ctable fields]"

$ctable search -compare {{match isbn 1-56592-*}} -key k -array_get_with_nulls _a -code {
  array set a $_a
  foreach field $fields {
    puts "$field{$k} = $a($field)"
  }
}
# vim: set ts=8 sw=4 sts=4 noet :
