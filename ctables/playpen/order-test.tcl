package require ctable

CExtension unixb 1.0 {

CTable passwd_info {
    varstring password
    int       groupID
    int       userID
    varstring home
    varstring name
    varstring shell
}

}

package require Unixb

passwd_info create pt

set fp [open passwd.tsv r]
pt read_tabsep $fp -with_field_names
close $fp

puts [pt array_get shonuf]

