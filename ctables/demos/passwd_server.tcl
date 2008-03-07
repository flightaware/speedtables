#!/usr/bin/env tclsh8.4
# $Id$

# Demo - ctable server for /etc/passwd

package require ctable
package require ctable_server

source passwd_table.tcl

proc load_password {pw} {
	set fp [open /etc/passwd r]
	$pw read_tabsep $fp -tab ":" -skip "#" -nokeys
	close $fp
}

u_passwd create passwd

load_pwfile passwd /etc/passwd

::ctable_server::register sttp://*:3100/passwd passwd

::ctable_server::serverwait

