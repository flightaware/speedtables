# set up a postgres connection without depending on any external infrastructure like DIO/rivet

# Requires the following environment variables/arguments

# -host $DBHOST=hostname (defaults to localhost)
# -port $DBPORT=tcp-port (defaults to 5432)
# -user $DBUSER=username (defaults to login name)
# -db / -name $DBNAME=database-name (defaults to user name)
# -password $DBPASS=password (required)

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
	if ![info exists opts(-port)] {
		if [info exists env(DBPORT)] {
			set opts(-port) $env(DBPORT)
		} else {
			set opts(-port) 5432
		}
	}
	if ![info exists opts(-user)] {
		if [info exists env(DBUSER)] {
			set opts(-user) $env(DBUSER)
		} elseif [info exists env(LOGNAME)] {
			set opts(-user) $env(LOGNAME)
		} else {
			error "Need database user name"
		}
	}
	if ![info exists opts(-password)] {
		if [info exists env(DBPASS)] {
			set opts(-password) $env(DBPASS)
		} else {
			error "Need database user password"
		}
	}
	if ![info exists opts(-name)] {
		if [info exists opts(-db)] {
			set opts(-name) $opts(-db)
			unset opts(-db)
		} else {
			set opts(-name) $opts(-user)
		}
	}

	set dbname $opts(-name)
	unset opts(-name)
	puts "+ [concat pg_connect [list $dbname] [array get opts]]"
	if [catch [concat pg_connect [list $dbname] [array get opts]] res] {
		error $res
	}
	set ::test::pgconn $res
	return $res
}
