#!/usr/local/bin/tclsh8.5

package require speedtable

speedtables Foo 1.0 {

table Bar {
key foo
varstring value
}

}

package require Foo

Bar create bar

bar set 1 value one
bar set 2 value two

bar search -compare [list [list in foo [list 1 1]]] -delete 1
