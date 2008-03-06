#!/usr/bin/env tclsh8.4
# $Id$

# Demo - ctable server for /etc/passwd

package require ctable
package require ctable_server

CExtension password 1.0 {

CTable pw {
    key user
    varstring passwd
    int uid indexed 1 notnull 1
    int gid notnull 1
    varstring gcos
    varstring home
    varstring shell
}

}


package require Password

proc load_password {pw} {
	set fp [open /etc/passwd r]
	$pw read_tabsep $fp -tab ":" -skip "#" -nokeys
	close $fp
}

pw create passwd

load_password passwd

::ctable_server::register sttp://*:3100/passwd passwd

::ctable_server::serverwait

