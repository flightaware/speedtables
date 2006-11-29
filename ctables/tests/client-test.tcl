#
#
#
#
#
#

package require ctable_client

#remote_ctable ctable://127.0.0.1/testTable t
remote_ctable ctable://127.0.0.1:11112/testTable t

puts "search of t in descending coolness limit 5"
t search -sort -coolness -limit 5 -write_tabsep stdout
puts ""

puts "search of t in descending coolness limit 5 / code body"
t search -sort -coolness -limit 5 -key key -array_get_with_nulls data -code {puts "$key -> $data"}
puts ""

