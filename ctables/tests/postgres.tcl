# set up a postgres connection without depending on any external infrastructure like DIO/rivet

# Requires the following environment variables/arguments

# -host $DBHOST=hostname (defaults to localhost)
# -db / -name $DBNAME=database-name (defaults to unqualified hostname, required if localhost)
# -port $DBPORT=tcp-port (defaults to 5432)
# -user $DBUSER=username (defaults to login name)
# -pass $DBPASS=password (required)

proc pgconn {args} {
	array set opts $args
	global env

	if [info exists ::test::pgconn] {
		return $::test::pgconn
	}

	if ![info exists opts(-host)] {
		if [info exists env(DBHOST)] {
			set opts(-host) $env(DBHOST)
		} else {
			set opts(-host) localhost
		}
	}
	if ![info exists opts(-name)] {
		if [info exists opts(-db)] {
			set opts(-name) $opts(-db)
			unset opts(-db)
		} elseif [info exists env(DBNAME)] {
			set opts(-name) $env(DBNAME)
		} else {
			set l [split $opts(-host) "."]
			set opts(-name) [lindex $l 0]
			if {![string length $opts(-name)] || "$opts(-name)" == "localhost"} {
				error "Need database name"
			}
		}
	}
	if ![info exists opts(-port)] {
		if [info exists env(DBPORT)] {
			set opts(-port) $env(DBPORT)
		} else {
			set opts(-port) 5432
		}
	}
	if ![info exists opts(-user)] {
		if [info exists env(DBUSER)] {
			set opts(-port) $env(DBUSER)
		} elseif [info exists env(LOGNAME)] {
			set opts(-port) $env(LOGNAME)
		} else {
			error "Need database user name"
		}
	}
	if ![info exists opts(-pass)] {
		if [info exists env(DBPASS)] {
			set opts(-port) $env(DBPASS)
		} else {
			error "Need database user password"
		}
	}

	set dbname $opts(-name)
	unset opts(-name)
	if {catch [list set pgconn [list $dbname] [array get opts]] err} {
		error $err
	}
	set ::test::pgconn $pgconn
	return $pgconn
}
