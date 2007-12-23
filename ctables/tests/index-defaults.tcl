source index-defaults.ct

package require Indef

set t [indef create #auto]

proc di {t i} {
  puts "begin $t index dump $i"
  $t index dump $i
  puts "end"
}

$t index create color
$t index create flavor

set foods {pizza sugar toast waffles soup nuts}
set colors {red orange yellow white maroon}
set flavors {sweet sour cheesy pepper acid}

proc re {list} {
  return [lindex $list [expr {int(rand() * [llength $list])}]]
}

for {set i 0} {$i < 100} {incr i} {
  if [expr {int(rand() * 2)}] {
    $t set $i id [re $foods]$i color [re $colors]
  } else {
    $t set $i id [re $foods]$i flavor [re $flavors]
  }
}

di $t color
di $t flavor

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t set $j color [re $colors] flavor [re $flavors]
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t delete $j
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t set $j id [re $foods]$j color [re $colors] flavor [re $flavors]
}

for {set i 0} {$i < 100} {incr i} {
  set j [expr {int(rand() * 100)}]
  $t set $j color [re $colors] flavor [re $flavors]
}

di $t color
di $t flavor
