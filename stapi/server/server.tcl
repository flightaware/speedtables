#
# $Id$

package require ctable
package require scache_locks
package require scache_pgtcl
package require Pgtcl
package require sc_postgres

namespace eval ::scache {
  variable work_dir /var/tmp/autocache
  variable debugging 1
  if $debugging { set work_dir ctables }
  variable version 0.1
  variable cache_time 0

  variable ctable2name

# ::scache::init ?options?
#
# Options:
#   -dir work_directory
#      Root of directory tree for the ctables
#   -mode mode
#      Octal mode for new directory
#   -conn connection
#      Pgsql connection (if not present, assumes DIO)
#   -cache minutes
#      How long to treat a cached tsv file as "good"
#
  proc init {args} {
    array set opts $args
    variable work_dir
    if [info exists opts(-dir)] {
      set work_dir $opts(-dir)
    }
    if [file exists $work_dir] {
      if ![file isdirectory $work_dir] {
	error "$work_dir must be a directory"
      }
    } else {
      file mkdir $work_dir
      if [info exists opts(-mode)] {
        catch {exec chmod $opts(-mode) $work_dir}
      }
    }
    if [info exists opts(-conn)] {
      set_conn $opts(-conn)
    }
    if [info exists opts(-cache)] {
      variable cache_time
      set cache_time [expr {$opts(-cache) * 60}]
    }
  }

  proc debug {args} {
    variable debugging
    if !$debugging return
    set args [split [join $args "\n"] "\n"]
    set m ""
    if {[llength $args] > 1} { append m "\n" }
    append m "[clock format [clock seconds]] [pid] [join $args "\n\t"]
    puts stderr $m
  }

  proc remove_tsv_file {table_name} {
    set tsv_file [workname $table_name tsv]
    if ![file exists $tsv_file] {
      set tsv_file [workname c_$table_name tsv]
    }
    catch {file delete -force $tsv_file}
  }

  variable sql2ctable
  array set sql2ctable {
    macaddr	mac
    varchar	varstring
    integer	int
    timestamp	varstring
    float8	float
    float4	float
    float2	float
    int4	int
    int2	int
    bool	varstring
    geometry	varstring
  }

  variable ctable2sql
  array set ctable2sql {
    mac		macaddr
    int		integer
    long	integer
    varstring	varchar
  }

  # open_cached name ?pattern? ?-opt val?...
  #
  # Open an initialised ctable, maintaining a local cache of the underlying
  # SQL table in a .tsv file in the workdir.
  #
  # Options
  #   pattern
  #   -pat pattern
  #      Only read lines matching the pattern from the cache, if the cache is
  #      good.
  #   -time cache_timeout
  #      Override the default cache timeout.
  #   -col name
  #      Name of column in the SQL file that contains the last_changed time of
  #      each entry, if any.
  #   -index field_name
  #      Name of a field to create an index on. Multiple -index are allowed.
  #
  proc open_cached {name args} {
    variable sql2ctable
    variable ctable2name
    variable cache_time

    set timeout $cache_time
    set pattern "*"
    if {[llength $args] & 1} {
      set pattern [lindex $args 0]
      set args [lrange $args 1 end]
    }
    foreach {n v} $args {
      switch -glob -- $n {
	-pat* { set pattern $v }
        -tim* { set timeout $v }
	-col* { set time_col $v }
	-ind* { lappend indices $v }
	default { return -code error "Unknown option '$n'" }
      }
    }

    set ctable [open_raw_ctable $name]
    set ctable_name "c_$name"

    if [info exists indices] {
      debug "Creating indices"
      foreach list $indices {
	foreach i $list {
	  debug "$ctable index create $i 24"
	  $ctable index create $i 24
	}
      }
      debug "Indexes created"
    }

    set last_read 0
    set tsv_file [workname $ctable_name tsv]
    if ![lockfile $tsv_file err 600] { # block for up to 10 minutes
      return -code error $err
    }
    if [file exists $tsv_file] {
      set file_time [file mtime $tsv_file]
      set read_from_file 0
      set table_complete 0

      if {[info exists time_col] && [string length $time_col]} {
	set read_from_file 1
        set last_read $file_time
      } elseif {!$timeout || $file_time + $timeout > [clock seconds]} {
	set read_from_file 1
	set table_complete 1
      } else {
	debug "Removing stale $tsv_file"
      }
      
      if $read_from_file {
	debug "Reading $ctable from $tsv_file"
        set fp [open $tsv_file r]
        gets $fp line
        set fields [split $line "\t"]
	set read_cmd [list $ctable read_tabsep $fp]
	if {"$pattern" != "*" && $table_complete} {
	  lappend read_cmd -glob $pattern
	}
        debug "eval $read_cmd [lrange $fields 1 end]"
        eval $read_cmd [lrange $fields 1 end]
        close $fp
        if $table_complete {
	  unlockfile $tsv_file
          set ctable2name($ctable) $ctable_name
          return $ctable
        }
      }
      file delete $tsv_file
    }

    set sql_file [workname $ctable_name sql]
    if ![file exists $sql_file] {
      unlockfile $tsv_file
      return -code error "Uninitialised ctable $ctable_name"
    }
    set fp [open $sql_file r]
    set sql [read $fp]
    close $fp

    set sql [set_time_limit $sql $time_col $last_read]

    if [catch {read_ctable_from_sql $ctable $sql} err] {
      $ctable destroy
      unlockfile $tsv_file
      return -code error -errorinfo $::errorInfo $err
    }

    save_ctable $ctable $tsv_file

    unlockfile $tsv_file

    set ctable2name($ctable) $ctable_name

    return $ctable
  }

  #
  # refresh_ctable name ctable time_col ?last_read? ?err?
  #
  # Update new rows from SQL table 'table' into ctable 'ctable' using time_col,
  # if last_read is non-zero use that rather than last modify time of the cache,
  # return success or failure if err variable name is provided.
  #
  proc refresh_ctable {name ctable time_col {last_read 0} {_err ""}} {
    if {"$_err" != ""} {
      upvar 1 $_err err
      set _err err
    }

    set ctable_name c_$name
    set sql_file [workname $ctable_name sql]
    if ![file exists $sql_file] {
      set err "Uninitialised ctable $ctable_name"
      if {"$_err" == ""} {
        return -code error $err
      }
      return 0
    }

    set fp [open $sql_file r]
    set sql [read $fp]
    close $fp

    if !$last_read {
      if {[string length $time_col]} {
        set tsv_file [workname $ctable_name tsv]
        set last_read [file mtime $tsv_file]
      }
    }

    set sql [set_time_limit $sql $time_col $last_read]
    return [read_ctable_from_sql $ctable $sql $_err]
  }

  #
  # Apply a time limit to an SQL statement (limited in design to the
  # statements generated by this code, not necessarily workable for general
  # case.
  #
  proc set_time_limit {sql time_col last_read} {
    if {"$time_col" == ""} {
      set last_read 0
    }
    if $last_read {
      set time_val [
	::sc_pg::clock_to_precise_sql_time_without_timezone $last_read
      ]
      set time_sql "$time_col > '$time_val'"
      debug "Will add new entries since $time_val"
      if [regexp -nocase { where } $sql] {
	set operator AND
      } else {
	set operator WHERE
      }
      regsub "\[;\n]*$" $sql " $operator $time_sql;" sql
    }
    return $sql
  }

  #
  # save a ctable, locating and locking the tsv file if not provided
  #
  proc save_ctable {ctable {tsv_file ""}} {
    variable ctable2name
    
    set locked 0
    if {"$tsv_file" == ""} {
      if ![info exists ctable2name($ctable)] {
        return -code error "Can't save $ctable - not cached"
      }
      set tsv_file [workname $ctable2name($ctable) tsv]

      if ![lockfile $tsv_file err 600] { # block for up to 10 minutes
        return -code error $err
      }
      set locked 1
    }

    debug "Writing $ctable to $tsv_file"
    set fp [open $tsv_file w]
    puts $fp [join [concat _key [$ctable fields]] "\t"]
    $ctable write_tabsep $fp
    close $fp

    if $locked {
      unlockfile $tsv_file
    }
  }

  # init_ctable name table_list where_clause ?columns|key_col column...?
  #
  #   name - base name of ctable
  #   table_list - list of SQL tables to extract data from
  #   where_clause - SQL "WHERE" clause to limit selection
  #   columns - list of column entries, first is key
  #   key_col - ley
  #   column - comumn entry
  #
  # Column entries are each a list of {field type expr ?name value?...}
  #
  #   field - field name
  #   type - sql type
  #   expr - sql expression to derive value, same as field name if missing
  #   name value
  #      - ctable arguments for the field
  #
  proc init_ctable {name tables where_clause args} {
    variable sql2ctable

    if {[llength $args] == 0} {
      set args "name tables where_clause ?columns|key_col column...?"
      return -code error "Usage [namespace which init_ctable] $args"
    }
    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }
    if {[llength $args] <= 1} {
      return -code error "Not enough columns in '[list $args]'"
    }

    init
    set ctable_name "c_$name"

    set ctable_dir [workname $ctable_name]
    if ![lockfile $ctable_dir err] {
      return -code error $err
    }

    variable version
    set full_version [package version ctable]+$version
    set verfile [workname $ctable_name ver]

    lappend tcl [namespace which init_ctable] $name $tables $where_clause
    set tcl [concat $tcl $args]
    set tclfile [workname $ctable_name tcl]

    if [file exists $verfile] {
      set fp [open $verfile r]
      set old_version [read -nonewline $fp]
      close $fp
      if {"$full_version" != "$old_version"} {
        trash_old_files $ctable_name
      }
    } else {
      trash_old_files $ctable_name
    }

    if [file exists $tclfile] {
      set fp [open $tclfile r]
      set old_tcl [read -nonewline $fp]
      close $fp
      if {"$old_tcl" == "$tcl"} {
	unlockfile $ctable_dir
	return 1
      }
      trash_old_files $ctable_name
    }

    array unset options
    foreach arg $args {
      foreach {col type expr} $arg break
      if {[llength $arg] > 3} {
        set options($col) [lrange $arg 3 end]
      }
      if {"$type" == ""} {
	set type varchar
      }
      if ![info exists ctable_key] {
        set ctable_key $col
      } else {
        lappend fields $col $type
      }
      if {"$expr" == ""} {
	lappend selected $col
      } else {
	lappend selected "$expr AS $col"
      }
    }

    set sql "SELECT [join $selected ,] FROM [join $tables ,]"
    if {"$where_clause" != ""} {
      append sql " WHERE $where_clause"
    }
    append sql ";"

    set sqlfile [workname $ctable_name sql]

    set ctable_dir [workname $ctable_name]
    if {[lsearch $::auto_path $ctable_dir] == -1} {
      lappend ::auto_path $ctable_dir
    }

    array set types $fields

    set cext_name "c_$name"
    foreach {n t} $fields {
      if [info exists sql2ctable($t)] {
        set t $sql2ctable($t)
      }
      if [info exists options($n)] {
	lappend ctable "$t\t[concat $n $options($n)];"
      } else {
        lappend ctable "$t\t$n;"
      }
    }

    debug "Building: CExtension $cext_name 1.1 { CTable $ctable_name {...} }"

    # Once we start creating files, we need to completely trash whatever's
    # partially created if there's an error...

    if [catch {
      file mkdir $ctable_dir

      CTableBuildPath $ctable_dir

      CExtension $cext_name 1.1 "
	CTable $ctable_name {
	    [join $ctable "\n\t    "]
	}
      "

      set fp [open $verfile w]
      puts $fp $full_version
      close $fp

      set fp [open $tclfile w]
      puts $fp $tcl
      close $fp

      set fp [open $sqlfile w]
      puts $fp $sql
      close $fp
    } err] {
      unlockfile $ctable_dir
      trash_old_files $ctable_name
      error $err $::errorInfo
    }

    unlockfile $ctable_dir
    return 1
  }

  #
  # Helper function for creating a cached ctable using the SQL database to
  # figure out the columns in the specified SQL table name.
  #
  # table_name - SQL table name
  # key - a column or list of columns in the SQL table that defines the
  #       unique key
  # name - if specified, use this for the ctable name rather than the SQL
  #       table name
  # selected_cols - a list of columns in the table.
  #       col - same as SQL column name
  #       +col - SQL column 'col', ctable column will be indexed
  #       * - wildcard, all columns are included
  proc init_cache_ctable {table_name key {name ""} {selected_cols {}}} {
    puts [info level 0]
    set columns [get_columns $table_name]
    if {"$name" == ""} {
      set name [string tolower $table_name]
    }
    if {[llength $key_column] > 1} {
      set key_column TEXT([join $key_column ") || ':' || TEXT("])
    }
    lappend args [list _key "" $key_column]
    foreach {col type} $columns {
      set options {}
      if [llength $selected_cols] {
	if {[lsearch -exact $selected_cols +$col] != -1} {
	  lappend options indexed 1
	} elseif {
	  [lsearch -exact $selected_cols "*"] == -1 &&
	  [lsearch -exact $selected_cols $col] == -1
	} {
	  continue
        }
      }
      lappend args [concat [list $col $type ""] $options]
    }
    return [init_ctable $name $table_name "" $args]
  }

  #
  # Open an initialized ctable but don't fetch anything from SQL, used
  # internally, and useful for temporary tables, copies, etcetera...
  #
  proc open_raw_ctable {name} {
    init

    set ctable_dir [workname c_$name]
    if ![lockfile $ctable_dir err] {
      return -code error $err
    }
    if ![file isdir $ctable_dir] {
      unlockfile $ctable_dir
      return -code error "Uninitialised ctable c_$name]
    }
    if {[lsearch $::auto_path $ctable_dir] == -1} {
      lappend ::auto_path $ctable_dir
    }

    if [catch {
      set status [c_$name create #auto]
    } err] {
      unlockfile $ctable_dir
      error $err $::errorInfo
    }
      
    unlockfile $ctable_dir
    return $status
  }

  proc trash_old_files {ctable_name} {
    foreach ext {ver sql tcl lock tsv ""} {
      file delete -force [workname $ctable_name $ext]
    }
  }

  proc workname {name {ext ""}} {
    variable work_dir
    if {"$ext" != ""} {
      append $name . $ext
    }
    return [file join $work_dir $name]
  }
}

package provide scache 1.0
