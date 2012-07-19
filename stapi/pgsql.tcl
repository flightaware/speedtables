#
#
# Copyright (C) 2008 by FlightAware LLC.  All Rights Reserved
# Copyright (C) 2006 by Superconnect, Ltd.  All Rights Reserved
#
# Open source under the Berkeley license
#
# $Id$
#

package require Pgtcl

namespace eval ::stapi {
  variable pg_conn
  variable default_user
  variable default_db
  variable dio_initted 0
  variable cache_table_columns 1

  #
  # set_DIO - try to create a global DIO object ::DIO with a default connection
  #  to the database.  OK to call over and over.
  #
  proc set_DIO {{db ""} {user ""}} {
    variable dio_initted
    if $dio_initted {
      return
    }

    if {[llength [info commands ::DIO]]} {
      set dio_initted 1
      return
    }

    if {"$user" == ""} {
      variable default_user
      if {![info exists default_user]} {
	return -code error "No SQL user provided"
      }
      set user $default_user
    }

    if {"$db" == ""} {
      variable default_db
      if {![info exists default_db]} {
	return -code error "no SQL db provided"
      }
      set db $default_db
    }

    uplevel #0 { package require DIO }
    ::DIO::handle Postgresql DIO -user $user -db $db
    exec_sql "set DateStyle TO 'US';"
    set dio_initted 1
  }

  #
  # set_conn - tell stapi what postgresql database connection object to
  #  use for its database connection
  #
  proc set_conn {new_conn} {
    variable pg_conn
    set pg_conn $new_conn
  }

  #
  # conn - get the database connection that stapi is supposed to use.
  #
  #  Do it by returning the connection defined in a call using set_conn
  #  or obtain it from DIO if there's a DIO object to get it from
  #
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

  #
  # exec_sql - execute some SQL.  Handle the result object.  Require
  #  it to succeed.  If it doesn't succeed, returns a Tcl error
  #  with the error text from pg_result and the request that caused
  #  it to happen
  #
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

  #
  # exec_sql_rows - like exec_sql except a variable passed in gets set
  #  with either the number of tuples retrieved or the number of
  #  tuples the command altered
  #
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

  #
  # get_columns - for the specified table, get each column's name and internal
  #  type specification and return them as a list of pairs
  #
  proc get_columns {table} {
    variable tableColumnCache
    variable cache_table_columns

    if {$cache_table_columns && [info exists tableColumnCache($table)]} {
        return $tableColumnCache($table)
    }

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

    if {$cache_table_columns} {
	set tableColumnCache($table) $result
    }

    return $result
  }

  #
  # better_get_columns - for the specified table, get each columns's
  # name, "real" type specification (like "character(5)" or 
  # "character varying") and whether or not it is null (t/f) and
  # return a list of triplets
  #
  proc better_get_columns {table} {
    set sql "SELECT a.attnum, a.attname AS col,
		pg_catalog.format_type(a.atttypid, a.atttypmod) as type,
		a.attnotnull as not_null
		FROM pg_class c, pg_attribute a, pg_type t
		WHERE c.relname = '$table'
		  and a.attnum > 0
		  and a.attrelid = c.oid
		  and a.atttypid = t.oid
		ORDER BY a.attnum;"
    pg_select [conn] $sql row {
      lappend result $row(col) $row(type) $row(not_null)
    }
    if ![info exists result] {
      return -code error "Can't get columns for $table"
    }
    return $result
  }

  #
  # read_ctable_from_sql - specify a ctable and a SQL select statement and
  #  this code invokes the SQL statement and loads the results into the
  #  specified ctable
  #
  # does a Tcl error if it gets an error from postgres unless error variable
  # is specified, in which case it sets the error message into the error
  # variable and returns -1.
  #
  # if successful it returns the number of tuples read, from zero on up.
  #
  proc read_ctable_from_sql {ctable sql {_err ""}} {
    if [string length $_err] { upvar 1 $_err err }

    set pg_res [pg_exec [conn] $sql]
    if {![set ok [string match "PGRES_*_OK" [pg_result $pg_res -status]]]} {
      set err [pg_result $pg_res -error]
      set errinf "$err\nIn \"sql\""
    } elseif {[catch {$ctable import_postgres_result $pg_res} err]} {
      set ok 0
      set errinf $::errorInfo
    }
    set numTuples [pg_result $pg_res -numTuples]
    pg_result $pg_res -clear

    if !$ok {
      if [string length $_err] { return -1 }
      return -code error -errorinfo $errinf $err
    }

    return $numTuples
  }

  #
  # read_ctable_from_sql_async - specify a ctable and a SQL select statement and
  #  this code invokes the SQL statement and loads the results into the
  #  specified ctable, asynchronously
  #
  # does a Tcl error if it gets an error from postgres unless error variable
  # is specified, in which case it sets the error message into the error
  # variable and returns -1.
  #
  # if successful it returns the number of tuples read, from zero on up.
  #
  proc read_ctable_from_sql_async {ctable sql callback} {
    pg_blocking [conn] 0

    # it either errors or returns nothing.  why catch the error and pass
    # it back, just let the error go on its own
    pg_sendquery [conn] $sql

    read_ctable_async_poll $ctable $callback
  }

  #
  # read_ctable_async_poll - async poll routine invoked by 
  # read_ctable_from_sql_async
  #
  proc read_ctable_async_poll {ctable callback} {
    if {![pg_isbusy [conn]]} {
	set pg_res [pg_getresult [conn]]
	if {$pg_res == ""} {
	    uplevel #0 {*}$callback 
	    pg_blocking [conn] 0
	    return
	}

	$ctable import_postgres_result $pg_res -poll_code update -poll_interval 100
	pg_result $pg_res -clear
    }
    after 10 [list ::stapi::read_ctable_async_poll $ctable $callback]
  }

  #
  # generate a SQL time from an integer clock time (seconds since 1970),
  # accurate to the second, without timezone info (using local timezone)
  #
  proc clock2sql {clock} {
    return [clock format $clock -format "%b %d %H:%M:%S %Y"]
  }
  
  #
  # generate a SQL time from an integer clock time (seconds since 1970),
  # accurate to the second, using GMT
  #
  proc clock2sqlgmt {clock} {
    return [clock format $clock -format "%b %d %H:%M:%S %Y" -timezone :UTC]
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

package provide st_postgres 1.8.2
