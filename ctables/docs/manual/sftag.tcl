#!/usr/local/bin/tclsh8.4

# $Id$

proc filename {chapter} {
  return [format ch%02d.html $chapter]
}

for {set chapter 1} {$chapter <= 15} {incr chapter} {
  lappend filenames [filename $chapter]
}
lappend filenames index.html manual.css

set build sourceforge

# From https://sourceforge.net/project/admin/logo.php?group_id=205759
set logo {<a href="http://sourceforge.net"><img src="http://sflogo.sourceforge.net/sflogo.php?group_id=205759\&amp;type=1" width="88" height="31" border="0" alt="SourceForge.net Logo" /></a>}

set logo_right "<!-- %BEGIN LOGO% -->\n<span class=logo-right>$logo</span>\n<!-- %END LOGO% -->"
set logo_left "<!-- %BEGIN LOGO% -->\n<span class=logo-left>$logo</span>\n<!-- %END LOGO% -->"
set logo "<!-- %BEGIN LOGO% -->\n<span class=logo>$logo</span>\n<!-- %END LOGO% -->"

file mkdir $build

foreach file $filenames {
  set fp [open $file r]
  set text [read $fp]
  close $fp

  regsub -all {<!-- INSERT LOGO RIGHT -->} $text $logo_right text
  regsub -all {<!-- INSERT LOGO LEFT -->} $text $logo_left text
  regsub -all {<!-- INSERT LOGO -->} $text $logo text

  set fp [open $build/$file w]
  puts -nonewline $fp $text
  close $fp
}
