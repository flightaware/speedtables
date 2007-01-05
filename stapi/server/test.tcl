#!/usr/local/bin/tclsh8.4

lappend auto_path [exec pwd]

package require scache

set columns [
  ::scache::from_table sc_equip mac -index i_account_number -without disco
]
if [string match "*disco*" $columns] {
  puts "Warning: disco is not yet dead."
}
puts "\$columns = [list $columns]"
::scache::init_ctable sc_equip {} "" $columns
set equip [::scache::open_cached sc_equip]
puts "\[$equip count] = [$equip count]"
