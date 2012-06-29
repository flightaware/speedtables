#
# $Id$

package require ctable
package require st_locks
package require st_postgres
package require st_debug
package require Pgtcl

namespace eval ::stapi {
  # Generated file version - change any time there's an incompatible change
  # in the format or behaviour of speedcache
  variable version 0.1

  # Default "stale cache" timeout, zero for no timeout.
  variable default_timeout 0

  # Generated ctables, cached data, and config files are all stored
  # under build_root.
  #
  # build_root
  #   +--- c_tablename.ver # Any change to this file invalidates the build
  #   +--- c_tablename.tcl # Tcl code to re-initialize the table
  #   +--- c_tablename.sql # SQL code to load the table from the database
  #   +--- c_tablename.tsv # Cached data
  #   +--- c_tablename     # ctable build directory
  #   |
  #   +--- c_anothertablename.*
  #   +--- c_anothertablename
  #   +...
  #
  # Locks are "filename.lock", see lock.tcl for details.
  #
  variable build_root

  variable default_build_root stapi

  # Saved information about open ctables
  variable ctable2name
  variable time_column
  variable sql_cache

  # Mapping from sql column types to ctable field types
  variable sql2speedtable
  array set sql2speedtable {
    "character varying"           varstring
    varchar	                  varstring
    name                          varstring
    text                          varstring

    timestamp                      varstring
    "timestamp without time zone"  varstring
    "timestamp with time zone"     varstring
    date                           varstring

    time                           varstring
    "time with time zone"          varstring
    "time without time zone"       varstring

    uuid                           varstring
    xml                            varstring
    tsquery                        varstring
    tsvector                       varstring

    macaddr	                   mac

    oid                            int

    bigint                         long
    int8                           long

    integer	                   int
    int4	                   int
    serial                         int

    int8                           wide

    interval                       varstring

    int2                           short
    smallint                       short

    float2	                   float
    float4	                   float
    real                           float

    float8	                   double
    "double precision"             double
    numeric                        double

    bool	                   boolean
    geometry	                   varstring
  }

  # Mapping from ctable field types to sql column types
  variable ctable2sql
  array set ctable2sql {
    mac		macaddr
    int		integer
    long	integer
    varstring	varchar
  }

  # ::stapi::init ?options?
  #
  # Options:
  #   -dir build_root_dir
  #      Root of directory tree for the ctables
  #
  #   -mode mode
  #      Octal mode for new root if it doesn't already exist
  #
  #   -conn connection
  #      Pgsql connection (if not present, assumes DIO), see pgsql.tcl
  #
  #   -cache minutes
  #      How long to treat a cached tsv file as "good"
  #
  proc init {args} {
    array set opts $args

    variable build_root
    variable default_build_root

    #
    if {[info exists opts(-dir)]} {
      set build_root $opts(-dir)
    }

    if {![info exists build_root]} {
      if {[info exists ::env(CTABLE_DIR)]} {
        set build_root $::env(CTABLE_DIR)
      } else {
        set build_root $default_build_root
      }
    }

    if {[file exists $build_root]} {
      if {![file isdirectory $build_root]} {
	error "$build_root must be a directory"
      }
    } else {
      file mkdir $build_root

      if {[info exists opts(-mode)]} {
        catch {exec chmod $opts(-mode) $build_root}
      }
    }

    # save off various configuration parameters

    if {[info exists opts(-conn)]} {
      set_conn $opts(-conn)
    }

    if {[info exists opts(-cache)]} {
      variable default_timeout
      set default_timeout [expr {$opts(-cache) * 60}]
    }

    if {[info exists opts(-user)]} {
      variable default_user
      set default_user $opts(-user)
    }

    if {[info exists opts(-db)]} {
      variable default_db
      set default_db $opts(-db)
    }
  }

  # init_ctable name table_list where_clause ?columns|column...?
  #
  # Initialize a cache ctable based on one or more SQL tables. If necessary,
  # this builds a ctable based on the columns, and generates new SQL to read
  # the table. If the ctable is already built, the version numbers match, and
  # the parameters match, then it's not necessary to rebuild the table and
  # init_ctable simply verifies that it's up to date.
  #
  #   name - base name of ctable
  #
  #   table_list - list of SQL tables to extract data from, if it's empty
  #             then use the name.
  #
  #   where_clause - SQL "WHERE" clause to limit selection, or an empty string
  #
  #   columns - list of column definitions. There must be at least two
  #             columns defined, the first is the ctable key, the rest are
  #             the fields of the ctable. If there is only one "column"
  #             argument, it's assumed to be a list of column arguments.
  #
  # Column entries are each a list of {field type expr ?name value?...}
  #
  #   field - field name
  #
  #   type - sql type
  #
  #   expr - sql expression to derive value
  #
  #   name value
  #      - ctable arguments for the field
  #
  # * Only the field name is absolutely required.
  #
  # If the type is missing or blank, it's assumed to be varchar.
  # If the expression is missing or blank, it's assumed to be the same as
  #    the field name.
  # 
  proc init_ctable {name tables where_clause args} {
    variable sql2speedtable

    # Validate arguments.
    if {"$name" == ""} {
      return -code error "Empty ctable name"
    }

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

    # make sure stapi init proc has been invoked
    init

    #
    set ctable_name "c_$name"

    # Lock the ctable build directory
    set build_dir [workname $ctable_name]
    if {![lockfile $build_dir err]} {
      return -code error $err
    }

    #
    # Validate the version file. If it doesn't exist, or the vertsion doesn't
    # match, delete everything.
    #
    variable version
    set full_version [package version ctable]+$version
    set verfile [workname $ctable_name ver]

    if {[file exists $verfile]} {
      set fp [open $verfile r]
      set old_version [read -nonewline $fp]
      close $fp

      if {"$full_version" != "$old_version"} {
        trash_old_files $ctable_name
      }
    } else {
      trash_old_files $ctable_name
    }

    #
    # Validate the parameters. If the parameter file exists, but the
    # parameters are different from this call, delete everything. Note
    # that even minor changes are assumed fatal, so it's probably best
    # to have a single place you call init_ctable.
    #
    lappend tcl [namespace which init_ctable] $name $tables $where_clause

    foreach arg $args {
      lappend tcl $arg
    }

    set tclfile [workname $ctable_name tcl]

    if {[file exists $tclfile]} {
      set fp [open $tclfile r]
      set old_tcl [read -nonewline $fp]
      close $fp

      if {"$old_tcl" == "$tcl"} {
	unlockfile $build_dir
	return 1
      }
      trash_old_files $ctable_name
    }

    # Generate the SQL select for this
    set sql [gen_speedtable_sql_select $name $tables $where_clause $args]

    set sqlfile [workname $ctable_name sql]

    # Make sure auto_path goes through the build directory, so we can load
    # the built ctable.
    if {[lsearch $::auto_path $build_dir] == -1} {
      lappend ::auto_path $build_dir
    }

    set ctable_body [create_speedtable_definition $ctable_name $args]

    # The C extension name is c_xxx, the ctable class is also c_xxx, and the
    # package built from the C extension will be C_xxx. It's possible for the
    # C extension and ctable name to be different, we are simply not doing
    # that here because we're not putting multiple ctables in a single cext.
    #
    set cext_name [string totitle "c_$name"]

    # Once we start creating files, we need to completely trash whatever's
    # partially created if there's an error...
    #
    if {[catch {
      file mkdir $build_dir

      # These two statements create the generated ctable and compile it.
      CTableBuildPath $build_dir

      if {[catch [list speedtables $cext_name 1.1 $ctable_body] ctable_err] == 1} {
	error $ctable_err "$::errorInfo\n\tIn $ctable_body"
      }

      set fp [open $verfile w]
      puts $fp $full_version
      close $fp

      set fp [open $tclfile w]
      puts $fp $tcl
      close $fp

      set fp [open $sqlfile w]
      puts $fp $sql
      close $fp
    } err]} {
      unlockfile $build_dir
      trash_old_files $ctable_name
      error $err $::errorInfo
    }

    unlockfile $build_dir
    return 1
  }

  # create_speedtable_definition name columns
  #
  # Generate a speedtable definiton.
  #
  # This generates a ctable based on the columns and returns it
  # to the caller.
  #
  #   columns - list of column definitions. There must be at least two
  #             columns defined, the first is the ctable key, the rest are
  #             the fields of the ctable. If there is only one "column"
  #             argument, it's assumed to be a list of column arguments.
  #
  # Column entries are each a list of {field type expr ?name value?...}
  #
  #   field - field name
  #
  #   type - sql type
  #
  #   expr - sql expression to derive value
  #
  #   name value
  #      - ctable arguments for the field
  #
  # * Only the field name is absolutely required.
  #
  # from_table can generate these
  #
  # If the type is missing or blank, it's assumed to be varchar.
  # If the expression is missing or blank, it's assumed to be the same as
  #    the field name.
  # 
  proc create_speedtable_definition {tableName columns} {
    variable sql2speedtable

    # Validate arguments.
    if {"$tableName" == ""} {
      return -code error "Empty speedtable name"
    }

    #
    # Parse the columns: field, type, and expression are fixed, the ctable
    # options are variable length. There's no difference between an empty
    # element in the list and a missing one.
    #
    array unset options
    foreach arg $columns {
      set field ""; set type ""; set expr ""
      foreach {field type expr} $arg break

      if {[llength $arg] > 3} {
        set options($field) [lrange $arg 3 end]
      }

      if {"$type" == ""} {
	set type varchar
      }

      if {![info exists ctable_key]} {
        set ctable_key $field
      } else {
        lappend fields $field $type
      }

    }

    # Assemble the ctable definition as a list of lines, from the type-map
    # table (static), the options table (parsed), and the list of fields. 
    foreach {n t} $fields {
      set width ""

      # is it "something(n)"? handle those special cases
      if {[regexp {([^(]*)\([0-9]*} $t dummy baseType] == 1} {

	    # is it "charater(n)?"
	    if {[regexp {character\(([^)]*)} $t dummy count] == 1} {
	      set t "fixedstring"
	      set width " $count"

	    # is it "character varying(n)?"
            } elseif {[regexp {character varying} $t dummy] == 1} {
		set t "varstring"
	    } else {
		# none of the above, strip the () and try to keep going
		set t $baseType
	    }
      }

      # can we direct lookup this thing in our table?
      if {[info exists sql2speedtable($t)]} {
        set t $sql2speedtable($t)
      }

      if {[info exists options($n)]} {
	lappend ctable "$t\t[concat $n $width $options($n)];"
      } else {
        lappend ctable "$t\t$n$width;"
      }
    }

    return [format "    table %s {\n\t    %s\n    }" $tableName [join $ctable "\n\t    "]]
  }

  # gen_speedtable_sql_select name table_list where_clause ?columns|column...?
  #
  # ...generates new SQL to read the table.
  #
  #   name - base name of ctable
  #
  #   table_list - list of SQL tables to extract data from, if it's empty
  #             then use the name.
  #
  #   where_clause - SQL "WHERE" clause to limit selection, or an empty string
  #
  #   columns - list of column definitions.
  # 
  proc gen_speedtable_sql_select {name tables where_clause columns} {
    variable sql2speedtable

    #
    # Generate the SQL select for this
    #
    foreach column $columns {
      set field ""; set type ""; set expr ""
      foreach {field type expr} $column break

      if {"$expr" == ""} {
	lappend selected $field
      } else {
	lappend selected "$expr AS $field"
      }
    }

    # If the table name is blank, use the ctable name.
    if {![llength $tables]} {
      lappend tables $name
    }

    # 
    set sql "SELECT [join $selected ,] FROM [join $tables ,]"
    if {"$where_clause" != ""} {
      append sql " WHERE $where_clause"
    }
    append sql ";"

    return $sql
  }

  # create_sql_table table_name ?-temp? ?-tablespace tablespace? columns...
  #
  # Using the same column format as init_ctable, this creates an SQL table
  # to match.
  # 
  #   table_name - SQL table name
  #   columns - List of column val
  #   options:
  #     -temp
  #       create a temp table
  #     -tablespace tablespace
  #       create table in the specified tablespace
  #
  proc create_sql_table {table_name args} {
    set temp 0
    set tablespace ""
    while {[string match "-*" [set opt [lindex $args 0]]]} {
      set args [lrange $args 1 end]

      switch -exact -- $opt {
        -temp { set temp 1 }

        -tablespace {
	  set tablespace [lindex $args 0]
	  set args [lrange $args 1 end]
	}

	default {
	  return -code error "Unknown option $opt"
	}
      }
    }

    if {[llength $args] == 0} {
      return -code error "No columns specified"
    }

    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }

    if {[llength $args] <= 1} {
      return -code error "Not enough columns specified"
    }

    set create_sql "CREATE"
    if {$temp} {
      append create_sql " TEMP"
    }

    append create_sql " TABLE $table_name"

    foreach column $args {
      foreach {field type} $column { break }
      lappend code "$field $type"
    }

    append create_sql " ([join $code ", "])"
    if {"$tablespace" != ""} {
      append create_sql " TABLESPACE $tablespace"
    }

    append create_sql ";"

    exec_sql $create_sql
  }

  # open_cached name ?pattern? ?-option val?... ?option val...?
  #
  # Open an initialised ctable, maintaining a local cache of the underlying
  # SQL table in a .tsv file in the workdir.
  #
  # There is one positional option, ?pattern?. 
  #      Only read lines matching the pattern from the cache, if the cache is
  #      good.
  #
  # Options begin with a dash:
  #   -pat pattern
  #      Equivalent to the pattern positional option
  #
  #   -time cache_timeout
  #      Override the default cache timeout.
  #
  #   -col name
  #      Name of column in the SQL file that contains the last_changed time of
  #      each entry, if any.
  #
  #   -index field_name
  #      Name of a field to create an index on. Multiple -index are allowed.
  #
  # Options that don't begin with a dash are passed to the ctable create
  # command.
  #
  proc open_cached {name args} {
    variable sql2speedtable
    variable ctable2name
    variable time_column
    variable default_timeout

    # default arguments
    set pattern "*"
    set timeout $default_timeout
    set time_col ""
    set indices {}

    # Parse and validate
    if {[llength $args] & 1} {
      set pattern [lindex $args 0]
      set args [lrange $args 1 end]
    }

    set open_command [list open_raw_ctable $name]

    foreach {n v} $args {
      switch -glob -- $n {
	-pat* { set pattern $v }
        -tim* { set timeout $v }
	-col* { set time_col $v }
	-ind* { lappend indices $v }
	-* { return -code error "Unknown option '$n'" }
	default {
	   lappend open_command $n $v
	}
      }
    }

    # open_raw_ctable (see above) does all the heavy lifting of loading the
    # extension and creating the ctable instance.
    set ctable [eval $open_command]

    # we need to know this to find the tsv file and sql file
    set ctable_name "c_$name"

    # If we're indexing any indexible fields, create the indexes before loading
    # the table from cache or db, this improves locality and improves
    # performance measurably.
    #
    foreach list $indices {
      foreach i $list {
	# debug "$ctable index create $i 24"
	$ctable index create $i 24
      }
    }

    # If no file, we want the last read time to be 0 (Jan 1 1970)
    set last_read 0

    # Lock the tsv file.
    set tsv_file [workname $ctable_name tsv]

   # block for up to 10 minutes
    if {![lockfile $tsv_file err 600]} {
      return -code error $err
    }

    # If the tsv file exists, check to see if it's stale and how to update
    # it.
    if {[file exists $tsv_file]} {
      set file_time [file mtime $tsv_file]
      set stale_tsv_file 0; # Is the file recent enough to use?
      set update_from_db 0; # Do we need to update the file from the db

      if {[string length $time_col]} {
	set stale_tsv_file 0
	set update_from_db 1
        set last_read $file_time
      } elseif {!$timeout || $file_time + $timeout > [clock seconds]} {
	set stale_tsv_file 0
	set update_from_db 0
      } else {
	set stale_tsv_file 1
	set update_from_db 1
	debug "Removing stale $tsv_file"
      }

      # It's fresh enough to eat
      if {!$stale_tsv_file} {
	debug "Reading $ctable from $tsv_file"
        set fp [open $tsv_file r]

	# first line has the names of the fields in the order they were saved
        gets $fp line
        set fields [split $line "\t"]

	# Start assembling the ctable read_tabsep command
	set read_cmd [list $ctable read_tabsep $fp -quote escape]

	# If we only want a partial read, but we're doing an update, we need
	# to do a partial read anyway, so don't include the pattern for an
	# update
	if {"$pattern" != "*" && !$update_from_db} {
	  lappend read_cmd -glob $pattern
	}

	# Pull the trigger, and close the file.
        # debug "eval $read_cmd [lrange $fields 1 end]"
        eval $read_cmd [lrange $fields 1 end]
        close $fp

	# If we don't have to do an update, we're done.
        if {!$update_from_db} {
	  unlockfile $tsv_file
          set ctable2name($ctable) $ctable_name
          return $ctable
        }
      }
      # At this point, the file is stale OR it's been read into memory. In
      # either case we're not going to need this any more.
      file delete $tsv_file
    }

    # Grab the SQL for reading the file, and eliminate the inconceivable.
    set sql_file [workname $ctable_name sql]
    if {![file exists $sql_file]} {
      unlockfile $tsv_file
      return -code error "Uninitialised ctable $ctable_name: $sql_file not found"
    }
    set fp [open $sql_file r]
    set sql [read -nonewline $fp]
    close $fp

    # If we're doing an update, and last_read is non-zero, this will patch the
    # SQL we read to only pull in records since the last change.
    set sql [set_time_limit $sql $time_col $last_read]

    if {[catch {read_ctable_from_sql $ctable $sql} err]} {
      $ctable destroy
      unlockfile $tsv_file
      return -code error -errorinfo $::errorInfo $err
    }

    # We've read it, save it.
    save_ctable $ctable $tsv_file

    unlockfile $tsv_file

    # Remember some info that will be handy later on.
    set ctable2name($ctable) $ctable_name
    if {"$time_col" != ""} {
      set time_column($ctable) $time_col
    }

    return $ctable
  }

  #
  # gen_refresh_ctable_sql ctable ?time_col? ?last_read? ?err?
  #
  # Generate the SQL to select new and updated rows from SQL table 'table' 
  # using time_col.
  #
  # if last_read is non-zero use that rather than last modify time of the cache,
  # return success or failure if err variable name is provided.
  #
  proc gen_refresh_ctable_sql {ctable {time_col ""} {last_read 0} {_err ""}} {
    variable ctable2name
    variable time_column
    variable sql_cache

    if {"$_err" != ""} {
      upvar 1 $_err err
      set _err err
    }

    if {$time_col == ""} {
	if {[info exists time_column($ctable)]} {
	    set time_col $time_column($ctable)
	}
    }

    # validate parameters
    if {![info exists ctable2name($ctable)]} {
      set reason "$ctable: Not a cached ctable"
    } else {
      set ctable_name $ctable2name($ctable)
      set sql_file [workname $ctable_name sql]

      if {![file exists $sql_file]} {
        set reason "Uninitialised ctable $ctable_name: $sql_file not found"
      }
    }

    # If there's a reason to be unhappy return 0 or abend.
    if {[info exists reason]} {
      set err $reason

      if {"$_err" == ""} {
        return -code error $err
      }
      return 0
    }

    # Get the sql.
    if {[info exists sql_cache($ctable)]} {
        set sql $sql_cache($ctable)
    } else {
	set fp [open $sql_file r]
	set sql [read $fp]
	close $fp
	set sql_cache($ctable) $sql
    }

    # If they didn't tell us the last-read time, guess it from the tsv file.
    if {!$last_read} {
      if {[string length $time_col]} {
        set tsv_file [workname $ctable_name tsv]

	if {[file exists $tsv_file]} {
          set last_read [file mtime $tsv_file]
	}
      }
    }

    # Patch the sql with the last read time if possible, then go to the db
    set sql [set_time_limit $sql $time_col $last_read]
    return $sql
  }

  #
  # refresh_ctable ctable ?time_col? ?last_read? ?err?
  #
  # Update new rows from SQL table 'table' into ctable 'ctable' using time_col,
  # if last_read is non-zero use that rather than last modify time of the cache,
  # return success or failure if err variable name is provided.
  #
  proc refresh_ctable {ctable {time_col ""} {last_read 0} {_err ""}} {
    variable ctable2name
    variable time_column

    if {"$_err" != ""} {
      upvar 1 $_err err
      set _err err
    }

    set sql [gen_refresh_ctable_sql $ctable $time_col $last_read err]
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

    if {$last_read} {
      set time_val [clock2sqlgmt $last_read]
      set time_sql "$time_col > '$time_val'"
      # debug "Will add new entries since $time_val"

      if {[regexp -nocase { where } $sql]} {
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
    
    # Keep track of whether we locked the beggar.
    set locked 0

    # If the tsv file wasn't passed to us, get the lock 
    if {"$tsv_file" == ""} {
      if {![info exists ctable2name($ctable)]} {
        return -code error "$ctable: Not a cached table"
      }

      set tsv_file [workname $ctable2name($ctable) tsv]

      # reading and saving tsv files can take a while, so allow 10 minutes!
      if {![lockfile $tsv_file err 600]} {
        return -code error $err
      }

      set locked 1
    }

    debug "Writing $ctable to $tsv_file"
    set fp [open $tsv_file w]

    # Write the field names so we can recover the correct order to pull them
    # out later.
    puts $fp [join [concat _key [$ctable fields]] "\t"]

    # Pull the trigger
    $ctable write_tabsep $fp -quote escape
    close $fp

    if {$locked} {
      unlockfile $tsv_file
    }
  }

  # from_table table_name keys ?-option value?
  #
  # Generate a column list for init_ctable by querying the SQL database
  # for the table definition.
  #
  #    keys - a list of columns that define the key for the table
  #
  # Options:
  #   -with column
  #      Include column name in table. If any "-with" clauses are provided,
  #      only the named columns will be included
  #
  #   -without column
  #      Exclude column name from table. You must not provide both "-with"
  #      and "-without" options.
  #
  #   -index column
  #      Make this column indexable
  #
  #   -column {name type ?sql? ?args}
  #      Add an explicit derived column
  #
  #   -table name
  #      If specified, generate implicit column-name as "table.column"
  #
  #   -prefix text
  #      If specified, prefix column names with "$prefix"
  #
  proc from_table {table_name keys args} {
    set with {}
    set without {}
    set indices {}
    set extra_columns {}

    # read and validate options
    foreach {name value} $args {
      switch -- $name {
	-with { lappend with $value }
	-without { lappend without $value }
	-index { lappend indices $value }
	-column { lappend extra_columns $value }
	-table { set table $value }
	-prefix { set prefix $value }
	default {
	  return -code error "Unknown option '$name'"
	}
      }
    }

    if {[llength $with] && [llength $without]} {
      return -code error "Can not specify both '-with' and '-without'"
    }

    # Get the raw list of all columns in the table
    set raw_cols [better_get_columns $table_name]
    foreach "column type notnull" $raw_cols {
	set types($column) $type
    }

    set columns {}

    # If keys specified (not necessarily going to be any if we're building
    # a complex ctable using multiple SQL tables)

    if {[llength $keys]} {
      foreach key $keys {
        if {[info exists types($key)]} {
	  set sql_key $key
	  if {[info exists table]} {
	    set sql_key $table.$key
	  }
	  # bend over backwards, if it's nottext, MAKE it text.
	  if {"[string tolower $types($key)]" != "varchar"} {
	    set sql_key TEXT($sql_key)
	  }

	  lappend sql_keys $sql_key
        } else {
	  return -code error "Key '$key' not found in $table_name"
        }
      }

      if {[llength $sql_keys] < 2} {
          set keyString $sql_keys
      } else {
          set newList [list]
	  foreach element $sql_keys {
	      lappend newList "coalesce($element,'')"
	  }
	  set keyString [join $newList "||':'||"]
      }
      lappend columns [list _key "" $keyString]
    }

    # If we don't have "-with", then use "-with all"
    if {![llength $with]} {
      set with [array names types]
    }

    # If we have any "-column" entries, don't pull in the same column
    # from the raw columns. If we're prefixing the raw_columns, only
    # watch for the extra column if we can whack the prefix off the name.

    foreach column $extra_columns {
      set field [lindex $column 0]
      if {[info exists prefix]} {
        if {![regexp "^$prefix(.*)" $field _ field]} {
	  continue
	}
      }
      lappend without $field
    }

    # Step through the raw columns, checking that they're supossed to be
    # included (with) and not excluded (without), create the final field
    # name with the prefix if needed, create the final SQL for the column
    # with the "table." prefix if needed, and assemble a 2, 3, or 4+ element
    # list of {name type ?sql? ?options?}...

    foreach {raw_col type notnull} $raw_cols {
      if {[lsearch -exact $with $raw_col] == -1} {
	continue
      }

      if {[lsearch -exact $without $raw_col] != -1} {
	continue
      }

      set field $raw_col
      if {[info exists prefix]} {
	set field $prefix$field
      }

      set sql $raw_col
      if {[info exists table]} {
	set sql $table.$sql
      }

      unset -nocomplain options
      if {[lsearch -exact $indices $raw_col] != -1} {
	lappend options indexed 1
      }

      set column [list $field $type]
      if {$notnull} {
	  lappend options notnull 1
      }

      if {"$field" != "$sql"} {
	lappend column $sql
      } elseif {[info exists options]} {
	lappend column ""
      }

      if {[info exists options]} {
	set column [concat $column $options]
      }

      lappend columns $column
    }

    # debug "from_table --> [concat $columns $extra_columns]"
    return [concat $columns $extra_columns]
  }

  #
  # open_raw_ctable
  #
  # Open an initialized ctable but don't fetch anything from SQL, used
  # internally, and useful for temporary tables, copies, etcetera...
  # we lock the ctable while we're loading it to make sure some scurvy
  # beggar doesn't go gcc on us while we're slurping our dot-ohs.
  #
  proc open_raw_ctable {name args} {
    init

    set ctable_name c_$name

    # if the ctable-creating command already exists, skip most of the work
    if {[info commands $ctable_name] != ""} {
        set locked 0
    } else {
	# validate and lock the ctable
	set build_dir [workname $ctable_name]

	if {![lockfile $build_dir err]} {
	  return -code error $err
	}
	set locked 1

	if {![file isdir $build_dir]} {
	  unlockfile $build_dir
	  return -code error "Uninitialised ctable $ctable_name: $build_dir not found or not a directory"
	}

	# make sure the build directory is in my path
	if {[lsearch $::auto_path $build_dir] == -1} {
	  lappend ::auto_path $build_dir
	}

	# Pull the trigger and load the package
	namespace eval :: [list package require C_$name]
    }

    # Create a new ctable instance
    if {[catch {
      if {[llength $args]} {
        set ctable [eval [list $ctable_name create #auto master] $args]
      } else {
	set ctable [$ctable_name create #auto]
      }
    } err]} {
        if {$locked} {
	  unlockfile $build_dir
	}
      error $err $::errorInfo
    }

    if {$locked} {
      unlockfile $build_dir
    }
    return $ctable
  }

  # Invalidate the ctable the hard way
  proc trash_old_files {ctable_name} {
    foreach ext {ver sql tcl tsv ""} {
      file delete -force [workname $ctable_name $ext]
    }
  }

  # Create a working file name in the build root
  proc workname {name {ext ""}} {
    if {"$name" == ""} {
      return -code error "Invalid ctable name (null)"
    }

    variable build_root

    if {"$ext" != ""} {
      append name . $ext
    }
    return [file join $build_root $name]
  }

  # Just invalidate the cache
  proc remove_tsv_file {table_name} {
    set tsv_file [workname $table_name tsv]

    if {![file exists $tsv_file]} {
      set tsv_file [workname c_$table_name tsv]
    }

    catch {file delete -force $tsv_file}
  }

  # Invalidate the whole shooting match
  proc remove_tcl_file {table_name} {
    set tcl_file [workname $table_name tcl]

    if {![file exists $tcl_file]} {
      set tcl_file [workname c_$table_name tcl]
    }

    catch {file delete -force $tcl_file}
  }
}

package provide st_server 1.8.2
