# $Id$

package require ctable

CExtension U_pwfiles 1.0 {

  CTable u_passwd {
    varstring user indexed 1 notnull 1
    varstring passwd
    int uid indexed 1 notnull 1
    int gid notnull 1
    varstring fullname
    varstring home notnull 1
    varstring shell
  }

  CTable u_group {
    varstring group
    varstring passwd
    int gid
    varstring users
  }

}

package require U_pwfiles

proc load_pwfile {tab file} {
    set fp [open $file r]
    $tab read_tabsep $fp -tab ":" -skip "#" -nokeys
    close $fp
}

