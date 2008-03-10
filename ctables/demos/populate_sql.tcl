#!/usr/bin/env tclsh8.4
# $Id$

# Import /etc/passwd into database

package require ctable
package require Pgtcl

source passwd_table.tcl

set pwtab [u_passwd create #auto]

load_pwfile $pwtab /etc/passwd

set conn [pg_connect -conninfo "dbname=www user=www"]

set r [pg_exec $conn "COPY passwd FROM stdin with DELIMITER as '\t';"]
if {"[pg_result $r -status]" == "PGRES_COPY_IN"} {
  $pwtab search -write_tabsep $conn -nokeys 1
  puts $conn "\\."
} else {
  puts [pg_result $r -error]
}
pg_result $r -clear
