#!/usr/local/bin/tclsh8.4

lappend auto_path [exec pwd]

package require scache

::scache::init_cache_ctable sc_equip mac
set equip [::scache::open_cached sc_equip]
puts "\[$equip count] = [$equip count]"
