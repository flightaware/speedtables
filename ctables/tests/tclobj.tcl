#

package require ctable

CExtension Objecttest 1.0 {

CTable objtable {
    tclobj value notnull 1
}

}

package require Objecttest

objtable create o

o set k1 value [list a b c]

set list [o get k1]

if {"$list" != "{a b c}"} {
	error "Expected {a b c} got $list"
}
