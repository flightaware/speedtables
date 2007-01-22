# $Id$

package require scache_client
package require scache_pgtcl

namespace eval ::scache {
  variable sqltable_seq 0
  proc connect_sql {table {address "-"} args} {
    variable sqltable_seq

    set params ""
    regexp {^([^?]*)?(.*)} $table _ table params
    set path ""
    regexp {^/*([^/]*)/(.*)} $table _ table path
    set path [split $path "/"]

    foreach param [split $params "&"] {
      if [regexp {^([^=]*)=(.*)} $param _ name val] {
	set vars($name) $val
      } else {
	set vars($name) ""
      }
    }

    if {[info exists vars(_key)] || [info exists vars(_keys)]} {
      if {[lsearch $path _key] == -1} {
	set path [concat {_key} $path]
      }
    }

    set raw_fields {}
    foreach {name type} [get_columns $table] {
      lappend raw_fields $name
      set field2type($name) $type
    }

    if {[llength $path] > 1} {
      set raw_fields {}
      foreach field [split $path "/"] {
	if [regexp {^([^:]*):(.*)} $field _ name type] {
	  set field2type($field) $type
	}
        lappend raw_fields $field
      }
    }

    if [info exists vars(_keys)] {
      regsub -all {[+: ]+} $vars(_keys) ":" vars(_keys)
      set keys [split $vars(_keys) ":"]
      if {[llength $keys] == 1} {
	set vars(_key) [lindex $keys 0]
      } elseif {[llength $keys] > 1} {
	set list {}
        foreach field $keys {
	  if [info exists vars($field)] {
	    lappend list $vars($field)
	  } elseif {
		[info exists field2type($field)] &&
		![string match "CHAR" [string toupper $field2type($field)] &&
		![string match "TEXT" string toupper $field2type($field)]
	  } {
	    lappend list "TEXT($field)"
	  } else {
	    lappend list $field
	  }
	}
	set vars(_key) [join $keys "||"]
      }
    }

    foreach field $raw_fields {
      if {"$field" == "_key"} {
	set key _key
      } else {
	lappend fields $field
      }
      if [info exists params($field)] {
        set field2sql($field) $params($field)
	unset params($field)
      }
    }

    if ![info exists key] {
      set key [lindex $fields 0]
      # set fields [lrange $fields 1 end]
    }

    set ns ::scache::sqltable[incr sqltable_seq]

    namespace eval $ns {
      proc ctable {args} {
	set level [expr {[info level] - 1}]
	eval [list ::scache::sql_ctable $level [namespace current]] $args
      }

      # copy the search proc into this namespace
      proc search_to_sql [info args ::scache::search_to_sql] [info body ::scache::search_to_sql]
    }

    set ${ns}::table_name $table
    array set ${ns}::sql [array get field2sql]
    set ${ns}::key $key
    set ${ns}::fields $fields
    array set ${ns}::types [array get field2type]

    return ${ns}::ctable
  }
  register sql connect_sql

  variable ctable_commands
  array set ctable_commands {
    get				sql_ctable_get
    set				sql_ctable_set
    array_get			sql_ctable_unimplemented
    array_get_with_nulls	sql_ctable_agwn
    exists			sql_ctable_exists
    delete			sql_ctable_delete
    count			sql_ctable_count
    foreach			sql_ctable_foreach
    type			sql_ctable_type
    import			sql_ctable_unimplemented
    import_postgres_result	sql_ctable_unimplemented
    export			sql_ctable_unimplemented
    fields			sql_ctable_fields
    fieldtype			sql_ctable_fieldtype
    needs_quoting		sql_ctable_needs_quoting
    names			sql_ctable_names
    reset			sql_ctable_unimplemented
    destroy			sql_ctable_destroy
    search			sql_ctable_search
    search+			sql_ctable_search
    statistics			sql_ctable_unimplemented
    write_tabsep		sql_ctable_unimplemented
    read_tabsep			sql_ctable_read_tabsep
    index			sql_ctable_ignore_null
  }

  proc sql_ctable {level ns cmd args} {
    variable ctable_commands
    if ![info exists ctable_commands($cmd)] {
      set proc sql_ctable_unimplemented
    } else {
      set proc $ctable_commands($cmd)
    }
    return [eval [list $proc $level $ns $cmd] $args]
  }

  proc sql_ctable_unimplemented {level ns cmd args} {
    return -code error "Unimplemented command $cmd"
  }

  proc sql_ctable_ignore_null {args} {
    return ""
  }

  proc sql_ctable_ignore_true {args} {
    return 1
  }

  proc sql_ctable_ignore_false {args} {
    return 0
  }

  proc sql_ctable_get {level ns cmd val args} {
    if ![llength $args] {
      set args [set ${ns}::fields]
    }
    foreach arg $args {
      if [info exists ${ns}::sql($arg)] {
	lappend select [set ${ns}::sql($arg)]
      } else {
	lappend select $arg
      }
    }
    set sql "SELECT [join $select ,] FROM [set ${ns}::table_name]"
    append sql " WHERE [set ${ns}::key] = [pg_quote $val]"
    append sql " LIMIT 1;"
    return [sql_get_one_tuple $sql]
  }

  proc sql_ctable_agwn {level ns cmd val args} {
    if ![llength $args] {
      set args [set ${ns}::fields]
    }
    set vals [eval [list sql_ctable_get $level $ns $cmd] $args]
    foreach arg $args val $vals {
      lappend result $arg $val
    }
    return $result
  }

  proc sql_ctable_exists {level ns cmd val} {
    set sql "SELECT [set ${ns}::key] FROM [set ${ns}::table_name]"
    append sql " WHERE [set ${ns}::key] = [pg_quote $val]"
    append sql " LIMIT 1;"
    # debug "\[pg_exec \[conn] \"$sql\"]"
    set pg_res [pg_exec [conn] $sql]
    if {![string match "PGRES_*_OK" [pg_result $pg_res -status]]} {
      set pg_err [pg_result $pg_res -error]
      pg_result $pg_res -clear
      return -code error -errorinfo "$pg_err\nIn $sql" $pg_err
    }
    set result [pg_result $pg_res -numTuples]
    pg_result $pg_res -clear
    return $result
  }

  proc sql_ctable_count {level ns cmd args} {
    set sql "SELECT COUNT([set ${ns}::key]) FROM [set ${ns}::table_name]"
    if {[llength $args] == 1} {
      append sql " WHERE [set ${ns}::key] = [pg_quote $val]"
    }
    append sql ";"
    return [lindex [sql_get_one_tuple $sql] 0]
  }

  proc sql_ctable_fields {level ns cmd args} {
    return [set ${ns}::fields]
  }

  proc sql_ctable_type {level ns cmd args} {
    return sql:///[set ${ns}::table_name]
  }

  proc sql_ctable_fieldtype {level ns cmd field} {
    if ![info exists ${ns}::types($field)] {
      return -code error "No such field: $field"
    }
    return [set ${ns}::types($field)]
  }

  proc sql_ctable_search {level ns cmd args} {
    array set request $args
    if [info exists request(-array_get)] {
      return -code error "Unimplemented: search -array_get"
    }
    if [info exists request(-array)] {
      return -code error "Unimplemented: search -array"
    }
    if {[info exists request(-countOnly)] && $request(-countOnly) == 0} {
      unset request(-countOnly)
    }
    if {[info exists request(-countOnly)] && ![info exists request(-code)]} {
      return -code error "Must provide -code or -countOnly"
    }
    set sql [${ns}::search_to_sql request]
    if [info exists request(-countOnly)] {
      return [lindex [sql_get_one_tuple $sql] 0]
    }
    set code {}
    set array __array
    if [info exists request(-array_with_nulls)] {
      set array $request(-array_with_nulls)
    }
    if [info exists request(-array_get_with_nulls)] {
      lappend code "set $request(-array_get_with_nulls) \[array get $array]"
    }
    if [info exists request(-key)] {
      lappend code "set $request(-key) \$${array}(__key)"
    }
    lappend code $request(-code)
    # debug [list pg_select [conn] $sql $array [join $code "\n"]]
    uplevel #$level [list pg_select [conn] $sql $array [join $code "\n"]]
  }

  proc sql_ctable_destroy {level ns cmd args} {
    namespace delete $ns
  }

  proc sql_ctable_set {level ns cmd args} { sql_ctable_unimplemented }
  proc sql_ctable_foreach {level ns cmd args} { sql_ctable_unimplemented }
  proc sql_ctable_needs_quoting {level ns cmd args} { sql_ctable_unimplemented }
  proc sql_ctable_names {level ns cmd args} { sql_ctable_unimplemented }
  proc sql_ctable_read_tabsep {level ns cmd args} { sql_ctable_unimplemented }

  #
  # This is never evaluated directly, it's only copied into a namespace
  # with [info body], so variables are from $ns and anything in ::scache
  # needs direct quoting
  #
  proc search_to_sql {_request} {
    upvar 1 $_request request
    variable key
    variable table_name
    variable fields

    set select {}
    if [info exists request(-countOnly)] {
      lappend select "COUNT($key) AS count"
    } else {
      if [info exists request(-key)] {
	if [info exists sql($key)] {
	  lappend select "$sql($key) AS __key"
	} else {
          lappend select "$key AS __key"
	}
      }
      if [info exists request(-fields)] {
        set cols $request(fields)
      } else {
        set cols $fields
      }
  
      foreach col $cols {
        if [info exists sql($col)] {
	  lappend select "$sql($col) AS $col"
        } else {
	  lappend select $col
        }
      }
    }
  
    set where {}
    if [info exists request(-glob)] {
      lappend where "$key LIKE [quote_glob $request(-glob)"
    }
  
    if [info exists request(-compare)] {
      foreach tuple $request(-compare) {
	foreach {op col v1 v2} $tuple break
	if [info exists types($col)] {
	  set type $types($col)
	} else {
	  set type varchar
	}
	set q1 [pg_quote $v1]
	set q2 [pg_quote $v2]
  
	if [info exists sql($col)] {
	  set col $sql($col)
	}
	switch -exact -- [string tolower $op] {
	  false { lappend where "$col = FALSE" }
	  true { lappend where "$col = TRUE" }
	  null { lappend where "$col IS NULL" }
	  notnull { lappend where "$col IS NOT NULL" }
	  < { lappend where "$col < $q1" }
	  <= { lappend where "$col <= $q1" }
	  = { lappend where "$col = $q1" }
	  != { lappend where "$col <> $q1" }
	  >= { lappend where "$col >= $q1" }
	  > { lappend where "$col > $q1" }
	  match { lappend where "$col ILIKE [::scache::quote_glob $v1]" }
	  match_case { lappend where "$col LIKE [::scache::quote_glob $v1]" }
	  range {
	    lappend where "$col >= $q1"
	    lappend where "$col < [pg_quote $v2]"
	  }
	  in {
	    foreach v [lrange $tuple 2 end] {
	      lappend q [pg_quote $v]
	    }
	    lappend where "$col IN ([join $q ","])"
	  }
	}
      }
    }
  
    set order {}
    if [info exists request(-sort)] {
      foreach field $request(-sort) {
	set desc ""
	if [regexp {^-(.*)} $field _ field] {
	  set desc " DESC"
	}
	if [info exists sql(field)] {
	  lappend order "$sql($field)$desc"
	} else {
	  lappend order "$field$desc"
	}
      }
    }
  
    set sql "SELECT [join $select ","] FROM $table_name"
    if [llength $where] {
      append sql " WHERE [join $where " AND "]"
    }
    if [llength $order] {
      append sql " ORDER BY [join $order ","]"
    }
    if [info exists request(-limit)] {
      append sql " LIMIT $request(-limit)"
    }
    if [info exists request(-offset)] {
      append sql " OFFSET $request(-offset)"
    }
    append sql ";"
  
    return $sql
  }

  proc sql_get_one_tuple {request} {
    # debug "\[pg_exec \[conn] \"$request\"]"
    set pg_res [pg_exec [conn] $request]
    if {![string match "PGRES_*_OK" [pg_result $pg_res -status]]} {
      set pg_err [pg_result $pg_res -error]
      if {"$pg_err" == ""} {
	set pg_err [pg_result $pg_res -status]
      }
    } elseif {[pg_result $pg_res -numTuples] == 0} {
      set pg_err "No match"
    } else {
      set result [pg_result $pg_res -getTuple 0]
    }
    pg_result $pg_res -clear
    if [info exists pg_err] {
      return -code error -errorinfo "$pg_err\nIn $request" $pg_err
    }	
    return $result
  }

  proc quote_glob {pattern} {
    regsub -all {[%_]} $pattern {\\&} pattern
    regsub -all {@} $pattern {@%} pattern
    regsub -all {\\[*]} $pattern @_ pattern
    regsub -all {[*]} $pattern "%" pattern
    regsub -all {@_} $pattern {*} pattern
    regsub -all {\\[?]} $pattern @_ pattern
    regsub -all {[?]} $pattern "_" pattern
    regsub -all {@_} $pattern {?} pattern
    regsub -all {@%} $pattern {@} pattern
    return [pg_quote $pattern]
  }
}

package provide scache_sql_client 1.0
