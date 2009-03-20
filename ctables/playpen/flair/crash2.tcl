#
# crash ctables circa 3/2009 with table operations
#
# $Id$
#

package require ctable

CExtension Meowmix 1.1 {

CTable Meow {
    varstring key indexed 1 notnull 1
    varstring value indexed 1 notnull 1
}

}

package require Meowmix

Meow create m
m index create value

puts "m set 0 value 7612"; m set 0 value 7612			; m verify -verbose
puts "m set 1 value 7777"; m set 1 value 7772			; m verify -verbose
puts "m set 17 value 7777"; m set 17 value 7772			; m verify -verbose
puts "m set 3 value 101"; m set 3 value 101			; m verify -verbose
puts "m set 3 value {}"; m set 3 value {}			; m verify -verbose
puts "m set 3 key {} value 4847"; m set 3 key {} value 4847			; m verify -verbose
puts "m set 0 value {}"; m set 0 value {}			; m verify -verbose
puts "m set 0 value {}"; m set 0 value {}			; m verify -verbose
puts "m set 1 value {}"; m set 1 value {}			; m verify -verbose
puts "m delete 4"; m delete 4			; m verify -verbose
puts "m delete 2"; m delete 2			; m verify -verbose
puts "m set 4 value {}"; m set 4 value {}			; m verify -verbose
puts "m set 3 key {} value 6954"; m set 3 key {} value 6954			; m verify -verbose
puts "m set 0 value {}"; m set 0 value {}			; m verify -verbose
puts "m set 2 key {} value 3738"; m set 2 key {} value 3738			; m verify -verbose
puts "m set 2 value {}"; m set 2 value {}			; m verify -verbose
puts "m set 3 value {}"; m set 3 value {}			; m verify -verbose
puts "m set 4 value 8897"; m set 4 value 8897			; m verify -verbose
m verify -verbose
puts "m set 3 key {} value 6813"; m set 3 key {} value 6813			; m verify -verbose

