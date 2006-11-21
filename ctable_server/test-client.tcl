#
#
#
#
#
#
#

source client.tcl

remote_ctable_create localhost cable_info foo

remote_ctable localhost foo

puts "foo is ready to go, hopefully"
