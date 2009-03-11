#
# crash ctables circa 3/2009 with table operations
#
# $Id$
#

package require ctable

CExtension Meowmix 1.1 {

CTable Meow {
    varstring value indexed 1  notnull 1 default stinky
    #default stinky
}

}

package require Meowmix

Meow create m
m index create value

#Meow null_value stinkpot
#Meow null_value ""

m set 0 value {}
m set 4 value 3104
m set 0 value 4728
m delete 4
