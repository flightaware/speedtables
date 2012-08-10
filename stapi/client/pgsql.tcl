#
# STAPI PostgreSQL Client
#
# This stuff adds sql:// as a stapi URI and provides a way to look at
# PostgreSQL tables as if they are ctables
#

package require st_client
package require st_postgres

namespace eval ::stapi {
  #
  # make_sql_uri - given a table name and some optional arguments like
  #  host, user, pass, db, keys, and key, construct a sql URI that
  #  looks like sql://...
  #
  proc make_sql_uri {table args} {
    while {[llength $args]} {
      set arg [lindex $args 0]
      set args [lrange $args 1 end]

      if {![regexp {^-(.*)} $arg _ opt]} {
	lappend cols [uri_esc $arg /?]
      } else {
	set val [lindex $args 0]
	set args [lrange $args 1 end]

        switch -- $opt {
	  cols {
	    foreach col $val {
	      lappend cols [uri_esc $col /?]
	    }
	  }

	  host {
	      set host [uri_esc $val @/:]
	  }

	  user {
	      set user [uri_esc $val @/:]
	  }

	  pass {
	      set pass [uri_esc $val @/:]
	  }

	  db {
	      set db [uri_esc $val @/:]
	  }

	  keys {
	      lappend params [uri_esc _keys=[join $val :] &]
	  }

	  key {
	      lappend params [uri_esc _key=$val &]
	  }

	  -* {
	    regexp {^-(.*)} $opt _ opt
	    lappend params [uri_esc $opt &=]=[uri_esc $val &]
	  }

	  * {
	    lappend params [uri_esc $opt &=]=[uri_esc $val &]
	  }
	}
      }
    }

    set uri sql://
    if {[info exists user]} {
      if {[info exists pass]} {
	append user : $pass
      }

      append uri $user @
    }

    if {[info exists host]} {
      append uri $host :
    }

    if {[info exists db]} {
      append uri $db
    }

    append uri / [uri_esc $table /?]
    if {[info exists cols]} {
      append uri / [join $cols /]
    }

    if {[info exists params]} {
      append uri ? [join $params &]
    }
    return $uri
  }

  #
  # uri_esc - escape a string i think for passing in a URI/URL
  #
  proc uri_esc {string {extra ""}} {
	  if {[catch {escape_string $string} result] == 0} {
		  # we were running under Apache Rivet and could use its existing command.
		  return $result
	  } else {
		  # TODO: this is not very good and is probably missing some cases.
		  foreach c [split "%\"'<> $extra" ""] {
			  scan $c "%c" i
			  regsub -all "\[$c]" $string [format "%%%02X" $i] string
		  }
		  return $string
	  }
  }

  #
  # uri_unesc - unescape a string after passing it through a URI/URL
  #
  proc uri_unesc {string} {
	  if {[catch {unescape_string $string} result] == 0} {
		  # we were running under Apache Rivet and could use its existing command.
		  return $result
	  } else {
		  # TODO: this is not very good and is probably missing some cases.
		  foreach c [split {\\$[} ""] {
			  scan $c "%c" i
			  regsub -all "\\$c" $string [format "%%%02X" $i] string
		  }
		  regsub -all {%([0-9A-Fa-f][0-9A-Fa-f])} $string {[format %c 0x\1]} string
		  return [subst $string]
	  }
  }

  variable sqltable_seq 0

  #
  # connect_pgsql - connect to postgres by cracking a sql uri
  #
  proc connect_pgsql {table {address "-"} args} {
    variable sqltable_seq

    set params ""
    regexp {^([^?]*)[?](.*)} $table _ table params
    set path ""
    regexp {^/*([^/]*)/(.*)} $table _ table path
    set path [split $path "/"]
    set table [uri_unesc $table]

    foreach param [split $params "&"] {
      if {[regexp {^([^=]*)=(.*)} $param _ name val]} {
	set vars([uri_unesc $name]) [uri_unesc $val]
      } else {
	set vars([uri_unesc $name]) ""
      }
    }

    set raw_fields {}
    foreach {name type} [get_columns $table] {
      lappend raw_fields $name
      set field2type($name) $type
    }

    if {[llength $path]} {
      set raw_fields {}
      foreach field $path {
	set field [uri_unesc $field]

	if {[regexp {^([^:]*):(.*)} $field _ field type]} {
	  set field2type($field) $type
	}
        lappend raw_fields $field
      }
    }

    # If the key is a simple column name, remember it and eliminate _key
    if {[info exists vars(_key)]} {
      if {[lsearch $raw_fields $vars(_key)] != -1} {
	set key $vars(_key)
	unset vars(_key)
      }
    }

    if {[info exists vars(_key)] || [info exists vars(_keys)]} {
      if {[lsearch $path _key] == -1} {
	set raw_fields [concat {_key} $raw_fields]
      }
    }

    if {[info exists vars(_keys)]} {
      regsub -all {[+: ]+} $vars(_keys) ":" vars(_keys)
      set keys [split $vars(_keys) ":"]

      if {[llength $keys] == 1} {
	set vars(_key) [lindex $keys 0]
      } elseif {[llength $keys] > 1} {
	set list {}

        foreach field $keys {
	  if {[info exists vars($field)]} {
	    lappend list $vars($field)
	  } else {
	    set type varchar

	    if {[info exists field2type($field)]} {
	      set type $field2type($field)
	    }

	    if {"$type" == "varchar" || "$type" == "text"} {
	      lappend list $field
	    } else {
	      lappend list TEXT($field)
	    }

	  }
	}

	if {[llength $list] < 2} {
	    set vars(_key) $list
	} else {
	    set newList [list]
	    foreach element $list {
	        lappend newList "coalesce($list,'')"
	    }
	    set vars(_key) [join $newList "||':'||"]
	}
      }
    }

    foreach field $raw_fields {
      if {"$field" == "_key"} {
	set key $vars(_key)
      } else {
	lappend fields $field
      }

      if {[info exists params($field)]} {
        set field2sql($field) $params($field)
	unset params($field)
      }
    }

    # last ditch - use first field in table
    if {![info exists key]} {
      set key [lindex $fields 0]
      # set fields [lrange $fields 1 end]
    }

    set ns ::stapi::sqltable[incr sqltable_seq]

    namespace eval $ns {
      #
      # ctable - 
      #
      proc ctable {args} {
	set level [expr {[info level] - 1}]
	eval [list ::stapi::sql_ctable $level [namespace current]] $args
      }

      # copy the search proc into this namespace
      proc search_to_sql [info args ::stapi::search_to_sql] [info body ::stapi::search_to_sql]
    }

    set ${ns}::table_name $table
    array set ${ns}::sql [array get field2sql]
    set ${ns}::key $key
    set ${ns}::fields $fields
    array set ${ns}::types [array get field2type]

    return ${ns}::ctable
  }
  register sql connect_pgsql

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
  variable ctable_extended_commands
  array set ctable_extended_commands {
    methods			sql_ctable_methods
    key				sql_ctable_key
    keys			sql_ctable_keys
    makekey			sql_ctable_makekey
    store			sql_ctable_store
  }

  #
  # sql_ctable -
  #
  proc sql_ctable {level ns cmd args} {
    variable ctable_commands
    variable ctable_extended_commands

    if {[info exists ctable_commands($cmd)]} {
      set proc $ctable_commands($cmd)
    } elseif {[info exists ctable_extended_commands($cmd)]} {
      set proc $ctable_extended_commands($cmd)
    } else {
      set proc sql_ctable_unimplemented
    }

    return [eval [list $proc $level $ns $cmd] $args]
  }

  #
  # sql_ctable_methods -
  #
  proc sql_ctable_methods {level ns cmd args} {
    variable ctable_commands
    variable ctable_extended_commands

    return [
      lsort [
        concat [array names ctable_commands] \
	       [array names ctable_extended_commands]
      ]
    ]
  }

  #
  # sql_ctable_key - 
  #
  proc sql_ctable_key {level ns cmd args} {
    set keys [set ${ns}::key]
    if {[llength $keys] == 1} {
      return [lindex $keys 0]
    } else {
      return "_key"
    }
  }

  #
  # sql_ctable_keys -
  #
  proc sql_ctable_keys {level ns cmd args} {
    return [set ${ns}::key]
  }

  #
  # sql_ctable_makekey
  #
  proc sql_ctable_makekey {level ns cmd args} {
    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }

    array set array $args
    set key [set ${ns}::key]

    if {[info exists array($key)]} {
      return $array($key)
    }

    if {[info exists array(_key)]} {
      return $array(_key)
    }
    return -code error "No key in list"
  }

  #
  # sql_ctable_unimplemented
  #
  proc sql_ctable_unimplemented {level ns cmd args} {
    return -code error "Unimplemented command $cmd"
  }

  #
  # sql_ctable_ignore_null
  #
  proc sql_ctable_ignore_null {args} {
    return ""
  }

  #
  # sql_ctable_ignore_true
  #
  proc sql_ctable_ignore_true {args} {
    return 1
  }

  #
  # sql_ctable_ignore_false
  #
  proc sql_ctable_ignore_false {args} {
    return 0
  }

  #
  # sql_create_sql
  #
  proc sql_create_sql {ns val slist} {
    if {![llength $slist]} {
      set slist [set ${ns}::fields]
    }

    foreach arg $slist {
      if {[info exists ${ns}::sql($arg)]} {
	lappend select [set ${ns}::sql($arg)]
      } else {
	lappend select $arg
      }
    }

    set sql "SELECT [join $select ,] FROM [set ${ns}::table_name]"
    append sql " WHERE [set ${ns}::key] = [pg_quote $val]"
    append sql " LIMIT 1;"

    return $sql
  }

  #
  # sql_ctable_get - implement ctable set operation on a postgres table
  #
  # Get list - return empty list for no data, SQL error is error
  #
  proc sql_ctable_get {level ns cmd val args} {
    set sql [sql_create_sql $ns $val $args]
    set result ""

    if {![sql_get_one_tuple $sql result]} {
      error $result
    }

    return $result
  }

  #
  # sql_ctable_agwn
  #
  # Get name-value list - return empty list for no data, SQL error is error
  #
  proc sql_ctable_agwn {level ns cmd val args} {
    set sql [sql_create_sql $ns $val $args]
    set result {}

    switch -- [sql_get_one_tuple $sql vals] {
      1 {
        foreach arg $args val $vals {
          lappend result $arg $val
        }
      }
      0 { error $vals }
    }

    return $result
  }

  #
  # sql_ctable_exists - implement a ctable exists method for SQL tables
  #
  proc sql_ctable_exists {level ns cmd val} {
    set sql "SELECT [set ${ns}::key] FROM [set ${ns}::table_name]"
    append sql " WHERE [set ${ns}::key] = [pg_quote $val]"
    append sql " LIMIT 1;"
    # debug "\[pg_exec \[conn] \"$sql\"]"

    set pg_res [pg_exec [conn] $sql]
    if {![set ok [string match "PGRES_*_OK" [pg_result $pg_res -status]]]} {
      set err [pg_result $pg_res -error]
      set errinf "$err\nIn $sql"
    } else {
      set result [pg_result $pg_res -numTuples]
    }

    pg_result $pg_res -clear

    if {!$ok} {
      return -code error -errorinfo $errinf $err
    }
    return $result
  }

  #
  # sql_ctable_count - implement a ctable count method for SQL tables
  #
  proc sql_ctable_count {level ns cmd args} {
    set sql "SELECT COUNT([set ${ns}::key]) FROM [set ${ns}::table_name]"

    if {[llength $args] == 1} {
      append sql " WHERE [set ${ns}::key] = [pg_quote $val]"
    }

    append sql ";"
    return [lindex [sql_get_one_tuple $sql] 0]
  }

  #
  # sql_ctable_fields - implement a ctables fields method for SQL tables
  #
  proc sql_ctable_fields {level ns cmd args} {
    return [set ${ns}::fields]
  }

  #
  # sql_ctable_type - implement a ctables "type" method for SQL tables
  #
  proc sql_ctable_type {level ns cmd args} {
    return sql:///[set ${ns}::table_name]
  }

  #
  # sql_ctable_fieldtype - implement a ctables "fieldtype" method for SQL tables
  #
  proc sql_ctable_fieldtype {level ns cmd field} {
    if {![info exists ${ns}::types($field)]} {
      return -code error "No such field: $field"
    }
    return [set ${ns}::types($field)]
  }

  #
  # sql_ctable_search - implement a ctable search method for SQL tables
  #
  proc sql_ctable_search {level ns cmd args} {
    array set search $args

    if {![info exists search(-code)] &&
	![info exists search(-key)] &&
	![info exists search(-array)] &&
	![info exists search(-array_get)] &&
	![info exists search(-array_get_with_nulls)] &&
	![info exists search(-array_with_nulls)]} {
	set search(-countOnly) 1
    }

    set sql [${ns}::search_to_sql search]
    if {[info exists search(-countOnly)]} {
      return [lindex [sql_get_one_tuple $sql] 0]
    }

    set code {}
    set array ${ns}::select_array

    if {[info exists search(-array)]} {
        set array $search(-array)
    }
    if {[info exists search(-array_with_nulls)]} {
      set array $search(-array_with_nulls)
    }

    if {[info exists search(-array_get_with_nulls)]} {
      lappend code "set $search(-array_get_with_nulls) \[array get $array]"
    }

    if {[info exists search(-array_get)]} {
      lappend code "set $search(-array_get) \[array get $array]"
    }

    if {[info exists search(-key)]} {
      lappend code "set $search(-key) \$${array}(__key)"
    }

    lappend code $search(-code)
    lappend code "incr ${ns}::select_count"
    set ${ns}::select_count 0

    set selectCommand [list pg_select]
    if {[info exists search(-array)] || [info exists search(-array_get)]} {
        lappend selectCommand "-withoutnulls"
    }
    lappend selectCommand [conn] $sql $array [join $code "\n"]

    #puts stderr "sql_ctable_search level $level ns $ns cmd $cmd args $args: selectCommand is $selectCommand"

    uplevel #$level $selectCommand
    return [set ${ns}::select_count]
  }

  #
  # sql_ctable_foreach - implement a ctable foreach method for SQL tables
  #
  proc sql_ctable_foreach {level ns cmd keyvar value code} {
    set sql "SELECT [set ${ns}::key] FROM [set ${ns}::table_name]"
    append sql " WHERE [set ${ns}::key] ILIKE [::stapi::quote_glob $val];"
    set code "set $keyvar \[lindex $__key 0]\n$code"
    uplevel #$level [list pg_select [conn] $sql __key $code]
  }

  #
  # sql_ctable_destroy - implement a ctable destroy method for SQL tables
  #
  proc sql_ctable_destroy {level ns cmd args} {
    namespace delete $ns
  }

  #
  # sql_ctable_delete - implement a ctable delete method for SQL tables
  #
  proc sql_ctable_delete {level ns cmd key args} {
    set sql "DELETE FROM [set ${ns}::table_name] WHERE [set ${ns}::key] = [pg_quote $key];"
    return [exec_sql $sql]
  }

  #
  # sql_ctable_set - implement a ctable set method for SQL tables
  #
  proc sql_ctable_set {level ns cmd key args} {
    if {![llength $args]} {
      return
    }

    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }

    foreach {col value} $args {
      if {[info exists ${ns}::sql($col)]} {
	set col [set ${ns}::sql($col)]
      }

      lappend assigns "$col = [pg_quote $value]"
      lappend cols $col
      lappend vals [pg_quote $value]
    }

    set sql "UPDATE [set ${ns}::table_name] SET [join $assigns ", "]"
    append sql " WHERE [set ${ns}::key] = [pg_quote $key];"
    set rows 0

    if {![exec_sql_rows $sql rows]} {
      return 0
    }

    if {$rows > 0} {
      return 1
    }
    set sql "INSERT INTO [set ${ns}::table_name] ([join $cols ","]) VALUES ([join $vals ","]);"
    return [exec_sql $sql]
  }

  #
  # sql_ctable_store - implement a ctable store method for SQL tables
  #
  proc sql_ctable_store {level ns cmd args} {
    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }
    return [
      eval [list sql_ctable_set $level $ns $cmd [
	sql_ctable_makekey $level $ns $cmd $args
      ]] $args
    ]
  }

  #
  # sql_ctable_needs_quoting
  #
  proc sql_ctable_needs_quoting {level ns cmd args} { sql_ctable_unimplemented }

  #
  # sql_ctable_names
  #
  proc sql_ctable_names {level ns cmd args} { sql_ctable_unimplemented }

  #
  # sql_ctable_read_tabsep
  #
  proc sql_ctable_read_tabsep {level ns cmd args} { sql_ctable_unimplemented }

  #
  # search_to_sql
  #
  # This is never evaluated directly, it's only copied into a namespace
  # with [info body], so variables are from $ns and anything in ::stapi
  # needs direct quoting
  #
  proc search_to_sql {_req} {
    upvar 1 $_req req
    variable key
    variable table_name
    variable fields

    set select {}
    if {[info exists req(-countOnly)]} {
      lappend select "COUNT($key) AS count"
    } else {
      if {[info exists req(-key)]} {
	if {[info exists sql($key)]} {
	  lappend select "$sql($key) AS __key"
	} else {
          lappend select "$key AS __key"
	}
      }

      if {[info exists req(-fields)]} {
        set cols $req(-fields)
      } else {
        set cols $fields
      }
  
      foreach col $cols {
        if {[info exists sql($col)]} {
	  lappend select "$sql($col) AS $col"
        } else {
	  lappend select $col
        }
      }
    }
  
    set where {}
    if {[info exists req(-glob)]} {
      lappend where "$key LIKE [quote_glob $req(-glob)]"
    }
  
    if {[info exists req(-compare)]} {
      foreach tuple $req(-compare) {
	foreach {op col v1 v2} $tuple break

	if {[info exists types($col)]} {
	  set type $types($col)
	} else {
	  set type varchar
	}

	set q1 [pg_quote $v1]
	set q2 [pg_quote $v2]
  
	if {[info exists sql($col)]} {
	  set col $sql($col)
	}

	switch -exact -- [string tolower $op] {
	  false {
	      lappend where "$col = FALSE"
	  }

	  true {
	      lappend where "$col = TRUE"
	  }

	  null {
	      lappend where "$col IS NULL"
	  }

	  notnull {
	      lappend where "$col IS NOT NULL"
	  }

	  < {
	      lappend where "$col < $q1"
	  }

	  <= {
	      lappend where "$col <= $q1"
	  }

	  = {
	      lappend where "$col = $q1"
	  }

	  != {
	      lappend where "$col <> $q1"
	  }

	  <> {
	      lappend where "$col <> $q1"
	  }

	  >= {
	      lappend where "$col >= $q1"
	  }

	  > {
	      lappend where "$col > $q1"
	  }

	  imatch {
	      lappend where "$col ILIKE [::stapi::quote_glob $v1]"
	  }

	  -imatch {
	      lappend where "NOT $col ILIKE [::stapi::quote_glob $v1]"
	  }

	  match {
	      lappend where "$col ILIKE [::stapi::quote_glob $v1]"
	  }

	  notmatch {
	      lappend where "NOT $col ILIKE [::stapi::quote_glob $v1]"
	  }

	  xmatch {
	      lappend where "$col LIKE [::stapi::quote_glob $v1]"
	  }

	  -xmatch {
	      lappend where "NOT $col LIKE [::stapi::quote_glob $v1]"
	  }

	  match_case {
	      lappend where "$col LIKE [::stapi::quote_glob $v1]"
	  }

	  notmatch_case {
	    lappend where "NOT $col LIKE [::stapi::quote_glob $v1]"
	  }

	  umatch {
	    lappend where "$col LIKE [::stapi::quote_glob [string toupper $v1]]"
	  }

	  -umatch {
	    lappend where "NOT $col LIKE [
				::stapi::quote_glob [string toupper $v1]]"
	  }

	  lmatch {
	    lappend where "$col LIKE [::stapi::quote_glob [string tolower $v1]]"
	  }

	  -lmatch {
	    lappend where "NOT $col LIKE [
				::stapi::quote_glob [string tolower $v1]]"
	  }

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
    if {[info exists req(-sort)]} {
      foreach field $req(-sort) {
	set desc ""

	if {[regexp {^-(.*)} $field _ field]} {
	  set desc " DESC"
	}

	if {[info exists sql(field)]} {
	  lappend order "$sql($field)$desc"
	} else {
	  lappend order "$field$desc"
	}
      }
    }
  
    # NB include a space for load balancing - total kludge, please remove asap
    set sql " SELECT [join $select ","] FROM $table_name"

    if {[llength $where]} {
      append sql " WHERE [join $where " AND "]"
    }

    if {[llength $order]} {
      append sql " ORDER BY [join $order ","]"
    }

    if {[info exists req(-limit)]} {
      append sql " LIMIT $req(-limit)"
    }

    if {[info exists req(-offset)]} {
      append sql " OFFSET $req(-offset)"
    }

    append sql ";"

  
    return $sql
  }

  #
  # sql_get_one_tuple
  #
  # Get one tuple from request
  # Two calling sequences:
  #   set result [sql_get_one_tuple $sql]
  #      No data is an error (No Match)
  #   set status [sql_set_one_tuple $sql result]
  #      status ==  1 - success
  #      status == -1 - No data,  *result not modified*
  #      status ==  0 - SQL error, result is error string
  #
  proc sql_get_one_tuple {req {_result ""}} {
    if {[string length $_result]} {
      upvar 1 $_result result
    }

    set pg_res [pg_exec [conn] $req]

    if {![set ok [string match "PGRES_*_OK" [pg_result $pg_res -status]]]} {
      set err [pg_result $pg_res -error]
    } elseif {[pg_result $pg_res -numTuples] == 0} {
      set ok -1
    } else {
      set result [pg_result $pg_res -getTuple 0]
    }

    pg_result $pg_res -clear

    if {[string length $_result]} {
      if {$ok == 0} {
	set result $err
      }
      return $ok
    }
      
    if {$ok <= 0} {
      set errinf "$err\nIn $req"
      return -code error -errorinfo $errinf $err
    }

    return $result
  }

  #
  # quote_glob - 
  #
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

  #
  # connect_sql
  #
  # Helper routine to shortcut the business of creating a URI and connecting
  # with the same keys. Using this implicitly pulls in stapi::extend inside connect
  # if it hasn't already been pulled in.
  #
  # Eg: ::stapi::connect_sql my_table {index} -cols {index name value}
  #
  proc connect_sql {table keys args} {
    lappend make make_sql_uri $table -keys $keys
    set uri [eval $make $args]
    return [connect $uri -keys $keys]
  }
}

package provide st_client_postgres 1.8.2
