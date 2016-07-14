# set up a postgres connection without depending on any external infrastructure like DIO/rivet

# Requires the following environment variables/arguments, or a conninfo structure
# matching the undashed argument names in "conninfo.tcl" or "~/.conninfo.tcl"

# -host $DBHOST=hostname (defaults to localhost)
# -port $DBPORT=tcp-port (defaults to 5432)
# -user $DBUSER=username (defaults to login name)
# -dbname $DBNAME=database-name (defaults to user name)
# -password $DBPASS=password (required)

namespace eval ::test {
}

proc pgconn {args} {
	global env

	if [info exists ::test::pgconn] {
		return $::test::pgconn
	}

	if [file exists conninfo.tcl] {
		source conninfo.tcl
	} elseif {[file exists $env(HOME)/.conninfo.tcl]} {
		source $env(HOME)/.conninfo.tcl
	}
	if [array exists conninfo] {
		foreach {key value} [array get conninfo] {
			set opts(-$key) $value
		}
	}

	array set opts $args

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
		}
	}
	if ![info exists opts(-dbname)] {
		if [info exists env(DBNAME)] {
			set opts(-dbname) $env(DBNAME)
		} else {
			set opts(-dbname) $opts(-user)
		}
	}

	set dbname $opts(-dbname)
	unset opts(-dbname)
	if [catch [concat pg_connect [list $dbname] [array get opts]] res] {
		error $res
	}

	puts stderr "Connected [array get opts] result is $res"
	puts stderr [list ::stapi::set_conn $res]
	::stapi::set_conn $res
}
