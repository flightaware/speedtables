#
# test ctables search routine
#
# $Id$
#

package require ctable

#CTableBuildPath /tmp

CExtension animinfo 1.0 {

CTable anim_characters {
    varstring id indexed 1 unique 1 notnull 1
    varstring name indexed 1 unique 1
    varstring home indexed 1 unique 0
    varstring show indexed 1 unique 0
    varstring dad
    boolean alive default 1
    varstring gender default male
    int age indexed 1 unique 0
    int coolness
}

}

package require Animinfo

anim_characters create t
