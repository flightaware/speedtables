#
# STAPI Cassandra Client
#
# This stuff adds cass:// as a stapi URI and provides a way to look at
# Cassandra tables as if they are ctables
#

package require casstcl
package require st_client
package require st_client_uri

namespace eval ::stapi {
  variable cassconn

  #
  # set_cassandra_connection connect-info
  #
  # connection info is either a list of name value pairs or multiple name-value pairs. Missing
  # values will be provided from the environment.
  #
  # -user username	($CASSTCL_USERNAME)
  # -host hostname	($CASSTCL_CONTACT_POINTS)
  # -pass password	($CASSTCL_PASSWORD)
  # -port port
  #
  # Connection is set in the variable specified
  #
  proc set_cassandra_connection {_conn args} {
    upvar 1 $_conn conn
    global env

    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }

    set hosts {}
    foreach {opt val} $args {
      regexp {^-(.*)} $opt _ opt
      switch -- $opt {
        contact_points {lappend hosts $val}
	host {lappend hosts $val}
        user {set user $val}
        pass {set pass $val}
	port {set port $val}
        
      }
    }
    if {![llength $hosts]} {
      if {[info exists env(CASSTCL_CONTACT_POINTS)]} {
	foreach host [split $env(CASSTCL_CONTACT_POINTS) ":"] {
	  lappend hosts $host
	}
      } else {
	error "No host provided for cassandra connection"
      }
    }
    if {![info exists user]} {
      if {[info exists env(CASSTCL_USERNAME)]} {
	set user $env(CASSTCL_USERNAME)
      } else {
	error "No user-name provided for cassandra connection"
      }
    }
    if {![info exists pass]} {
      if {[info exists env(CASSTCL_PASSWORD)]} {
	set pass $env(CASSTCL_PASSWORD)
      }
    }

    lappend cmd ::casstcl::connect
    lappend cmd -user $user
    if {[info exists port]} { lappend cmd -port $port }
    if {[info exists pass]} { lappend cmd -password $pass }
    foreach host $hosts {
      lappend cmd -host $host
    }
    set conn [eval $cmd]
  }

  #
  # Return cass connection for the specified namespace, fallback to shared
  #
  proc cass {{ns ""}} {
    # Return namespace connection if set
    if {[string length $ns]} {
      if {[info exists ${ns}::cassconn]} {
	return [set ${ns}::cassconn]
      }
    }

    # Pull in shared connection
    variable cassconn

    if {![info exists casscon]} {
      # Hope the environment variables are all there!
      set_cassandra_connection cassconn
    }

    return $cassconn
  }
   
  #
  # make_cass_uri - given a table name and some optional arguments like
  #  host, user, pass, db, keys, and key, construct a cassandra URI that
  #  looks like cass://...
  #
  proc make_cass_uri {table args} {
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

	  host { # Cassandra contact points can have multiple values. host is an alias for contact point
	      lappend contact_points [uri_esc $val @/:]
	  }

	  contact_point {
	      lappend contact_points [uri_esc $val @/:]
	  }

	  user {
	      set user [uri_esc $val @/:]
	  }

	  pass {
	      set pass [uri_esc $val @/:]
	  }

	  port {
	      set port [uri_esc $val @/:]
	  }

	  keys {
	      lappend params [uri_esc _keys=[join $val :] &]
	  }

	  key {
	      lappend params [uri_esc _key=$val &]
	  }

	  keyspace {
	      set keyspace $val
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

    if {[info exists keyspace]} {
      regexp {^[^.]*[.]\(.*\)$} $table _ table
      set table "$keyspace.$table"
    }

    if {![string match "*.*" $table]} {
      error "No keyspace provided for cassandra table $table."
    }

    set uri cass://
    if {[info exists user]} {
      if {[info exists pass]} {
	append user : $pass
      }

      append uri $user @
    }

    if {[info exists contact_points]} {
      append uri [join $contact_points ","] :
    }

    if {[info exists port]} {
      append uri $port
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
  # parse_cass_address address
  #
  # converts "user:pass@host1,host2:port" to {-host host1 -host host2 -user user -pass pass -port port}
  #
  proc parse_cass_address {address} {
    set connection {}

    if {[regexp {^\(.*\)@\(.*\)$} $address _ user address]} {
      if {[regexp {^\(.*\):\(.*\)$} $user _ user pass]} {
	lappend connection -pass $pass
      }
      lappend connection -user $user
    }

    if {[regexp {\(.*\):\(.*\)$} $address _ address port]} {
      lappend connection -port $port
    }

    foreach host [split $address ","] {
      lappend connection -host $host
    }

    return $connection
  }

  variable casstable_seq 0

  #
  # cass_get_columns table_name ?keyspace_name?
  #
  # Returns a list of triples {{column_name kind type} ...}
  #
  # Kind is "regular", "clustering", or "partition_key"
  #
  # Type is CQL type
  #
  proc cass_get_columns {ns table_name {keyspace_name ""}} {
    if {![string length $keyspace_name]} {
      set l [split $table_name "."]
      if {[llength $l] != 2} {
	error "Keyspace not provided for $table_name"
      }
      set keyspace_name [lindex $l 0]
      set table_name [lindex $l 1]
    }
    set query "SELECT column_name, kind, type
                 FROM system_schema.columns
                 WHERE keyspace_name = '$keyspace_name' and table_name = '$table_name';"

    set result {}
    [cass $ns] select $query row {
	lappend result [list $row(column_name) $row(kind) $row(type)]
    }

    return $result
  }

  #
  # connect_cassandra - connect to cassandra by cracking a cass:// uri
  #
  proc connect_cassandra {table {address "-"} args} {
    variable casstable_seq
    set ns ::stapi::casstable[incr casstable_seq]
    set keysep ":"

    # Parse local part into table, path (list of columns), and parameters
    set params ""
    regexp {^([^?]*)[?](.*)} $table _ table params
    set path ""
    regexp {^/*([^/]*)/(.*)} $table _ table path
    set path [split $path "/"]
    set table [uri_unesc $table]

    if {![string match "*.*" $table]} {
      error "No keyspace provided for cassandra table $table."
    }

    # parse address part into user/host/password etc and make Cassandra connection
    set conninfo [parse_cass_address $address]
    if {![llength $conninfo]} {
      variable cassconn
      set_cassandra_connection cassconn
    } else {
      namespace eval $ns {
        variable cassconn
      }

      set_cassandra_connection ${ns}::cassconn $conninfo
    }

    foreach param [split $params "&"] {
      if {[regexp {^([^=]*)=(.*)} $param _ name val]} {
	set name [uri_unesc $name]
	if {"$name" == "keysep"} {
	  set keysep [uri_unesc $val]
	} else {
	  set aliases($name) [uri_unesc $val]
	}
      }
    }

    set raw_fields {}
    set columns [cass_get_columns $ns $table]
    if {![llength $columns]} {
      catch {
        cleanup_connection $ns
        namespace delete $ns
      }
      error "Failed to describe cassandra table $table"
    }

    foreach tuple $columns {
      foreach {name kind type} $tuple {
        lappend raw_fields $name
        set field2type($name) $type
        switch -exact -- $kind {
	  partition_key { lappend partition_keys $name }
	  clustering { lappend cluster_keys $name }
        }
      }
    }

    if {![info exists partition_keys]} {
      catch {
        cleanup_connection $ns
        namespace delete $ns
      }
      error "Can't happen! Cassandra table has no partition key!"
    }

    set keyfields $partition_keys
    if {[info exists cluster_keys]} {
      set keyfields [concat $keyfields $cluster_keys]
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

    foreach field $raw_fields {
      lappend fields $field

      if {[info exists aliases($field)]} {
        set field2alias($field) $aliases($field)
	unset aliases($field)
      }
    }

    namespace eval $ns {
      #
      # ctable - 
      #
      proc ctable {args} {
	set level [expr {[info level] - 1}]
	catch {::stapi::cass_ctable $level [namespace current] {*}$args} catchResult catchOptions
	dict incr catchOptions -level 1
	return -options $catchOptions $catchResult
      }

      # copy the search proc into this namespace
      proc search_to_cql [info args ::stapi::search_to_cql] [info body ::stapi::search_to_cql]
    }

    set ${ns}::table_name $table
    array set ${ns}::aliases [array get field2alias]
    set ${ns}::fields $fields
    set ${ns}::keyfields $keyfields
    array set ${ns}::types [array get field2type]
    set ${ns}::partition_keys $partition_keys
    set ${ns}::keysep $keysep

    if {[info exists cluster_keys]} {
      set ${ns}::cluster_keys $cluster_keys
    }

    return ${ns}::ctable
  }
  register cass connect_cassandra

  variable ctable_commands
  array set ctable_commands {
    get				cass_ctable_get
    set				cass_ctable_set
    array_get			cass_ctable_array_get
    array_get_with_nulls	cass_ctable_array_get_with_nulls
    exists			cass_ctable_exists
    delete			cass_ctable_delete
    count			cass_ctable_count
    foreach			cass_ctable_foreach
    type			cass_ctable_type
    import			cass_ctable_unimplemented
    import_postgres_result	cass_ctable_unimplemented
    export			cass_ctable_unimplemented
    fields			cass_ctable_fields
    fieldtype			cass_ctable_fieldtype
    needs_quoting		cass_ctable_needs_quoting
    names			cass_ctable_names
    reset			cass_ctable_unimplemented
    destroy			cass_ctable_destroy
    search			cass_ctable_search
    search+			cass_ctable_search
    statistics			cass_ctable_unimplemented
    write_tabsep		cass_ctable_unimplemented
    read_tabsep			cass_ctable_read_tabsep
    index			cass_ctable_ignore_null
  }
  variable ctable_extended_commands
  array set ctable_extended_commands {
    methods			cass_ctable_methods
    key				cass_ctable_key
    keys			cass_ctable_keys
    makekey			cass_ctable_makekey
    store			cass_ctable_store
  }

  #
  # cass_ctable -
  #
  proc cass_ctable {level ns cmd args} {
    variable ctable_commands
    variable ctable_extended_commands

    if {[info exists ctable_commands($cmd)]} {
      set proc $ctable_commands($cmd)
    } elseif {[info exists ctable_extended_commands($cmd)]} {
      set proc $ctable_extended_commands($cmd)
    } else {
      set proc cass_ctable_unimplemented
    }

    catch {$proc $level $ns $cmd {*}$args} catchResult catchOptions
    dict incr catchOptions -level 1
    return -options $catchOptions $catchResult
  }

  #
  # cass_ctable_methods -
  #
  proc cass_ctable_methods {level ns cmd args} {
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
  # cass_ctable_key - 
  #
  proc cass_ctable_key {level ns cmd args} {
    if {[info exists ${ns}::cluster_keys] || [llength [set ${ns}::partition_keys]] > 1}  {
      return _key
    }
    return [lindex [set ${ns}::partition_keys] 0]
  }

  #
  # cass_ctable_keys -
  #
  proc cass_ctable_keys {level ns cmd args} {
    return [set ${ns}::keyfields]
  }

  #
  # cass_ctable_makekey
  #
  proc cass_ctable_makekey {level ns cmd args} {
    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }

    array set array $args

    return [cass_makekey_array $ns array]
  }

  #
  # cass_makekey_array
  #
  # Common helper for cass_ctable_makekey, extracting the key from an array
  #
  proc cass_makekey_array {ns _array} {
    upvar 1 $_array array

    set rlist {}

    foreach key [set ${ns}::keyfields] {
      if {[info exists array($key)]} {
        lappend rlist $array($key)
      } else {
	# REEVALUATE - should we allow incomplete keys?
        return -code error "No value for $key in list"
      }
    }

    return [join $rlist [set ${ns}::keysep]]
  }

  #
  # cass_ctable_unimplemented
  #
  proc cass_ctable_unimplemented {level ns cmd args} {
    return -code error "Unimplemented command $cmd"
  }

  #
  # cass_ctable_ignore_null
  #
  proc cass_ctable_ignore_null {args} {
    return ""
  }

  #
  # cass_ctable_ignore_true
  #
  proc cass_ctable_ignore_true {args} {
    return 1
  }

  #
  # cass_ctable_ignore_false
  #
  proc cass_ctable_ignore_false {args} {
    return 0
  }

  #
  # cass_create_cql - internal helper routine
  #
  proc cass_create_cql {ns val slist} {
    if {![llength $slist]} {
      set slist [set ${ns}::fields]
    }

    set where {}

    if {[string length $val]} {
      foreach {k v} [cass_extract_key $ns $val] {
        lappend keys $k
        set type [set ${ns}::types($k)]
        lappend where "$k = [::casstcl::quote $v $type]"
      }
    }

    foreach arg $slist {
      if {"$arg" == "_key" || "$arg" == "-key"} {
	foreach key $keys {
	  lappend select $key
	}
      } elseif {"$arg" == "-all"} {
	set where {}
      } elseif {"$arg" == "-count"} {
	lappend select "COUNT(1)"
      } elseif {[info exists ${ns}::alias($arg)]} {
	lappend select [set ${ns}::alias($arg)]
      } else {
	lappend select $arg
      }
    }

    set cql "SELECT [join $select ,] FROM [set ${ns}::table_name]"
    if {[llength $where]} {
      append cql " WHERE [join $where " AND "]"
    }
    append cql " LIMIT 1;"

    return $cql
  }

  #
  # cass_ctable_get - implement ctable get operation on a postgres table
  #
  # Get list - return empty list for no data, CQL error is error
  #
  proc cass_ctable_get {level ns cmd val args} {
    set cql [cass_create_cql $ns $val $args]
    set result ""

    set status [cass_array_get_row $ns $cql result]
    if {!$status} {
      error $result
    }

    if {$status == -1} {
      return {}
    }

    array set row $result

    set result {}

    foreach f [set ${ns}::fields] {
      if {[info exists row($f)]} {
        lappend result $row($f)
      } else {
	lappend result {}
      }
    }

    return $result
  }

  #
  # cass_ctable_array_get
  #
  # Get name-value list - return empty list for no data, CQL error is error
  #
  proc cass_ctable_array_get {level ns cmd val args} {
    set cql [cass_create_cql $ns $val $args]

    set result {}
    set status [cass_array_get_row $ns $cql result]

    if {!$status} {
      error $result
    }

    return $result
  }


  #
  # cass_ctable_array_get_with_nulls
  #
  # Get name-value list - return empty list for no data, CQL error is error
  #
  proc cass_ctable_array_get_with_nulls {level ns cmd val args} {
    set cql [cass_create_cql $ns $val $args]

    set result {}
    set status [cass_array_get_row $ns $cql result]

    if {!$status} {
      error $result
    }

    if {$status == -1} {
      return {}
    }

    array set row $result

    cass_fill_nulls row [set ${ns}::fields]

    return [array get row]
  }


  #
  # cass_ctable_exists - implement a ctable exists method for Cassandra tables
  #
  proc cass_ctable_exists {level ns cmd val} {
    set cql [cass_create_cql $ns $val -key]

    set status [cass_array_get_row $ns $cql result]

    if {!$status} {
      error $result
    }

    return [expr {$status > 0}]
  }

  #
  # cass_ctable_count - implement a ctable count method for Cassandra tables
  #
  proc cass_ctable_count {level ns cmd args} {
    set cql [cass_create_cql $ns {} -count]

    set status [cass_array_get_row $ns $cql result]

    if {!$status} {
      error $result
    }

    if {$status == -1} {
      return 0
    }

    array set row $result

    return $row(count)
  }

  #
  # cass_ctable_fields - implement a ctables fields method for Cassandra tables
  #
  proc cass_ctable_fields {level ns cmd args} {
    return [set ${ns}::fields]
  }

  #
  # cass_ctable_type - implement a ctables "type" method for Cassandra tables
  #
  proc cass_ctable_type {level ns cmd args} {
    return cass:///[set ${ns}::table_name]
  }

  #
  # cass_ctable_fieldtype - implement a ctables "fieldtype" method for Cassandra tables
  #
  proc cass_ctable_fieldtype {level ns cmd field} {
    if {![info exists ${ns}::types($field)]} {
      return -code error "No such field: $field"
    }
    return [set ${ns}::types($field)]
  }

  #
  # cass_ctable_search - implement a ctable search method for SQL tables
  #
  proc cass_ctable_search {level ns cmd args} {
    array set search $args

    if {![info exists search(-code)] &&
	![info exists search(-key)] &&
	![info exists search(-array)] &&
	![info exists search(-array_get)] &&
	![info exists search(-array_get_with_nulls)] &&
	![info exists search(-array_with_nulls)]} {
	set search(-countOnly) 1
    }

    set cql [${ns}::search_to_cql search]
    if {[info exists search(-countOnly)]} {
      return [lindex [cass_array_get_row $ns $cql] 0]
    }

    set code {}
    set array ${ns}::select_array

    if {[info exists search(-array)]} {
        set array $search(-array)
    }
    if {[info exists search(-array_with_nulls)]} {
      set array $search(-array_with_nulls)
    }

    if {[info exists search(-array_with_nulls)] || [info exists search(-array_get_with_nulls)]} {
        lappend code [list ::stapi::cass_fill_nulls $array [set ${ns}::fields]]
    }

    if {[info exists search(-array_get_with_nulls)]} {
      lappend code "set $search(-array_get_with_nulls) \[array get $array]"
    }

    if {[info exists search(-array_get)]} {
      lappend code "set $search(-array_get) \[array get $array]"
    }

    if {[info exists search(-key)]} {
      lappend code "set $search(-key) \[cass_makekey_array $ns $array]"
    }

    lappend code $search(-code)
    lappend code "incr ${ns}::select_count"
    set ${ns}::select_count 0

    set selectCommand [list [cass $ns] select]
    lappend selectCommand $cql $array [join $code "\n"]

    if {[catch {uplevel #$level $selectCommand} catchResult catchOptions]} {
	dict incr catchOptions -level 1
	return -options $catchOptions $catchResult
    }
    return [set ${ns}::select_count]
  }

  #
  # cass_fill_nulls array fields...
  #
  proc cass_fill_nulls {_array args} {
    upvar 1 $_array array
    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }
    foreach field $args {
      if {![info exists array($field)]} {
	set array($field) {}
      }
    }
  }

  #
  # cass_ctable_foreach - implement a ctable foreach method for Cassandra tables
  #
  proc cass_ctable_foreach {level ns cmd keyvar value code} {
    error "Match operations not implemented in CQL"
  }

  #
  # cass_ctable_destroy - implement a ctable destroy method for Cassandra tables
  #
  proc cass_ctable_destroy {level ns cmd args} {
    cleanup_connection $ns
    namespace delete $ns
  }

  #
  # cleanup_connection ns
  #
  # Helper routine to clean up anything that might leak in a Cassandra connection namespace
  #
  proc cleanup_connection {ns} {
    if [info exists ${ns}::cassconn] {
      set nsconn [set ${ns}::cassconn]
      variable cassconn
      if {![info exists cassconn] || "$cassconn" != "$nsconn"} {
	$nsconn delete
	unset ${ns}::cassconn
      }
    }
  }

  #
  # cass_extract_key
  #
  # Given a list generated by cass_ctable_makekey, generate a key-value list
  # of {partition_key value [cluster_key value]...}
  #
  proc cass_extract_key {ns key} {
    set key [split $key [set ${ns}::keysep]]
    foreach ckey [set ${ns}::keyfields] cval $key {
      lappend result $ckey $cval
    }
    return $result
  }
    
  #
  # cass_ctable_delete - implement a ctable delete method for Cassandra tables
  #
  proc cass_ctable_delete {level ns cmd key args} {
    set l [cass_extract_key $ns $key]
    set where {}
    foreach {k v} $l {
      lappend where "$k = [::casstcl::quote $v [set ${ns}::types($k)]]"
    }
    set cql "DELETE FROM [set ${ns}::table_name] WHERE [join $where " AND "];"
    return [[cass $ns] exec $cql]
  }

  #
  # cass_ctable_set - implement a ctable set method for SQL tables
  #
  proc cass_ctable_set {level ns cmd key args} {
    if {![llength $args]} {
      return
    }

    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }

    set upserts [cass_extract_key $ns $key]
    set keyfields [set ${ns}::keyfields]

    foreach {col value} $args {
      if {[lsearch $col $keyfields] == -1} {
        if {[info exists ${ns}::alias($col)]} {
	  set col_cql [set ${ns}::alias($col)]
        } else {
          set col_cql $col
        }
  
        lappend upserts $col_cql $value
      }
    }

    [cass $ns] exec -upsert [set ${ns}::table_name] $upserts
  }

  #
  # cass_ctable_store - implement a ctable store method for SQL tables
  #
  proc cass_ctable_store {level ns cmd args} {
    if {[llength $args] == 1} {
      set args [lindex $args 0]
    }
    return [
      eval [list cass_ctable_set $level $ns $cmd [
	cass_ctable_makekey $level $ns $cmd $args
      ]] $args
    ]
  }

  #
  # cass_ctable_needs_quoting
  #
  proc cass_ctable_needs_quoting {level ns cmd args} { cass_ctable_unimplemented }

  #
  # cass_ctable_names
  #
  proc cass_ctable_names {level ns cmd args} { cass_ctable_unimplemented }

  #
  # cass_ctable_read_tabsep
  #
  proc cass_ctable_read_tabsep {level ns cmd args} { cass_ctable_unimplemented }

  #
  # search_to_cql
  #
  # This is never evaluated directly, it's only copied into a namespace
  # with [info body], so variables are from $ns and anything in ::stapi
  # needs direct quoting
  #
  proc search_to_cql {_req} {
    upvar 1 $_req req
    variable partition_keys
    variable cluster_keys
    variable table_name
    variable fields
    variable keyfields
    variable keysep
    variable types

    set select {}
    if {[info exists req(-countOnly)]} {
      lappend select "COUNT(1)"
    } else {
      if {[info exists req(-fields)]} {
	# Populate select with requested fields
	foreach col $req(-fields) {
	  if {[lsearch $select $col] == -1]} {
	    if {[info exists alias($col)]} {
	      lappend select "$alias($col) AS $col"
	    } else {
	      lappend select $col
	    }
	  }
	}

	# And if a key variable was requested, make sure the keys are in the selection.
        if {[info exists req(-key)]} {
	  foreach k $keyfields {
	    if {[lsearch $select $k == -1]} {
	      lappend select $k
	    }
          }
        }
      } else {
	# they want all fields, which include the keys, so do it simply...
        lappend select *
      }
    }
  
    set iwhere {}
    set pwhere {}
    if {[info exists req(-glob)]} { error "Match operations not implemented in CQL" }

    if {[info exists req(-compare)]} {
      set tuples $req(-compare)

      set tokenize 0
      # check to see if we need to tokenize any partition keys
      foreach tuple $tuples {
	foreach {op col v1 v2} $tuple break

	# If it's no a relational operator, no
	if {"$op" != "<" && "$op" != "<=" && $op != ">" && "$op" != ">="} continue

	# If it doesn't include the partition key, no
	if {"$col" != "_pkey" && "$col" != "_key" && [lsearch $partition_keys $col] == -1} continue

	set tokenize 1
      }

      while {[llength $tuples]} {
	set tuple [lindex $tuples 0]
	set tuples [lrange $tuples 1 end]
	foreach {op col v1 v2} $tuple break

	if {[info exists alias($col)]} {
	  set col_cql $alias($col)
	} else {
	  set col_cql $col
        }

	if {"$col" == "_ckey"} {
	  if {[llength $keyfields] == 1} {
	    set col_cql [lindex $keyfields 0]
	    set q1 [::casstcl::quote $v1 $types($col_cql)]
	    set q2 [::casstcl::quote $v2 $types($col_cql)]
	  } else {
	    set col_cql "([join $keyfields ","])"
	    set list {}
    	    foreach v [split $v1 $keysep] k $keyfields {
      	      lappend list [::casstcl::quote $v $types($k)]
    	    }
	    set q1 "([join $list ","])"
	    set list {}
    	    foreach v [split $v2 $keysep] k $keyfields {
      	      lappend list [::casstcl::quote $v $types($k)]
    	    }
	    set q2 "([join $list ","])"
	  }
	} elseif {"$col" == "_pkey"} {
	  if {[llength $keyfields] == 1} {
	    set col_cql [lindex $keyfields 0]
	    set q1 [::casstcl::quote $v1 $types($col_cql)]
	    set q2 [::casstcl::quote $v2 $types($col_cql)]
	  } else {
	    # push the disassembled values back on the list
	    foreach e1 [split $v1 $keysep] e2 [split $v2 $keysep] k $partition_keys {
	      lappend tuples [list $op $k $e1 $e2]
	    }
	    continue
	  }
	} elseif {"$col" == "_key"} {
	  if {[llength $keyfields] == 1} {
	    set col_cql [lindex $keyfields 0]
	    set q1 [::casstcl::quote $v1 $types($col_cql)]
	    set q2 [::casstcl::quote $v2 $types($col_cql)]
	  } else {
	    # push the disassembled values back on the list
	    foreach e1 [split $v1 $keysep] e2 [split $v2 $keysep] k $keyfields {
	      lappend tuples [list $op $k $e1 $e2]
	    }
	    continue
	  }
	} else {
	  set q1 [::casstcl::quote $v1 $types($col)]
	  set q2 [::casstcl::quote $v2 $types($col)]
	}

	if {$tokenize && [lsearch $col $partition_keys] != -1} {
	  set col_cql "TOKEN($col_cql)"
	  set q1 "TOKEN($q1)"
	  set q2 "TOKEN($q2)"
	}

	if {[lsearch -exact $keyfields $col] >= 0} {
	  set w pwhere
	} else {
	  set w iwhere
	}

	switch -exact -- [string tolower $op] {
	  false {
	      lappend $w "$col_cql = FALSE"
	  }

	  true {
	      lappend $w "$col_cql = TRUE"
	  }

	  null { error "NULL operations not implemented in CQL" }

	  notnull { error "NULL operations not implemented in CQL" }

	  < {
	      lappend $w "$col_cql < $q1"
	  }

	  <= {
	      lappend $w "$col_cql <= $q1"
	  }

	  = {
	      lappend $w "$col_cql = $q1"
	  }

	  != {
	      lappend $w "$col_cql <> $q1"
	  }

	  <> {
	      lappend $w "$col_cql <> $q1"
	  }

	  >= {
	      lappend $w "$col_cql >= $q1"
	  }

	  > {
	      lappend $w "$col_cql > $q1"
	  }

	  range {
	      lappend $w "$col_cql >= $q1"
	      lappend $w "$col_cql < $q2"
	  }

	  in {
	    set list {}
	    foreach v $v1 {
	      lappend list [::casstcl::quote $v $types($col)]
	    }
	    lappend $w "$col_cql IN ([join $list ","])"
	  }

	  contains {
	    lappend $w "$col_cql CONTAINS $q1"
	  }

	  containskey {
	    lappend $w "$col_cql CONTAINS KEY $q1"
	  }

          imatch { error "Match operations not implemented in CQL" }
          -imatch { error "Match operations not implemented in CQL" }
          match { error "Match operations not implemented in CQL" }
          notmatch { error "Match operations not implemented in CQL" }
          xmatch { error "Match operations not implemented in CQL" }
          -xmatch { error "Match operations not implemented in CQL" }
          match_case { error "Match operations not implemented in CQL" }
          notmatch_case { error "Match operations not implemented in CQL" }
          umatch { error "Match operations not implemented in CQL" }
          -umatch { error "Match operations not implemented in CQL" }
          lmatch { error "Match operations not implemented in CQL" }
          -lmatch { error "Match operations not implemented in CQL" }
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

	if {[lsearch -exact $keyfields $col] < 0} {
	  error "Can only sort on primary or cluster key"
	}

	if {[info exists alias(field)]} {
	  lappend order "$alias($field)$desc"
	} else {
	  lappend order "$field$desc"
	}
      }
    }
  
    set cql "SELECT [join $select ","] FROM $table_name"

    set where [concat $pwhere $iwhere]
    if {[llength $where]} {
      append cql " WHERE [join $where " AND "]"
    }

    if {[llength $order]} {
      append cql " ORDER BY [join $order ","]"
    }

    if {[info exists req(-limit)]} {
      append cql " LIMIT $req(-limit)"
    }

    if {[info exists req(-offset)]} {
      error "OFFSET not supported in CQL"
    }

    if {[info exists req(-allow_filtering)] && $req(-allow_filtering) != 0} {
      append cql " ALLOW FILTERING"
    }
  
    append cql ";"

    return $cql
  }
  
  #
  # cass_array_get_row
  #
  # Get one tuple from request in array-get form
  # Two calling sequences:
  #   set result [cass_array_get_row $cql]
  #      No data is an error (No Match)
  #   set status [cass_set_one_tuple $cql result]
  #      status ==  1 - success
  #      status == -1 - No data,  *result not modified*
  #      status ==  0 - CQL error, result is error string
  #
  proc cass_array_get_row {ns req {_result ""}} {
    if {[string length $_result]} {
      upvar 1 $_result result
    }

    set future [[cass $ns] async $req]
    $future wait

    if {[$future status] != "CASS_OK"} {
      set status 0
      set err [$future error_message]
      set result $err
    } else {
      set count 0
      $future foreach row {
        incr count
        set result [array get row]
        break
      }
      if {$count} {
        set status 1
      } else {
        set status -1
  	set err "No Match"
      }
    }

    $future delete

    if {[string length $_result]} {
      return $status
    }
      
    if {$status <= 0} {
      set errinf "$err\nIn $req"
      return -code error -errorinfo $errinf $err
    }

    return $result
  }
}

package provide st_client_cassandra 1.13.10

# vim: set ts=8 sw=4 sts=4 noet :
