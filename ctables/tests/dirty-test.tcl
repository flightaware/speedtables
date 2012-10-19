source test_common.tcl

speedtables Testdirty 0.1 {
table Dirty {
varstring s
}
}

package require Testdirty

Dirty create d

d set 0 {s "foo"}
if {![d get 0 _dirty]} {
  error "Dirty bit expected, not set"
}
d set 0 {_dirty 0}
if {[d get 0 _dirty]} {
  error "Dirty bit set but not expected"
}
d set 0 {s "bar"}
if {![d get 0 _dirty]} {
  error "Dirty bit expected, not set"
}
