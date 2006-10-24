(* sml-output.sml
 *
 * COPYRIGHT (c) 2006
 * John Reppy (http://www.cs.uchicago.edu/~jhr)
 * Aaron Turon (http://www.cs.uchicago.edu/~adrassi)
 * All rights reserved.
 *
 * Back end for SML code, using first-class continuations for
 * Burke-Fisher-style error repair/recovery
 *)

structure SMLOutput = 
  struct

    structure S = LLKSpec
    structure P = Predict

    structure TMap = Token.Map
    structure TSet = Token.Set
    structure NMap = Nonterm.Map

    structure NT = Nonterm

    datatype ml_exp = datatype ML.ml_exp
    datatype ml_pat = datatype ML.ml_pat
    datatype ml_decl = datatype ML.ml_decl
    datatype ml_fundecl = datatype ML.ml_fundecl
    datatype ml_fun_heading = datatype ML.ml_fun_heading

  (* the following functions compute names or small expressions
   * used throughout the backend 
   *)
   
    fun NTFnName nt = NT.name nt ^ "_NT"
    fun NTFnVar nt = ML_Var (NTFnName nt)

    fun predFnName nt = NT.name nt ^ "_PRED"

    fun tokConName tok = "Tok." ^ Token.name tok
    fun tokConVar tok = ML_Var (tokConName tok)
    fun tokConPat tok = ML_ConPat (tokConName tok, 
			    if Token.hasTy tok
			    then [ML_Wild]
			    else [])
    fun tokConPat' tok = ML_ConPat (Token.name tok, 
			    if Token.hasTy tok
			    then [ML_Wild]
			    else [])
    fun tokMatch' tok = "match" ^ (Token.name tok)
    fun tokMatch tok = "" ^ tokMatch' tok

    fun tokExpected tok = ML_Raw [ML.Tok ("raise Fail \"expected " ^ (Token.name tok) ^ "\"")]

    val bindingSuffix = "_RES"

    fun actionHeader (name, bindings, suffix) = let
	  val withSuffix = map (fn b => Atom.toString b ^ suffix) 
			       (AtomSet.listItems bindings)
          in
            String.concat [name, " (", 
			   String.concatWith ", " withSuffix,
			   ")"]
          end

  (* make an expression that will pull the next token off the stream *)
    fun mkGet1 strm = ML_App ("lex", [ML_Var (strm)])
  (* make an expression that will pull the kth token off the stream *)
    fun mkGetk (strm, 1) = mkGet1 strm
      | mkGetk (strm, k) = ML_App ("lex", [ML_App ("#2", [mkGetk (strm, k-1)])])

    fun rawCode code = ML_Raw [ML.Tok code]

    fun wrap f = "(wrap " ^ f ^ ")"
    fun wrapApp (f, params) = ML_App (wrap f, params)

  (* make an expression for the given (polymorphic) decision tree *)
    fun mkPredict (pickFn, choiceFn, strm, tree, errAction) = let
          fun mkPredict (strm, P.Pick p) = 
	        pickFn p
	    | mkPredict (strm, P.ByTok branches) = let
		val branches = List.concat (map mkMatch branches)
		val errCase = (ML_Wild, errAction)
	        in
	          ML_Case (mkGet1 strm, branches @ [errCase])
	        end
	    | mkPredict (strm, P.Choice prods) = 
	        choiceFn prods
	  and mkMatch (set, tree) = 
	        map (fn tok => (ML_TupPat [tokConPat tok, ML_VarPat "strm'"],
				mkPredict ("strm'", tree)))
		    (TSet.listItems set)
          in
            mkPredict (strm, tree)
          end

  (* make a production *)
    fun mkProd (grm, pm) prod = let
          val rhs = Prod.items prod
	  val S.Grammar {actionStyle, ...} = grm
	  fun mkTok (t, strmExp, letFn) = 
	        letFn (ML_App (tokMatch t, [strmExp]))
	  fun mkNT (nt, strmExp, args, letFn, item) = let
	        val name = case (args, actionStyle)
		  of (SOME args, S.ActNormal) => 
		       "(" ^ NTFnName nt ^ " ("
		       ^ actionHeader 
			   ("UserCode.ARGS_" ^ Action.name args, 
			    Item.bindingsLeftOf (item, prod), 
			    bindingSuffix) 
		       ^ "))"
		   | _ => NTFnName nt
	        val innerExp = wrapApp (name, [strmExp])
	        in
	          if NT.isSubrule nt
		  then letFn (mkNonterm (grm, pm) (nt, innerExp))
		  else letFn innerExp
	        end
	  fun mkEBNF (nt, strmExp, fname, letFn) = let
	        val predName = predFnName nt
	        val innerExp = letFn (ML_App (fname, [ML_Var predName, ML_Var (wrap (NTFnName nt)), strmExp]))
		val Predict.PMaps {ebnfPredict, ...} = pm
		val predTree = ebnfPredict nt
		fun mkBool true = ML_Var "true"
		  | mkBool false = ML_Var "false"
		fun choiceFn _ = raise Fail "BUG: mkEBNF: backtracking choice unexpected"
		val errAction = ML_Var "false"
		val caseExp = mkPredict (mkBool, choiceFn, "strm", predTree, errAction)
		val predFn = ML_Funs ([(predName, ["strm"], caseExp)], innerExp)
		in 
	          mkNonterm (grm, pm) (nt, predFn)
	        end
	  fun mkItem strm ((item, binding), k) = let
	        val strmExp = ML_Var strm
		fun mkLet e = ML_Let ("(" ^ binding ^ bindingSuffix ^ 
				      ", strm')", e, k)
	        in
	          case Item.sym item
		   of S.TOK t      => mkTok  (t,  strmExp, mkLet)
		    | S.NONTERM (nt, args)
				   => mkNT   (nt, strmExp, args, mkLet, item)
		    | S.CLOS nt    => mkEBNF (nt, strmExp, "EBNF.closure", mkLet)
		    | S.POSCLOS nt => mkEBNF (nt, strmExp, "EBNF.posclos", mkLet)
		    | S.OPT nt     => mkEBNF (nt, strmExp, "EBNF.optional", mkLet)
	        end
	  val itemBindings = Prod.itemBindings prod
	  val action = 
	      case actionStyle
	       of S.ActDebug =>
		  "( print \"" ^ (Nonterm.qualName (Prod.lhs prod)) ^ "\\n\" )"
		| S.ActUnit => "()"
		| S.ActNormal => (case Prod.action prod
		    of SOME _ => actionHeader ("UserCode." ^ Prod.fullName prod ^ "_ACT", 
					       Prod.bindingsAtAction prod, bindingSuffix)
		     | NONE => let
			 val bindings = (List.mapPartial 
			    (fn (S.TOK t, binding) =>
				  if Token.hasTy t then
				    SOME (binding ^ bindingSuffix)
				  else NONE
			      | (_, binding) => SOME (binding ^ bindingSuffix))
			    (ListPair.zip (map Item.sym rhs, itemBindings)))
			 in 
			   if List.length bindings > 0 
			   then String.concatWith ", " bindings
			   else "()"
		         end
  	           (* end case *))
	  fun innerExp strm = let
	        val act = ML_Tuple [ML_Raw [ML.Tok action], ML_Var (strm)]
	        in case (Prod.pred prod, actionStyle)
		    of (SOME pred, S.ActNormal) =>
		         ML_If (ML_Raw [ML.Tok ("(" 
				  ^ actionHeader
				      ("UserCode." ^ Prod.fullName prod ^ "_PRED",
				       Prod.bindingsAtAction prod, bindingSuffix)
				  ^ ")")], 
				act,
				ML_Raw [ML.Tok "raise ParseError"])
		     | _ => act
	        end
	  val parse = case (ListPair.zip (rhs, itemBindings))
		       of [] => innerExp "strm"
			| fst::rst => 
			    mkItem "strm" 
			      (fst, List.foldr (mkItem "strm'") (innerExp "strm'") rst)
          in 
            parse
          end

  (* make a group of productions, along with a decision tree to choose one of them *)
    and mknProds (grm, pm, nt) = let
	  fun mkProdFun (prod, k) = ML_Funs ([(Prod.name prod, ["strm"], 
					    mkProd (grm, pm) prod)], k)
	  val Predict.PMaps {prodPredict, ...} = pm
	  val tree = prodPredict nt
	  fun pickFn prod = ML_App (Prod.name prod, [ML_Var "strm"])
	  fun choiceFn prods = 
	        ML_App ("tryProds", [ML_Var "strm", 
					ML_List (map (ML_Var o Prod.name) prods)])
	  val errAction = ML_App ("raise", [ML_Var "ParseError"])
	  val caseExp = mkPredict (pickFn, choiceFn, "strm", tree, errAction)
          in
	    foldr mkProdFun caseExp (Nonterm.prods nt)
          end

    and mkNonterm' (grm, pm) nt = let
	  val S.Grammar {actionStyle, ...} = grm
          val formals = case actionStyle
	      of S.ActNormal =>
	        if length (Nonterm.formals nt) > 0
		then " (" ^ (String.concatWith ", " 
			       (map 
				  (fn f => Atom.toString f ^ bindingSuffix)
				  (Nonterm.formals nt)))
		     ^ ")"
		else ""
	       | _ => ""
	  val exp = if List.length (Nonterm.prods nt) = 1
		    then mkProd (grm, pm) (hd (Nonterm.prods nt))
		    else mknProds(grm, pm, nt)
          in 
            (NTFnName nt ^ formals, ["strm"], exp)
          end
    and mkNonterm (grm, pm) (nt, k) = ML_Funs ([mkNonterm' (grm, pm) nt], k)

    fun mkNonterms (grm, pm) (nts, k) = 
	  ML_Funs (map (mkNonterm' (grm, pm)) nts, k)

  (* output the main parser body *)
    fun parserHook spec strm = let
          val (grm as S.Grammar {toks, nterms, startnt, sortedTops, ...}, pm) = spec
          val ppStrm = TextIOPP.openOut {dst = strm, wid = 80}
	  val args = if length (Nonterm.formals startnt) > 0 
		     then " args "
		     else ""
	  val innerExp = ML_App (NTFnName startnt ^ args, [ML_Var "strm"])
	  val parser = List.foldl (mkNonterms (grm, pm)) innerExp sortedTops
          in
            TextIO.output (strm, "fun parse' " ^ args ^ " strm = \n");
            ML.ppML (ppStrm, parser)
          end

    fun argsHook spec strm = let
          val (grm as S.Grammar {startnt, ...}, _) = spec
          in
            if length (Nonterm.formals startnt) > 0
	    then TextIO.output (strm, "args")
	    else ()
          end

  (* make a match function for a token *)
    fun ppMatch (strm, ppStrm) t = let
          val matchCase = 
	        (ML_TupPat 
		   [ML_ConPat (tokConName t,
			       if Token.hasTy t
			       then [ML_VarPat "x"]
			       else []),
		    ML_VarPat "strm'"],
		 if Token.hasTy t
		 then ML_Tuple [ML_Var "x", ML_Var "strm'"]
		 else ML_Tuple [ML_Var "()", ML_Var "strm'"])
	  val errCase = (ML_Wild, ML_App ("raise", [ML_Var "ParseError"]))
          val exp = ML_Case (mkGet1 "strm", [matchCase, errCase])
	  in
            TextIO.output (strm, "val " ^ tokMatch' t ^ " = wrap (fn strm => ");
	    ML.ppML (ppStrm, exp);
	    TextIO.output (strm, ")\n")
          end

  (* output the tokens datatype *)
    fun tokensHook spec strm = let
          val (S.Grammar {toks, ...}, _) = spec
          val ppStrm = TextIOPP.openOut {dst = strm, wid = 80}
	  val toksDT = 
	        "    datatype token = "
		^ (String.concatWith "\n      | " (List.map Token.def toks))
	  fun mkMat t = (ML_TupPat [tokConPat' t], rawCode (Token.quoted t))
          val casesExp = ML_Case (ML_Var "tok", List.map mkMat toks)
          in
            TextIO.output (strm, toksDT ^ "\n\n");
            TextIO.output (strm, "    fun toString tok = \n");
	    ML.ppML (ppStrm, casesExp);
	    TextIO.output (strm, "\n")
          end

    fun matchfnsHook spec strm = let
          val (S.Grammar {toks, ...}, _) = spec
          val ppStrm = TextIOPP.openOut {dst = strm, wid = 80}
          in
	    app (ppMatch (strm, ppStrm)) toks
          end

  (* output additional definitions for error handling *)
    fun repairsHook spec strm = let
          val (S.Grammar {toks, ...}, _) = spec
          val ppStrm = TextIOPP.openOut {dst = strm, wid = 80}
	  val allRepairs = "    val allRepairs = "
	  val unitToks = List.filter (not o Token.hasTy) toks
	  val deletion = "Deletion"
	  fun mk cstr tok = cstr ^ " Tok." ^ Token.name tok
	  val repairs = (deletion::
			  (  (List.map (mk "Insertion")    unitToks)
			   @ (List.map (mk "Substitution") unitToks)))
          in
            TextIO.output (strm, allRepairs);
	    TextIO.output (strm, "[" ^ (String.concatWith ", " repairs) ^ "]\n")
          end

  (* output header *)
    fun headerHook spec strm = let
          val (S.Grammar {header, ...}, _) = spec
          in
            TextIO.output (strm, header)
          end

  (* output user definitions *)
    fun defsHook spec strm = let
          val (S.Grammar {defs, prods, ...}, _) = spec
	  fun output ss = TextIO.output (strm, String.concat ss)
	  fun actionLevel (suffix, f) prod = (case f prod
            of SOME code => output [
	         "fun ", 
		 actionHeader (
		   Prod.fullName prod ^ suffix, 
		   Prod.bindingsAtAction prod, ""), 
		 " = \n  (", Action.toString code, ")\n"]
	     | NONE => ())
	  fun args prod (itm as S.ITEM {sym = S.NONTERM (nt, SOME code), ...}) = 
	        output ["fun ",
		  actionHeader (
		    "ARGS_" ^ Action.name code,
		    Item.bindingsLeftOf (itm, prod), ""),
		  " = \n  (", Action.toString code, ")\n"]
	    | args _ _ = ()
          in
            TextIO.output (strm, Action.toString defs);
	    TextIO.output (strm, "\n\n");
	    app (actionLevel ("_ACT", Prod.action)) prods;
	    app (actionLevel ("_PRED", Prod.pred)) prods;
	    app (fn prod => app (args prod) (Prod.items prod)) prods
          end

    val template = ExpandFile.mkTemplate "BackEnds/SML/template.sml"

    fun output (grm, pm, fname) = 
          ExpandFile.expand' {
	      src = template,
	      dst = fname ^ ".sml",
	      hooks = [("parser",   parserHook (grm, pm)),
		       ("tokens",   tokensHook (grm, pm)),
		       ("repairs",  repairsHook (grm, pm)),
		       ("header",   headerHook (grm, pm)),
		       ("defs",     defsHook (grm, pm)),
		       ("args",     argsHook (grm, pm)),
		       ("matchfns", matchfnsHook (grm, pm))]
	    }

  end
