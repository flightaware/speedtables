# 
# stapi code to copy 
#
# Copyright (C) 2006 by Superconnect, Ltd.  All Rights Reserved
# Copyright (C) 2008-2009 by FlightAware LLC. All Rights Reserved
#
# Released under the Berkeley license
#
# $Id$
#

namespace eval ::stapi {
  #
  # copyin_tsv_file - load a TSV file into a SQL table
  #
  # set rows [copyin_tsv_file $filename $table ?$skip? ?err?]
  #
  # Copy a named tsv file in, optionally skipping ?$skip? columns
  # Returns #rows in file, 0 for no data, <0 for sql error
  # Raises error if ?err? not provided and sql error occurs
  #
  proc copyin_tsv_file {file table {skip 0} {_err ""}} {
    if {"$_err" != ""} {
      upvar 1 $_err err
    }

    set fp [open $file r]

    if ![gets $fp columns] {
      close $fp
      set err "Empty file"
      return 0
    }

    set columns [split $columns "\t"]
    if $skip {
      set columns [lrange $columns $skip end]
    }

    if {[gets $fp row] < 0} {
      close $fp
      set err "No data"
      return 0
    }

    set rows 0

    # have to use pgtcl directly, DIO not flexible enough.
    set dp [DIO handle]
    set sql "COPY $table ([join $columns ","]) FROM STDIN WITH NULL AS '';"
    # debug $sql
    set res [pg_exec $dp $sql]
    if {"[pg_result $res -status]" != "PGRES_COPY_IN"} {
      set err [pg_result $res -error]
      pg_result $res -clear
      if {"$_err" == ""} {
	return -code error "copyin_tsv_file: $err"
      } else {
	return -1
      }
    }
    while 1 {
      incr rows
      if $skip {
	set row [join [lrange [split $row "\t"] $skip end] "\t"]
      }
      puts $dp $row
      if {[gets $fp row] < 0} {
	break
      }
    }
    close $fp
    puts $dp {\.}
    if {"[pg_result $res -status]" != "PGRES_COMMAND_OK"} {
      set err [pg_result $res -error]
      pg_result $res -clear
      if {"$_err" == ""} {
	return -code error "copyin_tsv_file: $err"
      } else {
	set rows -$rows
      }
    }
    pg_result $res -clear
    return $rows
  }

  #
  # copyout_ctable - copy a ctable into a SQL table
  #
  # set rows [copyout_ctable $ctable $table ?keyname? ?options? ?columns?]
  #
  # Copy a named ctable to a table. Options:
  #   -nokeys        -- skip key column
  #   -glob pattern -- limit import to rows with key column matching pattern
  #   column-name   -- limit import to named list of columns
  # Raises error if sql error occurs
  #
  proc copyout_ctable {ctable table args} {
    if ![string match "-*" [lindex $args 0]] {
      set keycol [lindex $args 0]
      set args [lrange $args 1 end]
    }
    while {[string match "-*" [set opt [lindex $args 0]]]} {
      switch -- $opt {
	-nokeys {
	  set args [lrange $args 1 end]
        }

	-glob {
	  set pattern [lindex $args 1]
	  set args [lrange $args 2 end]
	}

	default {
	  return -code error "copyout_ctable: Unknown option $opt"
	}
      }
    }

    # have to use pgtcl directly, DIO not flexible enough.
    set dp [DIO handle]

    lappend cmd $ctable write_tabsep $dp
    if ![info exists keycol] {
      lappend cmd -nokeys
    }

    if [info exists pattern] {
      lappend cmd -glob $pattern
    }

    if [llength $args] {
      set cmd [concat $cmd $args]
    } else {
      set args [$ctable fields]
    }

    if [info exists keycol] {
      set args [concat [list $keycol] $args]]
    }

    set sql "COPY $table ([join $args ","]) FROM STDIN WITH NULL AS '';"
    # debug $sql
    set res [pg_exec $dp $sql]
    if {"[pg_result $res -status]" != "PGRES_COPY_IN"} {
      set err [pg_result $res -error]
      pg_result $res -clear
      return -code error "copyout_ctable: $err in '$sql'"
    }

    eval $cmd
    if [catch {puts $dp {\.}} err] {
      append err "; [pg_result $res -error]"
      pg_result $res -clear
      return -code error "copyout_ctable: $err after '$sql' in $ctable"
    }

    if {"[pg_result $res -status]" != "PGRES_COMMAND_OK"} {
      set err [pg_result $res -error]
      pg_result $res -clear
      return -code error "copyout_ctable: $err"
    }

    set n [pg_result $res -cmdTuples]
    pg_result $res -clear
    return $n
  }
}

package provide st_postgres 1.9.1

