#
#
# Copyright (C) 2006 by Superconnect, Ltd.  All Rights Reserved
#
#
# $Id$
#

package require Pgtcl

namespace eval ::scache {
  variable pg_conn
  variable dio_initted 0

  proc set_DIO {} {
    variable dio_initted
    if $dio_initted {
      return
    }
    set dio_initted 1
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
    set pg_res [pg_exec [conn] $request]
    if {[pg_result $pg_res -status] != "PGRES_COMMAND_OK"} {
      set pg_err [pg_result $pg_res -error]
    }
    pg_result $pg_res -clear

    if [info exists pg_err] {
      if [string length $_err] {
	upvar 1 $_err err
	set err $pg_err
	return 0
      }
      return -code error -errorinfo "In $request" $error
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
    debug "Setting up database request" $sql

    if ![catch {set pg_res [pg_exec [conn] $sql]} pg_err] {
      unset -nocomplain pg_err
      set pg_stat [pg_result $pg_res -status]
      if {![string match "PGRES_*_OK" $pg_stat]} {
        set pg_err [pg_result $pg_res -error]
        pg_result $pg_res -clear
      }
    }

    if [info exists pg_err] {
      if [string length $_err] {
        upvar 1 $_err err
	set error $pg_err
        return 0
      }
      return -code error -errorinfo "$err\nIn \"pg_exec \[conn] $sql\"" $err
    }

    debug "Reading $ctable from database"
    $ctable import_postgres_result $pg_res

    pg_result $pg_res -clear

    return 1
  }
}

package provide scache_pgtcl 1.0
