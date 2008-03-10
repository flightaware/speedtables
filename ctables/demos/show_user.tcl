# $Id$

proc show_user {list} {
    array set entry $list

    puts "User name: $entry(username)"
    puts "       ID: $entry(uid)"
    puts "    Group: $entry(gid)"
    puts "     Name: $entry(fullname)"
    puts "     Home: $entry(home)"
    puts "    Shell: $entry(shell)"
}

proc search_passwd {tab id proc} {
    if [string is integer $id] {
	set field uid
    } else {
	set field username
    }

    return [
	$tab search \
	    -compare [list [list = $field $id]] \
	    -array_get_with_nulls list \
	    -code {$proc $list}
    ]
}
