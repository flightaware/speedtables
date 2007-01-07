#
# test ctables search routine
#
# $Id$
#

package require ctable

#set ::ctable::showCompilerCommands 1
#set ::ctable::genCompilerDebug 1

CExtension nametest 1.0 {

CTable nameTable {
    varstring name indexed 1 notnull 1
    double latitude notnull 1
    double longitude indexed 1 notnull 1
}

}

package require Nametest

nameTable create n

