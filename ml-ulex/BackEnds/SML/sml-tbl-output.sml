(* sml-tbl-output.sml
 *
 * COPYRIGHT (c) 2005 
 * John Reppy (http://www.cs.uchicago.edu/~jhr)
 * Aaron Turon (adrassi@gmail.com)
 * All rights reserved.
 *
 * Code generation for SML, using a transition table
 *)

structure SMLTblOutput : OUTPUT = 
  struct

    open SMLOutputSupport

  (* generate code for an individual state in the table *)
    fun mkState actionVec s = let
          val LO.State {id, startState, label, final, next} = s
	  fun w2s w = 
	        if !Options.lexCompat 
		then "#\"" ^ (Char.toString o Char.chr o Word32.toInt) w ^ "\""
		else "0w" ^ Word32.fmt StringCvt.DEC w
	  val ASCII = SIS.interval (0w0, 0w255)
	  fun mkTrans (set, state) = 
	        map (fn (c1, c2) => String.concat [
			"(", w2s c1, ",",
			     w2s c2, ",",
			     Int.toString (idOf state), ")"])
		    (SIS.intervals (SIS.intersect (set, ASCII)))
	  val allTransitions = List.concat (map mkTrans (!next))
	  in 
            String.concat [
	      "([", 
	      String.concatWith ", " allTransitions, 
	      "], [", 
	      String.concatWith ", " (map Int.toString final),
	      "])"]
          end

    fun tableHook spec strm = let
          val LO.Spec {actions, dfa, startStates, ...} = spec
          in
            TextIO.output (strm,
	      String.concatWith ", " (map (mkState actions) dfa))
          end

    fun lexerHook spec strm = let
          val LO.Spec {actions, dfa, startStates, ...} = spec
	  fun matchSS (label, state) =
	        (ML_ConPat (label, []), 
		   ML_App ("yygo yyactTable ", 
				[ML_Var (Int.toString (idOf state)),
				 ML_RefGet (ML_Var "yystrm"), 
				 ML_Var "yyNO_MATCH"]))
	  val innerExp = ML_Case (ML_RefGet (ML_Var "yyss"),
				  List.map matchSS startStates)
	  val eofCheckExp = 
	        if !Options.lexCompat 
		then
		  ML_If (ML_App("yyInput.eof", [ML_RefGet (ML_Var "yystrm")]), 
			 ML_App("UserDeclarations.eof", [ML_Var "yyarg"]),
			 innerExp)
		else 
		  ML_If (ML_App("ULexBuffer.eof", [ML_RefGet (ML_Var "yystrm")]), 
			 ML_App("UserDeclarations.eof", [ML_Tuple []]),
			 innerExp)
	  val actList = Vector.foldri 
			  (fn (i, _, ls) => (ML_Var o actName) i :: ls)
			  [] actions
	  val actTableExp = ML_Let ("yyactTable",
		ML_App ("Vector.fromList", [ML_List actList]),
		eofCheckExp)
	  val lexerExp = Vector.foldri mkAction actTableExp actions
          val ppStrm = TextIOPP.openOut {dst = strm, wid = 80}
          in
            ML.ppML (ppStrm, lexerExp)
          end

    fun output (spec, fname) = 
          ExpandFile.expand' {
	      src = if !Options.lexCompat 
		    then lexTemplate else ulexTemplate,
	      dst = fname ^ ".sml",
	      hooks = [("lexer", lexerHook spec),
		       ("startstates", startStatesHook spec),
		       ("userdecls", userDeclsHook spec),
		       ("header", headerHook spec),
		       ("args", argsHook spec),
		       ("table", tableHook spec)]
	    }

  end