# stapi/display/display.tcl -- derived from diodisplay.tcl

# Copyright 2006 Superconnect

# diodisplay.tcl --

# Copyright 2002-2004 The Apache Software Foundation

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#	http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# $Id$
#

package require Itcl
package require form
package require st_client
package require stapi_extend

#
# Only load ::csv:: if it's actually wanted.
#
namespace eval ::stapi::display {
	variable csv_loaded 0
	proc load_csv {} {
		variable csv_loaded
		if $csv_loaded {
			return
		}
		uplevel #0 package require csv
	}
}

catch { ::itcl::delete class STDisplay }

::itcl::class ::STDisplay {
	constructor {args} {
		eval configure $args
		load_response
		
		# allow 'ctable' instead of 'table' as a historical alias (interim)
		if {![info exists table] && [info exists ctable]} {
			set table $ctable
			unset ctable
		}
		
		# If it's not already an extended table, treat it like a URI
		if {[info exists table] && ![::stapi::extend::extended $table]} {
			set uri $table
			unset table
		}

		if {![info exists table]} {
			if ![info exists uri] {
				return -code error "No table or uri"
			}
			
			if ![info exists keyfields] {
				if [info exists key] {
					set keyfields [list $key]
				}
			}
			
			if [info exists keyfields] {
				set table [::stapi::connect $uri -keys $keyfields]
			} else {
				set table [::stapi::connect $uri]
			}
		}

		if ![info exists keyfields] {
			if [info exists key] {
				set keyfields [list $key]
			} else {
				set mlist [$table methods]

				if {[lsearch $mlist "key"] >= 0} {
					set keyfields [list [$table key]]
				} else {
					set keyfields [$table keys]
				}
			}
		}

		if {![info exists key]} {
			if {[llength $keyfields] == 1} {
				set key [lindex $keyfields 0]
			}
		}

		if {![info exists key]} {
			set cause $table
			if {[info exists uri]} { set cause $uri }
			return -code error "No key or keyfields, and $cause doesn't know how to tell me"
		}

		if {[lempty $form]} {
			set form [namespace which [::form #auto -defaults response]]
		}

		set document [env DOCUMENT_NAME]

		if {[info exists response(num)] \
				&& ![lempty $response(num)]} {
			set pagesize $response(num)
		}

		read_css_file
	}

	destructor {
		if {$cleanup} { do_cleanup }
	}

	method destroy {} {
		::itcl::delete object $this
	}

	method debug {args} {
		set show $debug

		if {"[lindex $args 0]" == "-force"} {
			set show 1
			set args [lrange $args 1 end]
		}
		if {$show} {
			eval ::stapi::debug $args
		}
	}

	## Glue routines for the mismatch between DIO and remote ctables.
	## The way DIO builds SQL that can be exposed outside DIO in assembling
	## a request is used by DIODisplay. We have to make that more abstract

	## New exposed configvars for STDisplay
	public variable table
	public variable ctable	;# Alias
	public variable uri
	public variable keyfields
	public variable key
	public variable debug 0

	## Background configvars
	private variable ct_selection

	private variable case

	#
	# configvar - a convenient helper for creating methods that can
	#  set and fetch one of the object's variables
	#
	method configvar {varName string {defval ""}} {
		if {"$string" == "$defval"} { return [set $varName] }
		configure -$varName $string
	}

	#
	# is_function - return true if name is known to be a function
	# such as Search List Add Edit Delete Details Main Save DoDelete Cancel
	# etc.
	#
	method is_function {name} {
		if {[lsearch $functions $name] >= 0} { return 1 }
		if {[lsearch $allfunctions $name] >= 0} { return 1 }
		return 0
	}

	#
	# do_cleanup - clean up our field subobjects, DIO objects, forms, and the 
	# like.
	#
	method do_cleanup {} {
		## Destroy all the fields created.
		foreach field $allfields { catch { $field destroy } }

		## Destroy the form object.
		catch { $form destroy }
	}

	#
	# handle_error - emit an error message
	#
	method handle_error {error args} {
		puts "<B>An error has occurred processing your request</B>"
		puts "<PRE>"
		if {$debug > 1} {
			puts ""
			if [llength $args] {
				puts [join $args "\n\n"]
			} else {
				puts "$::errorInfo"
			}
		}
		puts "$error"
		puts "</PRE>"
	}

	# escape string for display within HTML
	protected method escape_cgi {str} {
		if {[catch {escape_sgml_chars $str} result] == 0} {
			# we were running under Apache Rivet and could use its existing command.
			return $result
		} else {
			# TODO: this is not very good; it is probably missing some chars.
			# Substitute & first :)
			foreach \
				src " &		   {\"}		 " \
				dst { {\&amp;} {\&quot;} } {
					regsub -all $src $str $dst str
				}
			return $str
		}
	}

	# escape string for creation of a URL
	protected method escape_url {str} {
		if {[catch {escape_string $str} result] == 0} {
			# we were running under Apache Rivet and could use its existing command.
			return $result
		} else {
			# TODO: this is not very good; should also hex-encode many other things.
			foreach \
				src " &		   {\"}		 <       > " \
				dst { {\&amp;} {\&quot;} {\&lt;} {\&gt;} } {
					regsub -all $src $str $dst str
				}
			return $str
		}
	}


	#
	# read_css_file - parse and read in a CSS file so we can
	#  recognize CSS info and emit it in appropriate places
	#
	method read_css_file {} {
		if {"$css_file" != ""} {
			if {![catch {open [virtual_filename $css_file]} fp]} {
				set contents [read $fp]
				close $fp
			}
		} else {
			foreach file $css_files {
				if {![catch {open [virtual_filename $file]} fp]} {
					set css_file $file
					set contents [read $fp]
					close $fp
				}
			}
		}
		if ![info exists contents] {
			return
		}
		if {[catch {array set tmpArray $contents}]} { return }
		foreach class [array names tmpArray] {
			set cssArray([string toupper $class]) $tmpArray($class)
		}
	}

	#
	# get_css_class - figure out which CSS class we want to use.  
	# If class exists, we use that.	 If not, we use default.
	#
	method get_css_class {tag default class} {

		# if tag.class exists, use that
		if {[info exists cssArray([string toupper $tag.$class])]} {
			return $class
		}

		# if .class exists, use that
		if {[info exists cssArray([string toupper .$class])]} { 
			return $class 
		}

		# use the default
		return $default
	}

	#
	# parse_css_class - given a class and the name of an array, parse
	# the named CSS class (read from the style sheet) and return it as
	# key-value pairs in the named array.
	#
	method parse_css_class {class arrayName} {

		# if we don't have an entry for the specified class, give up
		if {![info exists cssArray($class)]} { 
			return
		}

		# split CSS entry on semicolons, for each one...
		upvar 1 $arrayName array
		foreach line [split $cssArray($class) \;] {

			# trim leading and trailing spaces
			set line [string trim $line]

			# split the line on a colon into property and value
			lassign [split $line :] property value

			# map the property to space-trimmed lowercase and
			# space-trim the value, then store in the passed array
			set property [string trim [string tolower $property]]
			set value [string trim $value]
			set array($property) $value
		}
	}

	#
	# button_image_src - return the value of the image-src element in
	# the specified class (from the CSS style sheet), or an empty
	# string if there isn't one.
	#
	method button_image_src {class} {
		set class [string toupper input.$class]
		parse_css_class $class array
		if {![info exists array(image-src)]} { 
			return 
		}
		return $array(image-src)
	}

	# state - return a list of name-value pairs that represents the current
	# state of the query, which can be used to properly populate links
	# outside STDisplay.
	method state {} {
		set state {}
		foreach var {mode query by how sort rev num page} {
			if [info exists response($var)] {
				lappend state $var $response($var)
			}
		}
		return $state
	}

	# DName - convert a field name to a display name
	protected method DName {fld} {
		if {[info exists NameTextMap($fld)]} {
			return $fld
		}
		if {[info exists FieldNameMap($fld)]} {
			return [$FieldNameMap($fld) text]
		}
		if {"$fld" == "_key"} {
			return "-key-"
		}
		return $fld
	}

	# FName - convert a display or column to a field name
	protected method FName {fld {complain 1}} {
		if {[info exists NameTextMap($fld)]} {
			set fld $NameTextMap($fld)
		}

		if {[info exists FieldNameMap($fld)]} {
			set fld $FieldNameMap($fld)
		}

		if {[lsearch $fields $fld] < 0} {
			if {$complain} {
				return -code error "No field name for $fld"
			} else {
				return ""
			}
		}
		return $fld
	}

	# CName - convert a field or column to a canonical name
	protected method CName {fld {complain 1}} {
		if {[info exists NameTextMap($fld)]} {
			return $NameTextMap($fld)
		}

		if {[info exists FieldNameMap($fld)]} {
			return $fld
		}

		if {[lsearch $fields $fld] < 0} {
			if {"$fld" == "-key-"} {
				if {[llength $keyfields] == 1} {
					return [lindex $keyfields 0]
				} else {
					return _key
				}
			}

			if {$complain} {
				return -code error "No field name for $fld"
			}
			return ""
		}
		return [$fld name]
	}

	method show {} {
		if {[llength $fields] <= 0} {
			foreach key $keyfields {
				if {"$key" == "_key"} {
					field $key -text "Key"
				} else {
					set text $key
					regsub -all {_} $text { } text
					field $key -text [string totitle $text]
				}
			}

			foreach fld [$table fields] {
				if {[lsearch $keyfields $fld] < 0} {
					set text $fld
					regsub -all {_} $text { } text
					field $fld -text [string totitle $text]
				}
			}
		}

		if {[llength $fields] <= 0} {
			return -code error "No fields defined for display."
		}

		# If readonly get rid of write functions, sanitize mode
		if {$readonly} {
			set skipfunctions $writefunctions
			if [info exists response(mode)] {
				if {[lsearch $writefunctions $response(mode)] >= 0} {
					set response(mode) List
				}
			}
		} else {
			set skipfunctions {}
		}

		# If no details, get rid of Details
		if {!$details} {
			lappend skipfunctions Details
		}

		if {[llength $skipfunctions]} {
			foreach list {functions rowfunctions} {
				set new {}
				foreach fun [set $list] {
					if {[lsearch $skipfunctions $fun] < 0} {
						lappend new $fun
					}
				}
				set $list $new
			}
		}

		# if there's a mode in the response array, use that, else leave mode
		# as the default (List unless caller specified otherwise)
		if {[info exists response(mode)]} {
			set mode $response(mode)
			if {[string match "*-*" $mode]} {
				set mode List
			} elseif {[string match {*[+ ]*} $mode]} {
				set mode List
				add_search_to_selection
			}
			set response(mode) $mode
		}
		puts "<!--Generated by $this show, mode=$mode-->"

		# sanitize "by":
		# If it's empty, remove it.
		# If it's a label, change it to a field
		if [info exists response(by)] {
			if {"$response(by)" == ""} {
				unset response(by)
			} else {
				set response(by) [DName $response(by)]
			}
		}
		
		# if there was a request to generate a CSV file, generate it
		if {[info exists response(ct_csv)]} {
			gencsvfile $response(ct_csv)
			if $csvredirect {
				headers redirect $csvurl
				destroy
				return
			}
		}

		# if there is a style sheet defined, emit HTML to reference it
		if {![lempty $css_file]} {
			puts "<LINK REL=\"stylesheet\" TYPE=\"text/css\" HREF=\"$css_file\">"
		}

		# put out the table header
		puts {<TABLE WIDTH="100%" CLASS="DIO">}
		puts {<TR CLASS="DIO">}
		puts {<TD VALIGN="center" CLASS="DIO">}

		# if mode isn't Main and persistentmain is set (the default),
		# use Main
		if {$mode != "Main" && $persistentmain} { 
			Main 
		}

		if {![is_function $mode]} {
			puts "<H2>Invalid function '$mode'</H2>"
			puts "
		<P>This may be due to an error in an external link
		or in this web page. You may be able to use the back
		button in your browser to return to the previous page
		and try this query again. If you continue to get this
		error, please contact the operator of this system.</P>"
			puts "</TD>"
			puts "</TR>"
			puts "</TABLE>"
			return
		}

		if {[catch [list $this $mode] error]} {
			puts "</TD>"
			puts "</TR>"
			puts "</TABLE>"
			if !$trap_errors {
				if {$cleanup} { destroy }
				error $error $::errorInfo
			}
			puts "<H2>Internal Error</H2>"
			handle_error "$this $mode => $error"
		}

		puts "</TD>"
		puts "</TR>"
		puts "</TABLE>"

		if {$cleanup} { destroy }
	}

	method showview {} {
		puts {<TABLE CLASS="DIOView">}
		set row 0
		foreach field $fields {
			$field showview [lindex {"" "Alt"} $row]
			set row [expr 1 - $row]
		}
		puts "</TABLE>"
	}

	protected method hide_hidden_vars {f} {
		foreach var [array names hidden] {
			$f hidden $var -value [escape_cgi $hidden($var)]
		}
	}

	protected method hide_selection {f {op ""} {val ""}} {
		if {"$op" == "+"} {
			set all 1
		} else {
			set all 0
		}
		set selection [get_selection $all]

		if {"$op" == "-"} {
			set first [lsearch $selection $val]
			if {$first >= 0} {
				set selection [lreplace $selection $first $first]
			}
		}

		$f hidden ct_sel -value [escape_cgi $selection]
	}

	protected method hide_cgi_vars {f args} {
		# Special cases first
		if [info exists response(mode)] {
			set val $response(mode)

			if [string match {*[+ -]*} $val] {
				set val [lindex {List Search} [info exists response(query)]]
			}
			$f hidden mode -value [escape_cgi $val]
		}

		# Just copy the rest
		foreach cgi_var {query by how sort rev num} {
			if {[lsearch $args $cgi_var] < 0} {
				if [info exists response($cgi_var)] {
					$f hidden $cgi_var -value [escape_cgi $response($cgi_var)]
				}
			}
		}
	}

	#
	# showform - emit a form for inserting a new record
	#
	# response(by) will contain whatever was in the "where" field
	# response(query) will contain whatever was in the "is" field
	#
	method showform {} {
		get_field_values array

		set save [button_image_src DIOFormSaveButton]
		set cancel [button_image_src DIOFormCancelButton]

		$form start -method post -name save_form
		#$form hidden pizza -value pepperoni
		hide_hidden_vars $form
		hide_selection $form
		$form hidden mode -value Save

		if [info exists response(mode)] {
			$form hidden DIODfromMode -value [escape_cgi $response(mode)]
		}

		$form hidden DIODkey -value [escape_cgi [makekey array]]
		puts {<TABLE CLASS="DIOForm">}

		# emit the fields for each field using the showform method
		# of the field.	 if they've typed something into the
		# search field and it matches one of the fields in the
		# record (and it should), put that in as the default
		foreach field $fields {
			set name [$field name]

			if [info exists alias($name)] { 
				continue
			}

			if {[info exists response(by)] && $response(by) == $name} {
				if {![$field readonly] && $response(query) != ""} {
					$field value $response(query)
				}
			}
			$field showform
		}
		puts "</TABLE>"

		puts {<TABLE CLASS="DIOFormSaveButton">}
		puts {<TR CLASS="DIOFormSaveButton">}
		puts {<TD CLASS="DIOFormSaveButton">}

		if {![lempty $save]} {
			$form image save -src $save -class DIOFormSaveButton
		} else {
			$form submit save.x -value "Save" -class DIOFormSaveButton
		}
		puts "</TD>"
		puts {<TD CLASS="DIOFormSaveButton">}

		if {![lempty $cancel]} {
			$form image cancel -src $cancel -class DIOFormSaveButton
		} else {
			$form submit cancel.x -value "Cancel" -class DIOFormCancelButton
		}
		puts "</TD>"
		puts "</TR>"
		puts "</TABLE>"

		$form end
	}

	method page_buttons {end {count 0}} {
		if {$pagesize <= 0} { return }

		if {![info exists response(page)]} { set response(page) 1 }

		set pref DIO$end
		if {!$count} {
			set count [perform request]
		}

		set pages [expr ($count + $pagesize - 1) / $pagesize]

		if {$pages <= 1} {
			return
		}

		set first [expr $response(page) - 3]
		if {$first > $pages - 5} {
			set first [expr $pages - 5]
		}

		if {$first > 1} {
			lappend pagelist 1 1

			if {$first > 10} {
				lappend pagelist ".." 0
				set mid [expr $first / 2]
				if {$mid > 20 && $response(page) > $pages - 20} {
					set quarter [expr $mid / 2]
					lappend pagelist $quarter $quarter
					lappend pagelist ".." 0
				}

				if {$first < $pages - 4} {
					set first [expr $response(page) - 1]
				}

				lappend pagelist $mid $mid
				if {$first - $mid > 10 && $response(page) > $pages - 20} {
					lappend pagelist ".." 0
					set quarter [expr ( $first + $mid ) / 2]
					lappend pagelist $quarter $quarter
				}
			}

			if {$first > 3} {
				lappend pagelist ".." 0
			} elseif {$first > 2} {
				lappend pagelist 2 2
			}
		} else {
			set first 1
		}

		set last [expr $response(page) + 3]
		if {$last < $pages - 10 && $last > 3} {
			set last [expr $response(page) + 1]
		}

		if {$last < 5} {
			set last 5
		}

		if {$last > $pages} {
			set last $pages
		}

		for {set i $first} {$i <= $last} {incr i} {
			lappend pagelist $i $i
		}

		if {$last < $pages} {
			if {$last < $pages - 2} {
				lappend pagelist ".." 0
			} elseif {$last < $pages - 1} {
				incr last
				lappend pagelist $last $last
			}

			if {$last < $pages - 10} {
				set mid [expr ( $pages + $last ) / 2]
				if {$last < $mid - 10 && $response(page) < 20} {
					set quarter [expr ( $mid + $last ) / 2]
					lappend pagelist $quarter $quarter
					lappend pagelist ".." 0
				}

				lappend pagelist $mid $mid
				lappend pagelist ".." 0
				if {$mid < $pages - 20 && $response(page) < 20} {
					set quarter [expr ( $mid + $pages ) / 2]
					lappend pagelist $quarter $quarter
					lappend pagelist ".." 0
				}
			}
			lappend pagelist $pages $pages
		}

		foreach {n p} $pagelist {
			if {$p == 0 || $p == $response(page)} {
				lappend navbar $n
			} else {
				set html "<A HREF=\""
				set list {}
				
				foreach var {mode query by how sort rev num} {
					if {[info exists response($var)]} {
						lappend list $var $response($var)
					}
				}
				
				lappend list page $p
				append html [document $list]
				append html "\">$n</A>"
				lappend navbar $html 
			}
		}

		if {"$end" == "Bottom"} {
			puts "<BR/>"
		}
		
		set class [get_css_class TABLE DIONavButtons ${pref}NavButtons]
		puts "<TABLE WIDTH=\"100%\" CLASS=\"$class\">"
		puts "<TR CLASS=\"$class\">"
		puts "<TD CLASS=\"$class\">"
		puts "<FONT SIZE=-1>"
		
		if {"$end" == "Top"} {
			puts "$count records; page:"
		} else {
			puts "Go to page"
		}
		
		foreach link $navbar {
			puts "$link&nbsp;"
		}
		
		puts "</FONT>"
		puts "</TD>"
		
		if {"$end" == "Top" && $pages>10} {
			set f [::form #auto]
			$f start -method get
			hide_hidden_vars $f
			hide_selection $f
			hide_cgi_vars $f
			puts "<TD ALIGN=RIGHT>"
			puts "<FONT SIZE=-1>"
			puts "Jump to"
			$f text page -size 4 -value $response(page)
			$f submit submit -value "Go"
			puts "</FONT>"
			puts "</TD>"
			$f end
		}
		puts "</TR>"
		puts "</TABLE>"
		if {"$end" == "Top"} {
			puts "<BR/>"
		}
	}
	

	method rowheader {{total 0}} {
		set fieldList $fields
		if {![lempty $rowfields]} {
			set fieldList $rowfields
		}
		
		set rowcount 0

		puts "<P>"

		if {$topnav} {
			page_buttons Top $total
		}

		puts {<TABLE BORDER WIDTH="100%" CLASS="DIORowHeader">}
		puts {<TR CLASS="DIORowHeader">}
		set W [expr {100 / [llength $fieldList]}]
		
		foreach field $fieldList {
			set name [$field name]
			set text [$field text]

			regsub -all $labelsplit $text "<BR>" text
			set col_title ""
			set col_title_text $text

			if [info exists hovertext($name)] {
				set col_title " title=\"$hovertext($name)\""
				set col_title_text "<span$col_title>$text</span>"
			}

			if {![sortable $name]} {
				set html $col_title_text
			} else {
				set html ""
				set list {}

				foreach var {mode query by how num} {
					if {[info exists response($var)]} {
						lappend list $var $response($var)
						set sep "&"
					}
				}

				lappend list sort $name
				set a_attr ""

				if {[info exists response(sort)] && "$response(sort)" == "$name"} {
					set rev 1
					if {[info exists response(rev)]} {
						set rev [expr 1 - $response(rev)]
					}

					lappend list rev $rev
					append html "$col_title_text&nbsp;"

					set desc $rev
					if [info exists order($name)] {
						switch -glob -- [string tolower $order($name)] {
							desc* {
								set desc [expr 1 - $desc]
							}
						}
					}

					set text [lindex $arrows $desc]
					set a_attr { class="DIOArrow"}
				}
				append html "<A HREF=\""
				append html [document $list]
				append html "\"$a_attr$col_title>$text</A>"
			}
			set class [get_css_class TH DIORowHeader DIORowHeader-$name]
			puts "<TH CLASS=\"$class\" WIDTH=\"$W%\">$html</TH>"
		}

		if {![lempty $rowfunctions] && "$rowfunctions" != "-"} {
			puts {<TH CLASS="DIORowHeaderFunctions" WIDTH="0%">&nbsp;</TH>}
		}
		puts "</TR>"
	}

	private method altrow {} {
		incr rowcount
		if !$alternaterows { return "" }
		if {$rowcount % 2} { return "" }
		return Alt
	}

	method showrow {arrayName} {
		upvar 1 $arrayName a

		set alt [altrow]

		set fieldList $fields
		if {![lempty $rowfields]} {
			set fieldList $rowfields
		}

		puts "<TR CLASS=\"DIORowField$alt\">"
		foreach field $fieldList {
			set name [$field name]
			set column $name

			if [info exists alias($name)] {
				set column $alias($name)
			}

			set class [get_css_class TD DIORowField$alt DIORowField$alt-$name]

			set text [column_value $name a]

			if ![string length $text] {
				set text "&nbsp;"
			}

			set attr NOWRAP
			if [info exists attributes($name)] {
				append attr " $attributes($name) "
				if [regsub -nocase { +wrap +} " $attr " { } attr] {
					set attr $attributes($name)
				}
				set attr [string trim $attr]
			}
			puts "<TD CLASS=\"$class\" $attr>$text</TD>"
		}

		if {![lempty $rowfunctions] && "$rowfunctions" != "-"} {
			set f [::form #auto]
			$f start -method get
			puts "<TD NOWRAP CLASS=\"DIORowFunctions$alt\">"
			hide_hidden_vars $f
			hide_selection $f
			$f hidden query -value [escape_cgi [makekey a]]
			$f hidden by -value [escape_cgi $key]

			if {[llength $rowfunctions] > 2} {
				$f select mode -values $rowfunctions -class DIORowFunctionSelect$alt
				$f submit submit -value "Go" -class DIORowFunctionButton$alt
			} else {
				foreach func $rowfunctions {
					$f submit mode -value $func -class DIORowFunctionButton$alt
				}
			}
			puts "</TD>"
			$f end
		}

		puts "</TR>"
	}

	method rowfooter {{total 0}} {
		if [array exists lastrow] {
			set rowclass "DIORowField[altrow]"

			set fieldList $fields
			if {![lempty $rowfields]} { set fieldList $rowfields }

			set skip 0
			set row {}

			foreach field $fieldList {
				set name [$field name]
				if [info exists lastrow($name)] {
					if {$skip > 0} {
						lappend row "<TD CLASS=\"$rowclass\" span=\"$skip\">&nbsp;</TD>"
					}
					set skip 0
					lappend row "<TD CLASS=\"$rowclass\">$lastrow($name)</TD>"
				} else {
					incr skip
				}
			}

			if [llength $row] {
				if {![lempty $rowfunctions] && "$rowfunctions" != "-"} {
					incr skip
				}

				if {$skip > 0} {
					lappend row "<TD CLASS=\"$rowclass\" span=\"$skip\">&nbsp;</TD>"
				}

				puts "<TR CLASS=\"rowclass\">"
				puts [join $row " "]
				puts "</TR>"
			}
		}
		puts "</TABLE>"

		if {$bottomnav} {
			page_buttons Bottom $total
		}
	}

	## Check field's "sortability"
	protected method sortable {name} {
		## If allowsort is false, nothing is sortable.
		if !$allowsort {
			return 0
		}

		## If there's a list of sortfields, it's only sortable if it's in that
		if {![lempty $sortfields]} {
			if {[lsearch $sortfields $name] < 0} {
				return 0
			}
		}

		## Otherwise if it's searchable, it's sortable
		return [searchable $name]
	}

	## Check field's "searchability"
	protected method searchable {name} {
		## If it's marked as searchable
		if {[lsearch $searchfields $name] < 0} {
			return 1
		}

		## If it's filtered and the filter isn't reversible one way or another
		if {
			[info exists filters($name)] &&
			![info exists unfilters($name)] &&
			![string match "*_ok" $filters($name)]
		} {
			return 0
		}

		## If it's an alias field
		if [info exists alias($name)] {
			return 0
		}

		# Otherwise it's searchable
		return 1
	}

	## Define a new function.
	method function {name} {
		lappend allfunctions $name
	}

	## Define a field in the object.
	method field {name args} {
		import_keyvalue_pairs data $args

		set class STDisplayField
		if {[info exists data(type)]} {
			if {![lempty [::itcl::find classes *STDisplayField_$data(type)]]} {
				set class STDisplayField_$data(type)
			}
		}

		set field [
				   eval [
						 list $class #auto -name $name -display $this -form $form
						] $args
				  ]
		lappend fields $field
		lappend allfields $field
		lappend allnames $name
		
		set FieldNameMap($name) $field
		set NameTextMap([$field text]) $name
	}

	private method make_limit_selector {values _selector {_array ""}} {
		if ![info exists limit] { return 0 }

		upvar 1 $_selector selector
		if {"$_array" != ""} {
			upvar 1 $_array array
		}
		
		foreach val $values name $keyfields {
			lappend selector [list = $name $val]
		}

		foreach {k v} $limit {
			regsub {^-} $k "" k
			lappend selector [list = $k $v]
			set array($k) $v
		}

		return 1
	}

	# Simplify a "compare" operation in a search to make it compatible with 
	# standard ctables
	method simplify_compare {_compare} {
		upvar 1 $_compare compare

		set new_compare {}
		set changed 0
		foreach list $compare {
			set op [lindex $list 0]

			if {"$op" == "<>"} {
				set list [concat {!=} [lrange $list 1 end]]
				set changed 1
			} elseif {[regexp {^(-?)(.)match} $op _ not ch]} {
				set op [lindex {match notmatch} [string length $not]]
				unset -nocomplain fn
				switch -exact -- [string tolower $ch] {
					u { append op _case; set fn toupper }
					l { append op _case; set fn tolower }
					x { append op _case }
				}

				set pat [lindex $list 2]
				if [info exists fn] {
					set pat [string $fn $pat]
				}

				set list [concat $op [lindex $list 1] [list $pat]] 
				set changed 1
			}
			lappend new_compare $list
		}

		if {$changed} {
			set compare $new_compare
		}
	}

	# Perform an extended "search" request bundled in an array
	method perform {_request args} {
		upvar 1 $_request request
		array set search [array get request]
		array set search $args
		uplevel 1 [list $table search] [array get search]
	}

	method fetch {keyVal arrayName} {
		upvar 1 $arrayName array
		if [make_limit_selector $keyVal selector] {
			set result [$table search -compare $selector -array_with_nulls array]
		} else {
			set list [$table array_get_with_nulls $keyVal]
			set result [llength $list]
			if {$result} {
				array set array $list
			}
		}
		return $result
	}

	# SHorthand to make a key from table
	method makekey {arrayName} {
		upvar 1 $arrayName array

		set list {}
		foreach kf $keyfields {
			if [info exists array($kf)] {
				lappend list $array($kf)
			}
		}

		if {[llength $list] == 0} {
			if [info exists array(_key)] {
				return $array(_key)
			} else {
				return -code error "No key in array"
			}
		}

		if {[llength $list] == 1} {
			return [lindex $list 0]
		}

		return $list
	}

	# SHorthand to store table
	method store {arrayName} {
		upvar 1 $arrayName array
		if [make_limit_selector {} selector array] {
			if ![$table search -compare $selector -key _] {
				return 0
			}
		}
		return [$table store [array get array]]
	}

	method delete {keyVal} {
		if [make_limit_selector $keyVal selector] {
			if ![$table search -compare $selector -key keyVal] {
				return 0
			}
		}
		return [$table delete $keyVal]
	}

	method pretty_fields {list} {
		set labels {}
		foreach field $list {
			lappend labels [$field text]
		}
		return $labels
	}

	method set_field_values {arrayName} {
		upvar 1 $arrayName array

		# for all the elements in the specified array, try to invoke
		# the field for that name, invoking the method "value" to
		# set the value to the specified value
		foreach name [array names array] {
			if [info exists FieldNameMap($name)] {
				$FieldNameMap($name) configure -value $array($name)
			}
		}
	}

	method get_field_values {arrayName} {
		upvar 1 $arrayName array

		foreach field $allfields {
			set v [$field value]
			set n [$field name]
			if {"$v" == "" && [info exists blankval($n)]} {
				if {"$blankval($n)" != "$v"} continue
			}
			set array($n) $v
		}
	}

	method make_request {_request} {
		upvar 1 $_request request
		unset -nocomplain request
		array unset request
	}

	method set_limit {_request {selector {}}} {
		upvar 1 $_request request

		if [info exists request(-compare)] {
			set request(-compare) [concat $request(-compare) $selector]
		} else {
			set request(-compare) $selector
		}

		make_limit_selector {} request(-compare)
		if [llength $request(-compare)] {
			return 1
		}

		unset request(-compare)
		return 0
	}

	method set_order {_request} {
		upvar 1 $_request request

		if {"[set sort [request_to_sort]]" != ""} {
			set request(-sort) $sort
		}
	}

	method set_page {_request} {
		upvar 1 $_request request

		set recno [get_offset]
		if {$recno > 0} {
			set request(-offset) $recno
		}

		if {$pagesize > 0} {
			set request(-limit) $pagesize
		}
	}

	method gencsvfile {selector} {
		if {"$csvfile" == ""} {
			return
		}

		::stapi::display::load_csv

		make_request request
		set_limit request
		set_order request

		if [catch {set fp [open $csvfile w]} err] {
			$r destroy
			return
		}

		set columns {}

		foreach field $fields {
			set name [$field name]
			# Don't put alias fields in unless there's a csv filter for them
			if [info exists alias($name)] {
				if ![info exists csvfilters($name)] {
					continue
				}
			}
			lappend columns $name
			set label [$field text]
			regsub -all { *<[^>]*> *} $label " " label
			lappend textlist $label
		}

		if [info exists textlist] {
			puts $fp [::csv::join $textlist]
		}

		perform request -array_with_nulls a -key k -code {

			# If there's no fields defined, then use the columns we got from
			# the query and put their names out as the first line

			if {![llength $columns]} {
				set columns [array names a]
				puts $fp [::csv::join $columns]
			}
			set list {}
			foreach name $columns {
				lappend list [column_value $name a csv]
			}
			puts $fp [::csv::join $list]
		}

		close $fp

		$r destroy
	}

	method showcsvform {query} {
		$form start -method get
		puts "<TR CLASS='DIOForm'><TD CLASS='DIOForm' VALIGN='MIDDLE' WIDTH='100%'>"
		# save hidden vars
		hide_hidden_vars $form

		# save form vars so state isn't lost
		foreach {n v} [state] {
			$form hidden $n -value [escape_cgi $v]
		}

		# save search
		hide_selection $form
		# save query for generation
		$form hidden ct_csv -value [escape_cgi $query]

		if $csvredirect {
			set csvlabel "Download CSV file"
		} else {
			set csvlabel "Generate CSV file"
		}

		$form submit submit -value $csvlabel \
			-class DIOMainSubmitButton

		if [file exists $csvfile] {
			if ![catch {file stat $csvfile st}] {
				if $csvredirect {
					puts "Previous:&nbsp;"
				}
				set filename $csvfile
				regsub {^.*/} $filename "" filename
				puts "<A HREF=\"$csvurl\">$filename</A>:"
				puts "$st(size) bytes,"
				puts [clock format $st(mtime) -format "%d-%b-%Y %H:%M:%S"]
			}
		}

		puts "</TD></TR>"
		$form end
	}

	method DisplayRequest {selector} {
		make_request request
		set partial [set_limit request $selector]

		if {!$partial} {
			if {$rows} {
				set total $rows
			} else {
				set total [$table count]
			}
		} else {
			set total [perform request]
		}

		if {$total <= [get_offset]} {
			puts "Could not find any matching records."
			return
		}

		rowheader $total

		set_order request
		set_page request
		perform request -array_with_nulls a -code { showrow a }

		rowfooter $total

		if {"$csvfile" != "" && "$csvurl" != ""} {
			showcsvform $query
		}
	}

	method Main {} {
		puts "<TABLE BORDER='0' WIDTH='100%' CLASS='DIOForm'>"

		display_selection {"&nbsp;"} {}

		set skipfunctions {}
		if {[lsearch $functions Search] >= 0} {
			foreach f "Edit Delete" {
				if {[lsearch $functions $f] >= 0
					&& [lsearch $rowfunctions $f] >= 0} {
					lappend skipfunctions $f
				}
			}
		}

		puts "<TR CLASS='DIOForm'>"
		puts "<TD CLASS='DIOForm' ALIGN='LEFT' VALIGN='MIDDLE' WIDTH='1%' NOWRAP>"

		set selfunctions {}
		foreach f $functions {
			if {"$f" != "List"} {
				if {[lsearch $skipfunctions $f] < 0} {
					lappend selfunctions $f
				}
			} else {
				set listform [::form #auto]
				puts "<DIV STYLE='display:none'>"
				$listform start -method get
				puts "</DIV>"
				hide_hidden_vars $listform
				# hide_selection $listform
				$listform hidden mode -value "List"
				$listform hidden query -value ""
				$listform submit submit -value "Show All" \
					-class DIORowFunctionButton
				puts "<DIV STYLE='display:none'>"
				$listform end
				puts "</DIV>"
			}
		}
		puts "</TD>"
		puts "<TD CLASS='DIOForm' ALIGN='LEFT' VALIGN='MIDDLE' WIDTH='1%' NOWRAP>"

		puts "<DIV STYLE='display:none'>"
		$form start -method get
		puts "</DIV>"
		puts "&nbsp;"

		hide_hidden_vars $form
		hide_selection $form

		if {[llength $selfunctions] > 2} {
			$form select mode -values $selfunctions -class DIOMainFunctionsSelect
			puts "where"
		} else {
			puts "Select:"
		}

		set fieldList $fields
		if {![lempty $searchfields]} { set fieldList $searchfields }

		set first "-column-"
		if [info exists response(by)] {
			set first $response(by)
			if {"$first" == "_key"} {
				set first "-key-"
			}
		}

		set labels [list $first]
		foreach field $fieldList {
			if ![searchable [$field name]] { continue }
			set label [$field text]
			if {"$label" != "$first"} {
				lappend labels $label
			}
		}

		$form select by -values $labels -class DIOMainSearchBy

		puts "</TD>"
		puts "<TD CLASS='DIOForm' ALIGN='LEFT' VALIGN='MIDDLE' WIDTH='1%' NOWRAP>"
		if [string match {*[Ss]earch*} $selfunctions] {
			$form select how -values {"=" "<" "<=" ">" ">=" "<>"}
		} else {
			puts "is"
		}

		puts "</TD>"
		puts "<TD CLASS='DIOForm' ALIGN='LEFT' VALIGN='MIDDLE' WIDTH='1%' NOWRAP>"
		if [info exists response(query)] {
			$form text query -value [escape_cgi $response(query)] -class DIOMainQuery
		} else {
			$form text query -value "" -class DIOMainQuery
		}

		puts "</TD>"
		puts "<TD CLASS='DIOForm' ALIGN='LEFT' VALIGN='MIDDLE' WIDTH='100%' NOWRAP>"

		if [string match {*[sS]earch*} $selfunctions] {
			display_add_button $form
		}

		if {[llength $selfunctions] > 2} {
			$form submit submit -value "GO" -class DIOMainSubmitButton
		} else {
			foreach f $selfunctions {
				$form submit mode -value $f -class DIOMainSubmitButton
			}
		}

		if {![lempty $numresults]} {
			puts "</TD></TR>"
			puts "<TR CLASS='DIOForm'><TD CLASS='DIOForm'>Results per page: "
			$form select num -values $numresults -class DIOMainNumResults
		}

		puts "</TD></TR>"

		puts "<DIV STYLE='display:none'>"
		$form end
		puts "</DIV>"
		puts "</TABLE>"
	}

	protected method parse_order {name list {reverse 0}} {
		set descending 0
		foreach word $list {
			if [info exists nextvar] {
				set $nextvar $word
				unset nextvar
				continue
			}
			
			switch -glob -- $word {
				asc* { set descending 0 }
				desc* { set descending 1 }
				null* { set nextvar null }
			}
		}

		# ctables doesn't handle this yet
		#	if [info exists null] {
		#		set field "COALESCE($field,$null)"
		#	}

		if {$reverse} {
			set descending [expr 1 - $descending]
		}
		if $descending {
			set name -$name
		}

		return $name
	}

	method request_to_sort {} {
		if {[info exists response(sort)] && ![lempty $response(sort)]} {
			set name [CName $response(sort) 0]
			if {"$name" == ""} {
				unset response(sort)
			} else {
				set rev 0
				if {[info exists response(rev)] && $response(rev)} {
					set rev 1
				}

				set ord ascending
				if [info exists order($name)] {
					set ord $order($name)
				}

				return [list [parse_order $name $ord $rev]]
			}
		}

		if {"$defaultsortfield" != ""} {
			if [regexp {^-(.*)} $defaultsortfield _ name] {
				set ord descending
			} else {
				set ord ascending
				set name $defaultsortfield
			}
			return [list [parse_order [CName $name] $ord]]
		}

		return {}
	}

	method get_offset {} {
		if {$pagesize <= 0} { return 0 }
		if {![info exists response(page)]} { return 0 }
		return [expr ($response(page) - 1) * $pagesize]
	}

	protected method display_selection {precells postcells} {
		set selection [get_selection 0]
		if {![llength $selection]} {
			return
		}
		set span [expr {4 + [llength $precells] + [llength $postcells]}]
		puts "<TR><TD CLASS='DIOFormHeader' COLSPAN='$span'>"
		puts {<font color="#444444"><b>Current filters:</b></font>}
		puts {</TD></TR>}
		foreach search $selection {
			foreach {how col what} $search { break }
			puts {<TR CLASS="DIOSelect">}
			set f [::form #auto]
			puts {<DIV STYLE="display:none">}
			$f start -method get
			puts "</DIV>"
			hide_hidden_vars $f
			hide_cgi_vars $f mode
			hide_selection $f - $search
			if {[string match "*-*match*" $how]} {
				set how "is not like"
			} elseif {[string match "*match*" $how]} {
				set how "is like"
			}

			foreach cell $precells {
				puts "<TD CLASS='DIOSelect' WIDTH='1%'>$cell</TD>"
			}
			foreach \
				cell [list [DName $col] $how $what] \
				align {right middle left} \
				{
					puts "<TD CLASS='DIOSelect' ALIGN='$align' WIDTH='1%'>[escape_cgi $cell]</TD>"
				}
			puts {<TD CLASS="DIOSelect" WIDTH="100%" ALIGN="LEFT">}
			$f submit mode -value "-" -class DIOForm
			puts "</TD>"
			foreach cell $postcells {
				puts "<TD CLASS='DIOSelect'>$cell</TD>"
			}
			puts "<DIV STYLE='display:none'>"
			$f end
			puts "</DIV>"
			puts "</TR>"
		}
		puts "<TR><TD CLASS='DIOFormHeader' COLSPAN='$span'>"
		puts ""
		puts "</TD></TR>"
	}

	protected method display_add_button {f} {
		$f submit mode -value "+" -class DIOForm
	}

	protected method add_search_to_selection {} {
		set search_list [get_selection 1]
		array unset ct_selection
	}

	protected method get_selection {searching} {
		if [info exists ct_selection($searching)] {
			return $ct_selection($searching)
		}

		if ![info exists search_list] {
			if [info exists response(ct_sel)] {
				set search_list $response(ct_sel)
				if {[llength $search_list] == 3
					&& [llength [lindex $search_list 0]] == 1} {
					set search_list [list $search_list]
				}
			} else {
				set search_list {}
			}
		}
		set ct_selection(0) $search_list
		if !$searching {
			return $search_list
		}
		set new_list $search_list

		if [info exists response(by)] {
			set name [CName $response(by)]

			set what $response(query)

			set how "="
			if {[info exists response(how)] && [string length $response(how)]} {
				set how $response(how)
			}

			if {[string match {*[*?]*} $what]} {
				if {"$how" == "="} {
					set how "match"
				} elseif {"$how" == "<>"} {
					set how "notmatch"
				}
			}
			if {[string match "*like*" $how] || [string match "*match*" $how]} {
				switch -glob -- $how {
					*not* { set how "notmatch" }
					-*	  { set how "match-" }
					default { set how "match" }
				}
				if {[info exists case($name)]} {
					switch -glob -- [string tolower $case(name)] {
						u* {
							set what [string toupper $what]
							append how "_case"
						}
						l* {
							set what [string tolower $what]
							append how "_case"
						}
						x* {
							append how "_case"
						}
					}
				}
			}

			if {"$how" == "<>"} {
				set how "!="
			}

			set search [list $how $name $what]
			if {[lsearch $new_list $search] < 0} {
				lappend new_list [list $how $name $what]
			}
		}
		set ct_selection(1) $new_list
		return $new_list
	}

	method Search {} {
		display_request_with_selection [get_selection 1]
	}

	method List {} {
		display_request_with_selection [get_selection 0]
	}

	protected method display_request_with_selection {selection} {
		set request {}
		foreach target $selection {
			foreach {how column what} $target { break }

			if {[info exists unfilters($column)] && "$unfilters($column)" != "-"} {
				set what [$unfilters($column) $what]
			}

			lappend request [list $how $column $what]
		}
		DisplayRequest $request
	}

	method Add {} {
		showform
	}

	method Edit {} {
		if {![fetch $response(query) array]} {
			puts "That record does not exist in the database."
			return
		}

		set_field_values array

		showform
	}

	##
	## When we save, we want to set all the fields' values and then get
	## them into a new array.  We do this because we want to clean any
	## unwanted variables out of the array but also because some fields
	## have special handling for their values, and we want to make sure
	## we get the right value.
	##
	method Save {} {
		if {[info exists response(cancel.x)]} {
			Cancel
			return
		}

		## We need to see if the key exists.  If they are adding a new
		## entry, we just want to see if the key exists.  If they are
		## editing an entry, we need to see if they changed the keyfield
		## while editing.  If they didn't change the keyfield, there's no
		## reason to check it.
		set adding [expr {$response(DIODfromMode) == "Add"}]
		if {$adding} {
			set keyVal [makekey response]
			set list [$table array_get_with_nulls $keyVal]
			if {[llength $list]} {
				array set a $list
			}
		} else {
			set keyVal $response(DIODkey)
			set newkey [makekey response]

			## If we have a new key, and the newkey doesn't exist in the
			## database, we are moving this record to a new key, so we
			## need to delete the old key.
			if {$keyVal != $newkey} {
				if {![fetch $newkey a]} {
					delete $keyVal
				}
			}
		}

		if {[array exists a]} {
			puts "That record ($keyVal) already exists in the database."
			return
		}

		set_field_values response
		get_field_values storeArray

		# Don't try and write readonly values.
		foreach name [array names storeArray] {
			if [[FName $name] readonly] {
				unset storeArray($name)
			}
		}

		# Because an empty string is not EXACTLY a null value and not always
		# a legal value, if the array element is empty and we're adding a
		# new row or there is no legal null value for the type
		# remove it from the array -- PdS Jul 2006
		foreach {n v} [array get storeArray] {
			if {"$v" == ""} {
				if $adding {
					unset storeArray($n)
				} elseif {![info exists FieldNameMap($n)]} {
					unset storeArray($n)
				} elseif {![$FieldNameMap($n) null_ok]} {
					unset storeArray($n)
				}
			}
		}

		store storeArray
		headers redirect [document]
	}

	# return a URL containing all of the current state
	protected method document {{extra {}}} {
		set url $document
		set ch "?"
		foreach {n v} $extra {
			append url $ch $n = [escape_url $v]
			set ch "&"
		}
		foreach {n v} [array get hidden] {
			append url $ch $n = [escape_url $v]
			set ch "&"
		}
		set selection [get_selection 0]
		if [llength $selection] {
			append url $ch ct_sel = [escape_url $selection]
			set ch "&"
		}
		return $url
	}

	method Delete {} {
		if {![fetch $response(query) array]} {
			puts "That record does not exist in the database."
			return
		}

		if {!$confirmdelete} {
			DoDelete
			return
		}

		puts "<CENTER>"
		puts {<TABLE CLASS="DIODeleteConfirm">}
		puts "<TR CLASS='DIODeleteConfirm'>"
		puts {<TD COLSPAN=2 CLASS="DIODeleteConfirm">}
		puts "Are you sure you want to delete this record from the database?"
		puts "</TD>"
		puts "</TR>"
		puts "<TR CLASS='DIODeleteConfirmYesButton'>"
		puts {<TD ALIGN="center" CLASS="DIODeleteConfirmYesButton">}
		set f [::form #auto]
		$f start -method post
		hide_hidden_vars $f
		hide_selection $f
		$f hidden mode -value DoDelete
		$f hidden query -value [escape_cgi $response(query)]
		$f submit submit -value Yes -class DIODeleteConfirmYesButton
		$f end
		puts "</TD>"
		puts {<TD ALIGN="center" CLASS="DIODeleteConfirmNoButton">}
		set f [::form #auto]
		$f start -method post
		hide_hidden_vars $f
		hide_selection $f
		$f submit submit -value No -class "DIODeleteConfirmNoButton"
		$f end
		puts "</TD>"
		puts "</TR>"
		puts "</TABLE>"
		puts "</CENTER>"
	}

	method DoDelete {} {
		if [catch {delete $response(query)} err] {
			error "delete $response(query) => $err" $::errorInfo
		}

		headers redirect [document]
	}

	method Details {} {
		if {![fetch $response(query) array]} {
			puts "That record does not exist in the database."
			return
		}

		set_field_values array

		showview
	}

	method Cancel {} {
		headers redirect [document]
	}

	###
	## Define variable functions for each variable.
	###

	private method names2fields {nameList} {
		set fieldList {}
		foreach name $nameList {
			lappend fieldList [FName $name]
		}
		return $fieldList
	}

	protected method fields2names {fieldList} {
		set nameList {}
		foreach field $fieldList {
			lappend nameList [$field name]
		}
		return $nameList
	}

	method fields {{list ""}} {
		if {[lempty $list]} { return [fields2names $fields] }
		set fields [names2fields $list]
	}

	method searchfields {{list ""}} {
		if {[lempty $list]} { return [fields2names $searchfields] }
		set searchfields [names2fields $list]
	}

	method rowfields {{list ""}} {
		if {[lempty $list]} { return [fields2names $rowfields] }
		set rowfields [names2fields $list]
	}
	
	method lastrow {name {value ""}} {
		if [string length $value] {
			set lastrow($name) $value
		} elseif {[info exists lastrow($name)]} {
			set value $lastrow($name)
		}
		return $value
	}

	method alias {name {value ""}} {
		if [string length $value] {
			set alias($name) $value
		} elseif {[info exists alias($name)]} {
			set value $alias($name)
		} else {
			set value $name
		}
		return $value
	}

	protected method column_value {name _row {type ""}} {
		upvar 1 $_row row

		set val ""

		set column $name
		if [info exists alias($name)] {
			set column $alias($name)
		}

		if [info exists row($column)] {
			set val [apply_filter $name $row($column) row $type]
		}

		return $val
	}

	method apply_filter {name val {_row ""} {which ""}} {
		if [info exists ${which}filters($name)] {
			set cmd [list [set ${which}filters($name)] $val]

			if {"$_row" != "" && [info exists ${which}filtercols($name)]} {
				upvar 1 $_row row
				foreach n [set ${which}filtercols($name)] {
					if [info exists row($n)] {
						lappend cmd $row($n)
					}
				}
			}

			set val [eval $cmd]
		}
		return $val
	}

	method filter {name {value ""} args} {
		if [string length $value] {
			set f [uplevel 1 [list namespace which $value]]
			if {"$f" == ""} {
				return -code error "Unknown filter $value"
			}
			set value $f
			set filters($name) $f
			if [llength $args] {
				set filtercols($name) $args
			}
		} elseif {[info exists filters($name)]} {
			set value $filters($name)
		}
		return $value
	}

	method smartfilter {args} {
		uplevel 1 [concat $this filter $args]
	}
	
	method csvfilter {name {value ""} args} {
		if [string length $value] {
			set f [uplevel 1 [list namespace which $value]]
			if {"$f" == ""} {
				return -code error "Unknown filter $value"
			}
			set value $f
			set csvfilters($name) $f
			if [llength $args] {
				set csvfiltercols($name) $args
			}
		} elseif {[info exists csvfilters($name)]} {
			set value $csvfilters($name)
		}
		return $value
	}
	
	method order {name {value ""}} {
		if [string length $value] {
			set order($name) $value
		} elseif {[info exists order($name)]} {
			set value $order($name)
		}
		return $value
	}

	method hovertext {name {value ""}} {
		if [string length $value] {
			set hovertext($name) $value
		} elseif {[info exists hovertext($name)]} {
			set value $hovertext($name)
		}
		return $value
	}
	
	method blankval {name {value ""}} {
		if [string length $value] {
			set blankval($name) $value
		} elseif {[info exists blankval($name)]} {
			set value $blankval($name)
		}
		return $value
	}
	
	method limit {args} {
		if [string length $args] {
			set limit $args
		} elseif {[info exists limit]} {
			set args $limit
		}
		return $args
	}
	
	method case {name {value ""}} {
		if [string length $value] {
			set case($name) $value
		} else {
			if [info exists case($name)] {
				set value $case($name)
			}
		}
		return $value
	}

	method unfilter {name {value ""}} {
		if [string length $value] {
			if {"$value" != "-"} {
				set f [uplevel 1 [list namespace which $value]]
				if {"$f" == ""} {
					return -code error "Unknown filter $value"
				}
				set value $f
			}
			set unfilters($name) $value
		} elseif {[info exists unfilters($name)]} {
			set value $unfilters($name)
		}
		return $value
	}
	
	method attributes {name {value ""}} {
		if [string length $value] {
			set attributes($name) $value
		} elseif {[info exists attributes($name)]} {
			set value $attributes($name)
		}
		return $value
	}
	
	method hidden {name {value ""}} {
		if [string length $value] {
			set hidden($name) $value
		} elseif {[info exists hidden($name)]} {
			set value $hidden($name)
		}
		return $value
	}

	method details {{string ""}} { configvar details $string }
	method readonly {{string ""}} { configvar readonly $string }
	method mode {{string ""}} { configvar mode $string }
	method csvfile {{string ""}} { configvar csvfile $string }

	method title {{string ""}} { configvar title $string }
	method functions {{string "--"}} { configvar functions $string "--" }
	method pagesize {{string ""}} { configvar pagesize $string }
	method form {{string ""}} { configvar form $string }
	method cleanup {{string ""}} { configvar cleanup $string }
	method confirmdelete {{string ""}} { configvar confirmdelete $string }

	method css {{string ""}} { configvar css $string }
	method persistentmain {{string ""}} { configvar persistentmain $string }
	method alternaterows {{string ""}} { configvar alternaterows $string }
	method allowsort {{string ""}} { configvar allowsort $string }
	method sortfields {{string ""}} { configvar sortfields $string }
	method topnav {{string "--"}} { configvar topnav $string "--" }
	method bottomnav {{string "--"}} { configvar bottomnav $string "--" }
	method numresults {{string ""}} { configvar numresults $string }
	method defaultsortfield {{string ""}} { configvar defaultsortfield $string }
	method labelsplit {{string ""}} { configvar labelsplit $string }

	method rowfunctions {{string "--"}} { configvar rowfunctions $string "--" }
	method arrows {{string ""}} { configvar arrows $string }

	method rows {{string 0}} { configvar rows $string 0 }

	## OPTIONS ##

	public variable rows	 0
	public variable title	 ""
	public variable fields	 ""
	public variable searchfields ""
	public variable functions	 "Search List Add Edit Delete Details"
	public variable pagesize	 25
	public variable form	 ""
	public variable cleanup	 1
	public variable confirmdelete 1
	public variable mode	List
	public variable trap_errors	0

	public variable css_file	""	{
		if {![lempty $css_file]} {
			catch {unset cssArray}
			read_css_file
		}
	}

	public variable css_files		{"display.css" "diodisplay.css"} {
		if {![lempty $css_files]} {
			catch {unset cssArray}
			read_css_file
		}
	}

	public variable persistentmain	1
	public variable alternaterows	1
	public variable allowsort		1
	public variable sortfields		""
	public variable topnav		1
	public variable bottomnav		1
	public variable numresults		""
	public variable defaultsortfield	""
	public variable labelsplit		"\n"

	protected variable rowfields	 ""
	public variable rowfunctions "Details Edit Delete"

	public variable details 1
	public variable readonly 0

	public variable response
	public variable cssArray
	public variable document	 ""
	protected variable allfields	{}
	protected variable allnames		{}
	protected variable NameTextMap
	protected variable FieldNameMap
	protected variable writefunctions { Add Edit Delete Save DoDelete }
	public variable allfunctions {
		Search
		List
		Add
		Edit
		Delete
		Details
		Main
		Save
		DoDelete
		Cancel
	}

	# -csv, -csvfile, -csvurl
	# If -csvfile is provided and is in the same directory, gen -csvurl
	public variable csv		0 {
		if {$csv && "$csvfile" == ""} {
			set csvfile "download.csv"
			set csvurl "download.csv"
		}
	}
	public variable csvfile	"" {
		set csv 1
		if {"$csvurl" == ""} {
			if ![regexp {^[.]*/} $csvfile] {
				set csvurl $csvfile
			}
		}
	}
	public variable csvurl ""
	public variable csvredirect	0

	public variable arrows {"&darr;" "&uarr;"}

	private variable blankval
	private variable rowcount
	private variable filters
	private variable alias
	private variable lastrow
	private variable filtercols
	private variable hovertext
	private variable csvfilters
	private variable csvfiltercols
	private variable order
	private variable unfilters
	private variable attributes
	private variable hidden
	private variable limit
	private variable search_list

} ; ## ::itcl::class STDisplay

catch { ::itcl::delete class ::STDisplayField }

#
# STDisplayField object -- defined for each field we're displaying
#
::itcl::class ::STDisplayField {

	constructor {args} {
		## We want to simulate Itcl's configure command, but we want to
		## check for arguments that are not variables of our object.  If
		## they're not, we save them as arguments to the form when this
		## field is displayed.
		import_keyvalue_pairs data $args
		foreach var [array names data] {
			if {![info exists $var]} {
				lappend formargs -$var $data($var)
			} else {
				set $var $data($var)
			}
		}

		# if text (field description) isn't set, prettify the actual
		# field name and use that
		if {[lempty $text]} { set text [pretty [split $name _]] }
	}

	destructor {

	}

	method destroy {} {
		::itcl::delete object $this
	}

	#
	# get_css_class - ask the parent DIODIsplay object to look up
	# a CSS class entry
	#
	method get_css_class {tag default class} {
		return [$display get_css_class $tag $default $class]
	}

	#
	# get_css_tag -- set tag to select or textarea if type is select
	# or textarea, else to input
	#
	method get_css_tag {} {
		switch -- $type {
			"select" {
				set tag select
			}
			"textarea" {
				set tag textarea
			}
			default {
				set tag input
			}
		}
	}

	#
	# pretty -- prettify a list of words by uppercasing the first letter
	#  of each word
	#
	method pretty {string} {
		set words ""
		foreach w $string {
			lappend words \
				[string toupper [string index $w 0]][string range $w 1 end]
		}
		return [join $words " "]
	}

	#
	# configvar - a convenient helper for creating methods that can
	#  set and fetch one of the object's variables
	#
	method configvar {varName string {defval ""}} {
		if {"$string" == "$defval"} { return [set $varName] }
		configure -$varName $string
	}

	#
	# showview - emit a table row of either DIOViewRow, DIOViewRowAlt,
	# DIOViewRow-fieldname (this object's field name), or 
	# DIOViewRowAlt-fieldname, a table data field of either
	# DIOViewHeader or DIOViewHeader-fieldname, and then a
	# value of class DIOViewField or DIOViewField-fieldname
	#
	method showview {{alt ""}} {
		set class [get_css_class TR DIOViewRow$alt DIOViewViewRow$alt-$name]
		puts "<TR CLASS=\"$class\">"

		set class [get_css_class TD DIOViewHeader DIOViewHeader-$name]
		puts "<TD CLASS=\"$class\">$text:</TD>"

		set class [get_css_class TD DIOViewField DIOViewField-$name]
		puts "<TD CLASS=\"$class\">$value</TD>"

		puts "</TR>"
	}

	#
	# showform -- like showview, creates a table row and table data, but
	# if readonly isn't set, emits a form field corresponding to the type
	# of this field
	#
	method showform {} {
		set class [get_css_class TD DIOFormHeader DIOFormHeader-$name]

		puts "<TR CLASS=\"$class\">"
		puts "<TD CLASS=\"$class\">$text:</TD>"

		set class [get_css_class TD DIOFormField DIOFormField-$name]
		puts "<TD CLASS=\"$class\">"
		if {$readonly} {
			puts "$value"
		} else {
			set tag [get_css_tag]
			set class [get_css_class $tag DIOFormField DIOFormField-$name]

			set text $value
			regsub -all "\"" $text {\&quot;} text
			if {$type == "select"} {
				$form select $name -values $values -class $class -value $text
			} else {
				eval $form $type $name -value [list $text] $formargs -class $class
			}
		}
		puts "</TD>"
		puts "</TR>"
	}

	method null_ok {} {
		return [expr {"$type" == "text"}]
	}

	# methods that give us method-based access to get and set the
	# object's variables...
	method display	{{string ""}} { configvar display $string }
	method form	 {{string ""}} { configvar form $string }
	method formargs	 {{string ""}} { configvar formargs $string }
	method name	 {{string ""}} { configvar name $string }
	method text	 {{string ""}} { configvar text $string }
	method type	 {{string ""}} { configvar type $string }
	method value {{string ""}} { configvar value $string }
	method readonly {{string ""}} { configvar readonly $string }

	public variable display		""
	public variable form		""
	public variable formargs		""

	# values - for fields of type "select" only, the values that go in
	# the popdown (or whatever) selector
	public variable values				""

	# name - the field name
	public variable name		""

	# text - the description text for the field. if not specified,
	#  it's constructed from a prettified version of the field name
	public variable text		""

	# value - the default value of the field
	public variable value		""

	# type - the data type of the field
	public variable type		"text"

	# readonly - if 1, we don't allow the value to be changed
	public variable readonly		0

} ; ## ::itcl::class STDisplayField

catch { ::itcl::delete class ::STDisplayField_boolean }

#
# STDisplayField_boolen -- superclass of STDisplayField that overrides
# a few methods to specially handle booleans
#
::itcl::class ::STDisplayField_boolean {
	inherit ::STDisplayField

	constructor {args} {eval configure $args} {
		eval configure $args
	}

	method add_true_value {string} {
		lappend trueValues $string
	}

	#
	# showform -- emit a form field for a boolean
	#
	method showform {} {
		set class [get_css_class TD DIOFormHeader DIOFormHeader-$name]
		puts "<TR CLASS=\"$class\">"
		puts "<TD CLASS=\"$class\">$text:</TD>"

		set class [get_css_class TD DIOFormField DIOFormField-$name]
		puts "<TD CLASS=\"$class\">"
		if {$readonly} {
			if {[boolean_value]} {
				puts $true
			} else {
				puts $false
			}
		} else {
			if {[boolean_value]} {
				$form default_value $name $true
			} else {
				$form default_value $name $false
			}
			eval $form radiobuttons $name \
				-values [list "$true $false"] $formargs
		}
		puts "</TD>"
		puts "</TR>"
	}

	#
	# showview -- emit a view for a boolean
	#
	method showview {{alt ""}} {
		set class [get_css_class TR DIOViewRow$alt DIOViewRow$alt-$name]
		puts "<TR CLASS=\"$class\">"

		set class [get_css_class TD DIOViewHeader DIOViewHeader-$name]
		puts "<TD CLASS=\"$class\">$text:</TD>"

		set class [get_css_class TD DIOViewField DIOViewField-$name]
		puts "<TD CLASS=\"$class\">"
		if {[boolean_value]} {
			puts $true
		} else {
			puts $false
		}
		puts "</TD>"

		puts "</TR>"
	}

	#
	# boolean_value -- return 1 if value is found in the values list, else 0
	#
	method boolean_value {} {
		set val [string tolower $value]
		if {[lsearch -exact $values $val] >= 0} { return 1 }
		return 0
	}

	method value {{string ""}} { configvar value $string }

	public variable true	"Yes"
	public variable false	"No"
	public variable values	"1 y yes t true on"

	public variable value "" {
		if {[boolean_value]} {
			set value $true
		} else {
			set value $false
		}
	}

	method null_ok {} {
		return 0
	}

} ; ## ::itcl::class ::STDisplayField_boolean

package provide st_display 1.8.2

