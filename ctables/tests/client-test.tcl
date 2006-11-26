#
#
#
#
#
#

package require ctable_client

remote_ctable 127.0.0.1 t

puts "remote search of t"
t search
puts ""

puts "search of t in descending coolness limit 5"
t search -sort -coolness -limit 5 -include_field_names 1
puts ""

