#
# test ctables search routine
#
# $Id$
#

package require ctable

#CTableBuildPath /tmp

CExtension macip 1.0 {

CTable mac_ip {
    varstring id indexed 1 unique 1
    mac mac indexed 1 unique 1
    inet ip indexed 1 
}

}

package require Macip

mac_ip create t
t index create id

t set foo id foo mac 11:22:33:44:55:66 ip 206.109.1.1
t set bar id bar mac 66:55:44:33:22:11 ip 206.109.7.65
t set snap id snap mac de:ad:be:ef:00:00 ip 127.0.0.1
t set crackle id crackle mac 00:de:ad:be:ef:00 ip 192.168.1.1
t set pop id pop mac fe:ed:da:be:e0:00 ip 10.0.1.1

puts "t search all"
t search -write_tabsep stdout
puts ""
 
 puts "t search mac > 00:ff:ff:ff:ff:ff"
t search -compare {{> mac 00:ff:ff:ff:ff:ff}} -write_tabsep stdout
puts ""

t index create mac
 puts "t search mac > 00:ff:ff:ff:ff:ff with search+"
t search+ -compare {{> mac 00:ff:ff:ff:ff:ff}} -write_tabsep stdout
puts ""

 puts "t search range mac 00:ff:ff:ff:ff:ff ff:ff:ff:ff:ff:ff with search+"
t search+ -compare {{range mac 00:ff:ff:ff:ff:ff ff:ff:ff:ff:ff:ff}} -write_tabsep stdout
puts ""

puts "t search+ ip >= 128.0.0.0 and < 255.255.255.255 without index"
t search+ -compare {{>= ip 128.0.0.0} {< ip 255.255.255.255}} -write_tabsep stdout
puts ""

puts "t search+ range ip 128.0.0.0 to 255.255.255.255"
t search+ -compare {{range ip 128.0.0.0 255.255.255.255}} -write_tabsep stdout
puts ""

t index create ip

puts "t search+ range ip 128.0.0.0 to 255.255.255.255 with index"
t search+ -compare {{range ip 128.0.0.0 255.255.255.255}} -write_tabsep stdout
puts ""

