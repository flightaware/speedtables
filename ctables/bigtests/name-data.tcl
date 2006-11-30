#
# test ctables search routine
#
# $Id$
#

package require ctable

#CTableBuildPath /tmp

CExtension nametest 1.0 {

CTable nameTable {
    varstring name
}

}

package require Nametest

nameTable create n

set fp [open names.txt]
n read_tabsep $fp
close $fp

puts "[n count] records loaded into ctable n"
