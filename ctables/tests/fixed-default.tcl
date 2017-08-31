#
# fixed string default test
#
# $Id$
#

source test_common.tcl

package require ctable

CExtension fixed_defaults 1.0 {

CTable fixedStrings {
    int noid
    fixedstring single 1 notnull 1 default "-"
    fixedstring triple 3 notnull 1 default "---"
}

}

package require Fixed_defaults 1.0

fixedStrings create t

proc tt {cmd expected} {
	eval $cmd
	set result [t array_get 1]
	if {"$result" ne "$expected"} {
		error "Command [list $cmd] expected [list $expected] got [list $result]"
	}
}

tt {t set 1 noid 1} {noid 1 single - triple ---}
tt {t set 1 single a triple abc} {noid 1 single a triple abc}
tt {t set 1 single ""} {noid 1 single - triple abc}
tt {t set 1 triple ""} {noid 1 single - triple ---}
tt {t set 1 triple "a"} {noid 1 single - triple a--}

