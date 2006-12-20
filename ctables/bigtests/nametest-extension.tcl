#
# test ctables search routine
#
# $Id$
#

package require ctable

set ::ctable::showCompilerCommands 1

CExtension nametest 1.0 {

CTable nameTable {
    varstring name indexed 1
    double latitude
    double longitude indexed 1
}

}

package require Nametest

nameTable create n

