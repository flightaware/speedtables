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

