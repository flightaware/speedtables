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

array set data {
foo 		{mac 11:22:33:44:55:66 ip 206.109.1.1}
bar 		{mac 66:55:44:33:22:11 ip 206.109.7.65}
snap 		{mac de:ad:be:ef:00:00 ip 127.0.0.1}
crackle 	{mac 00:de:ad:be:ef:00 ip 192.168.1.1}
pop 		{mac fe:ed:da:be:e0:00 ip 10.0.1.1}
}

# Apparently not all implementations of ethers understand this format
# doublepop 	{mac feed.dabe.e001    ip 10.9.8.7}
# 
# array set special_macs {
# doublepop 	fe:ed:da:be:e0:01
# }

foreach {key val} [array get data] {
	eval [list t set $key id $key] $val
}

# Make sure what we put in comes out
puts "checking data integrity"
t search -array row -code {
	set id $row(id)
	array set expected $data($id)
	if {[info exists special_macs($id)]} {
		set expected(mac) $special_macs($id)
	}
	if {"$row(ip)" != "$expected(ip)"} {
		error "Expected ip $expected(ip) got $row(ip) for $id"
	}
	if {"[string tolower $row(mac)]" != "[string tolower $expected(mac)]"} {
		error "Expected mac $expected(mac) got $row(mac) for $id"
	}
}
puts "ok"

proc check {code count} {
	if {[llength $code]} {
		puts [list t search -compare $code]
		set check [t search -compare $code -countOnly 1]
		set name [list search -compare $code]
	} else {
		puts [list t search]
		set check [t search -countOnly 1]
		set name full-search
	}
	if {$check != $count} {
		error "Expected count $count got $check for $name"
	}
}

puts "checking search"
check "" 5

check {{> mac 00:ff:ff:ff:ff:ff}} 4

check {{> mac 00:ff:ff:ff:ff:ff}} 4

check {{range mac 00:ff:ff:ff:ff:ff ff:ff:ff:ff:ff:ff}} 4

check {{>= ip 128.0.0.0} {< ip 255.255.255.255}} 3

check {{range ip 128.0.0.0 255.255.255.255}} 3

t index create ip
puts "checking with index"

check {{range ip 128.0.0.0 255.255.255.255}} 3
puts "ok"
