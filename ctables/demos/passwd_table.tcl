# $Id$

package require ctable

CExtension U_pwfiles 1.0 {

  CTable u_passwd {
    key user
    varstring passwd
    int uid indexed 1 notnull 1
    int gid notnull 1
    varstring gcos
    varstring home
    varstring shell
  }

  CTable u_group {
    key group
    varstring passwd
    int gid
    varstring users
  }

}

package require U_pwfiles

proc load_pfwile {tab file} {
    set fp [open $file r]
    $tab read_tabsep $fp -tab ":" -skip "#" -nokeys
    close $fp
}

