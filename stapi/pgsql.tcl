#
#
# Copyright (C) 2006 by Superconnect, Ltd.  All Rights Reserved
#
#
# $Id$
#

package require Pgtcl

namespace eval ::sttp {
  variable pg_conn
  variable dio_initted 0

  proc set_DIO {} {
    variable dio_initted
    if $dio_initted {
      return
    }
    set dio_initted 1
    if {[llength [info commands ::DIO]]} { return }

    uplevel #0 { package require DIO }
    ::DIO::handle Postgresql DIO -user www -db www
    exec_sql "set DateStyle TO 'US';"
  }

  proc set_conn {new_conn} {
    variable pg_conn
    set pg_conn new_conn
  }

  proc conn {} {
    variable pg_conn

    if [info exists pg_conn] {
      return $pg_conn
    }

    variable dio_initted
    if !$dio_initted {
      set_DIO
    }
    return [DIO handle]
  }

  proc exec_sql {request {_err ""}} {
    if [string length $_err] { upvar 1 $_err err }

    set pg_res [pg_exec [conn] $request]
    if {![set ok [string match "PGRES_*_OK" [pg_result $pg_res -status]]]} {
      set err [pg_result $pg_res -error]
      set errinf "$err\nIn $request"
    }
    pg_result $pg_res -clear

    if !$ok {
      if [string length $_err] { return 0 }
      return -code error -errorinfo $errinf $err
    }
    return 1
  }

  proc exec_sql_rows {request _rows {_err ""}} {
    if [string length $_err] { upvar 1 $_err err }

    set pg_res [pg_exec [conn] $request]
    set status [pg_result $pg_res -status]
    if {"$status" == "PGRES_COMMAND_OK"} {
      set ok 1
      upvar 1 $_rows rows
      set rows [pg_result $pg_res -cmdTuples]
    } elseif {"$status" == "PGRES_TUPLES_OK"} {
      set ok 1
      upvar 1 $_rows rows
      set rows [pg_result $pg_res -numTuples]
    } elseif {[string match "PGRES_*_OK" $status]} {
      set ok 1
    } else {
      set ok 0
      set err [pg_result $pg_res -error]
      set errinf "$err\nIn $request"
    }
    pg_result $pg_res -clear

    if !$ok {
      if [string length $_err] { return 0 }
      return -code error -errorinfo $errinf $err
    }
    return 1
  }

  proc get_columns {table} {
    set sql "SELECT a.attnum, a.attname AS col, t.typname AS type
		FROM pg_class c, pg_attribute a, pg_type t
		WHERE c.relname = '$table'
		  and a.attnum > 0
		  and a.attrelid = c.oid
		  and a.atttypid = t.oid
		ORDER BY a.attnum;"
    pg_select [conn] $sql row {
      lappend result $row(col) $row(type)
    }
    if ![info exists result] {
      return -code error "Can't get columns for $table"
    }
    return $result
  }

  proc read_ctable_from_sql {ctable sql {_err ""}} {
    if [string length $_err] { upvar 1 $_err err }

    set pg_res [pg_exec [conn] $sql]
    if ![set ok [string match "PGRES_*_OK" [pg_result $pg_res -status]]] {
      set err [pg_result $pg_res -error]
      set errinf "$err\nIn \"sql\""
    } elseif {[catch {$ctable import_postgres_result $pg_res} err]} {
      set ok 0
      set errinf $::errorInfo
    }
    pg_result $pg_res -clear

    if !$ok {
      if [string length $_err] { return 0 }
      return -code error -errorinfo $errinf $err
    }

    return 1
  }

  #
  # generate a SQL time from an integer clock time (seconds since 1970),
  # accurate to the second, without timezone info (using local timezone)
  #
  proc clock2sql {clock} {
    return [clock format $clock -format "%b %d %H:%M:%S %Y"]
  }
  
  #
  # convert a SQL time without timezone to a clock value (integer
  # seconds since 1970)
  #
  proc sql2clock {time} {
    if {$time == ""} {
      return 0
    }
    return [clock scan [lindex [split $time "."] 0]]
  }
}

package provide sttp_postgres 1.0
