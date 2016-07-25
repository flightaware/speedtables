#!/bin/sh

set d [exec pwd]
if [file exists $d/pkgIndex.tcl] {
  puts stderr "auto path is $d"
  lappend auto_path $d
}
set d [file dirname $d]
if [file exists $d/pkgIndex.tcl] {
  puts stderr "auto path is $d"
  lappend auto_path $d
}

package require st_client_cassandra

if ![info exists env(CASSTCL_CONTACT_POINTS)] {
	error "Please set environment variables CASSTCL_USERNAME, CASSTCL_CONTACT_POINTS, CASSTCL_PASSWORD"
}

set school [::stapi::connect cass:///test.school/]

$school set A000000 name Hobo age 101
$school set A000001 name Hungry age 51
$school set A000002 name Happy age 52
$school set A000003 name Dopey age 53

$school search -array row -code {
	lappend students $row(student_id) $row(name)
	set rows($row(student_id)) [array get row]
}

foreach {id name} $students {
	puts "$school get $id --> [$school get $id]"
	if {"$name" == "Hobo"} {
	     puts "Deleting Hobo!"
	     $school delete $id
        }
}

puts "$school array_get A000001 -> [$school array_get A000001]"
puts "$school array_get_with_nulls A000001 -> [$school array_get_with_nulls A000001]"

puts "Changing Dopey to Grumpy"
$school set A000003 name Grumpy
puts "$school array_get A000003 -> [$school array_get A000003]"

puts "Checking routines"
puts "methods   [$school methods]"
puts "key       [$school key]"
puts "keys      [$school keys]"
set a [$school array_get A000003]
puts "makekey   [$school makekey $a] (from $a)"
puts "exists    [$school exists A000003]"
puts "fields    [$school fields]"
puts "type      [$school type]"
puts "fieldtype [$school fieldtype student_id]"
array set tmp $a
set tmp(name) "Doozer"
$school store [array get tmp]
puts "store ->  [$school array_get A000003]"

puts "search tests"

$school search -compare {{in student_id {A000001 A000002 A000003 A000004}}} -array row -code {
	puts [array get row]
}

puts "search index tests"

puts "== Hungry"
$school search -compare {{= name "Hungry"}} -array row -code {
	puts [array get row]
}
$school destroy

set class [::stapi::connect cass:///test.class/]

puts "Cluster key test - room = 1301 and hour > 12"
$class search -compare {{= room 1301} {>= hour 12}} -array row -code {
	puts [array get row]
}

puts "Expensive cluster key test - hour > 12"
$class search -compare {{>= hour 12}} -array row -allow_filtering 1 -code {
	puts [array get row]
}

$class destroy
