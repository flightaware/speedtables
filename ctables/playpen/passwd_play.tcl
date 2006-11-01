

source passwd.ct

package require Yewnix

passwd_info create foo

set fp [open passwd.tab]
foo read_tabsep $fp

puts "foo is ready to go"
