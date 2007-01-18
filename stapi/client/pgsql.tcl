# $Id$

package require scache_client

namespace eval ::scache {
  proc connect_sql {table {address "-"} args} {
    return -code error "SQL transport method not implemented"
  }
  register sql connect_sql

  proc search_to_sql {_table _request} {
    upvar 1 $_table table
    upvar 1 $_request request
    array set field_to_sql $table(sql)

    set select {}
    if [info exists request(-countOnly)] {
      lappend select "COUNT($table(key)) AS count"
    } else {
      if [info exists request(-fields)] {
        set fields $request(fields)
      } else {
        set fields $table(fields)
      }

      foreach field $fields {
        if [info exists field_to_sql($field)] {
	  lappend select "$field_to_sql($field) AS $field"
        } else {
	  lappend select $field
        }
      }
    }

    set where {}
    if [info exists request(-glob)] {
      lappend where "$table(key) LIKE [glob_to_quoted_match $request(-glob)"
    }

    if [info exists request(-compare)] {
      foreach tuple $request(-compare) {
	foreach {op col v1 v2} $tuple break
	if [info exists col_types($col)] {
	  set type $col_type($col)
	} else {
	  set type varchar
	}
	set q1 [quote_for_sql $v1 $type]
	set q2 [quote_for_sql $v2 $type]

	if [info exists field_to_sql($col)] {
	  set col $field_to_sql($col)
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
	  match { lappend where "$col ILIKE [glob_to_quoted_match $v1]" }
	  match_case { lappend where "$col LIKE [glob_to_quoted_match $v1]" }
	  range {
	    lappend where "$col >= $q1"
	    lappend where "$col < [quote_for_sql $v2 $type]"
	  }
	  in {
	    foreach v [lrange $tuple 2 end] {
	      lappend q [quote_for_sql $v $type]
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
	if [info exists field_to_sql(field)] {
	  lappend order "$field_to_sql($field)$desc"
	} else {
	  lappend order "$field$desc"
	}
      }
    }

    set sql "SELECT [join $select ","] FROM $table(table_name)"
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
}

package provide scache_sql_client 1.0
