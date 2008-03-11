# $Id$

package require ctable

CExtension U_passwd 1.0 {

  CTable u_passwd {
    varstring username indexed 1 notnull 1
    varstring passwd
    int uid indexed 1 notnull 1
    int gid notnull 1
    varstring fullname
    varstring home notnull 1
    varstring shell
  }

}

package require U_passwd

proc load_pwfile {tab file} {
    set fp [open $file r]
    $tab read_tabsep $fp -tab ":" -skip "#" -nokeys
    close $fp
}

