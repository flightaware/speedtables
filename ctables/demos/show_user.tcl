# $Id$

proc show_user {rowArray} {
    upvar 1 $rowArray row

    puts "User name: $row(user)"
    puts "       ID: $row(uid)"
    puts "    Group: $row(gid)"
    puts "     GCOS: $row(gcos)"
    puts "     Home: $row(home)"
    puts "    Shell: $row(shell)"
}

if {[llength $argv] == 0} {
   puts stderr "Usage: $argv0 user \[user...]"
   exit 2
}

foreach user $argv {
    if [string is integer $user] {
	set count [
	    $pwtab search \
		-compare [list [list = uid $user]] \
		-array_with_nulls row \
		-key key \
		-code { puts $key; show_user row }
	]
	if {$count == 0} {
	    puts stderr "$uid: no users found"
	}
    } elseif ![$pwtab exists $user] {
	puts "$user: not found"
    } else {
	array set row [$pwtab array_get_with_nulls $user]
	show_user row
    }
}

