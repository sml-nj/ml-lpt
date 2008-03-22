(* expand-file.sml
 *
 * COPYRIGHT (c) 1999 Bell Labs, Lucent Technologies.
 * (Used with permission)
 *
 * Copy a template file to an output file while expanding placeholders.
 * Placeholders are denoted by @id@ on a line by themselves.
 *)

structure ExpandFile : sig

    type hook = TextIO.outstream -> unit
    type template

    val expand : {
	  src : string, (* file name *)
	  dst : string, (* file name *)
	  hooks : (string * hook) list
        } -> unit

    val mkTemplate : string -> template (* file name -> template *)
    val expand' : {
	  src : template, 
	  dst : string, (* file name *)
	  hooks : (string * hook) list
        } -> unit

  end = struct

    structure TIO = TextIO
    structure SS = Substring
    structure RE = RegExpFn (
      structure P = AwkSyntax
      structure E = BackTrackEngine)
    structure M = MatchTree

    type hook = TextIO.outstream -> unit
    type template = string list

    fun mkTemplate fname = let
          val file = TIO.openIn fname
	  fun done () = TIO.closeIn file
	  fun read () = (case TIO.inputLine file
			  of NONE => []
			   | SOME line => line::read()
			 (* end case *))
	  in 
            read() handle ex => (done(); raise ex)
	    before done()
	  end

    val placeholderRE = RE.compileString "[\\t ]*@([a-zA-Z][-a-zA-Z0-9_]*)@[\\t ]*"
    val prefixPlaceholder = RE.prefix placeholderRE SS.getc

    fun findPlaceholder s = (case prefixPlaceholder(SS.full s)
	   of SOME(M.Match(_, [M.Match({pos, len}, _)]), _) =>
		SOME(SS.string(SS.slice(pos, 0, SOME len)))
	    | _ => NONE
	  (* end case *))

  (* copy from inStrm to outStrm expanding placeholders *)
    fun copy (inStrm, outStrm, hooks) = let
	  fun lp [] = ()
	    | lp (s::ss) = (
	        case findPlaceholder s
		 of NONE => TIO.output (outStrm, s)
		  | (SOME id) => (
		      case (List.find (fn (id', h) => id = id') hooks)
		       of (SOME(_, h)) => h outStrm
			| NONE => raise Fail "bogus placeholder"
		      (* end case *))
	        (* end case *);
		lp(ss))
		
	  in
	    lp(inStrm)
	  end

    exception OpenOut

    fun expand' {src, dst, hooks} = (let
	  val dstStrm = TIO.openOut dst
		handle ex => (
		  TIO.output(TIO.stdOut, concat[
		      "Warning: unable to open output file \"",
		      dst, "\"\n"
		    ]);
		  raise OpenOut)
	  fun done () = (TIO.closeOut dstStrm)
	  in
	    copy (src, dstStrm, hooks) handle ex => (done(); raise ex);
	    done()
	  end
	    handle OpenOut => ())

    fun expand {src, dst, hooks} = 
	  expand' {src = mkTemplate src, 
		   dst = dst, 
		   hooks = hooks}

  end
