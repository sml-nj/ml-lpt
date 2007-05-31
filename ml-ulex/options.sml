(* options.sml
 *
 * COPYRIGHT (c) 2006
 * Aaron Turon (adrassi@gmail.com)
 * All rights reserved.
 *
 * Command-line options for ml-ulex
 *)

structure Options = 
  struct

    datatype be_mode = BySize | TableBased | FnBased

    val fname     : string ref = ref ""
    val lexCompat : bool ref   = ref false
    val dump      : bool ref   = ref false
    val dot       : bool ref   = ref false
    val match     : bool ref   = ref false
    val beTest    : bool ref   = ref false
    val minimize  : bool ref   = ref false
    val beMode	  : be_mode ref = ref BySize

    fun procArg arg = 
	  (case arg
	    of "--dot"    => dot := true
	     | "--dump"	  => dump := true
	     | "--match"  => match := true
	     | "--testbe" => beTest := true
	     | "--ml-lex-mode"	=> lexCompat := true
	     | "--minimize"	=> minimize := true
	     | "--table-based"	=> beMode := TableBased
	     | "--fn-based"	=> beMode := FnBased
	     | file	  => 
	         if String.size (!fname) > 0 
		 then 
		   raise Fail "Only one input file may be specified\n"
		 else fname := file
	   (* end case *))

  end
