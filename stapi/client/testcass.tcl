#!/bin/sh

package require st_client_cassandra

if ![info exists env(CASSTCL_CONTACT_POINTS)] {
  error "Please set environment variables CASSTCL_USERNAME, CASSTCL_CONTACT_POINTS, CASSTCL_PASSWORD"
}

set c ::stapi::connect cass:///test.school/

$c search -compare {{> age 20}} -array row {
  puts [array get row]
}

