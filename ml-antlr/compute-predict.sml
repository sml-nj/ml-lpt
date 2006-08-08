(* compute-predict.sml
 *
 * COPYRIGHT (c) 2006
 * John Reppy (http://www.cs.uchicago.edu/~jhr)
 * Aaron Turon (http://www.cs.uchicago.edu/~adrassi)
 * All rights reserved.
 *
 * Prediction tree computation; given a grammar, 
 * produce a decision tree for each decision point.
 *)

structure ComputePredict :
  sig

    val mkPM : LLKSpec.grammar * GLA.gla -> Predict.predict_maps

  end = struct
	
    structure P = Predict
    structure TSet = Token.Set
    structure NMap = Nonterm.Map
    structure S = LLKSpec

    val maxK = 3

    val debugPredict = false

    fun debug s = if debugPredict then print (s ^ "\n") else ()
    fun debugs ss = debug (concat ss)

  (* error handling, for lookahead computation failure *)
    fun mapi f l = ListPair.map f (List.tabulate (length l, fn i => i), l)
    fun doErr (prePath, nt, msg) = (print (String.concat [
          "lookahead computation failed for ",
	  Nonterm.qualName nt, ",\n", msg, "\n  ",
	  String.concatWith "\n  " 
	    (mapi (fn (k, s) => "k = " ^ (Int.toString (k+1)) ^ ": " 
			       ^ (Token.setToString s))
		 prePath)]);
	  print "\n")

  (* compute a decision tree for predicting a production for a nonterminal *)
    fun compute(gla, nt) = let
	  fun tryToks (prePath, k) (prod, branches) = let
	        fun consNE ((set, prods), ls) =
		      if TSet.isEmpty set 
		      then ls
		      else (set, prods)::ls
	        fun intersect ((set, prods), (branches, toks)) = let
		      val isct = TSet.intersection (set, toks)
		      in
		        (consNE((isct, prod::prods),
			   consNE((TSet.difference (set, isct), prods),
			     branches)),
			 TSet.difference (toks, isct))
		      end
	        val toks = GLA.lookK (gla, prod, SOME prePath, k)
		val (branches', toks') = foldl intersect ([], toks) branches
                in
	          consNE((toks', [prod]), branches')
                end
	  fun try (prePath, k, prods) = let
		fun finBranch (set, [prod]) = (set, P.Pick prod)
		  | finBranch (set, []) = raise Fail "bug: ComputePredict"
		  | finBranch (set, prods) = 
		      if List.all Prod.canTry prods then
			(set, P.Choice (Prod.sortProds prods))
		      else if k = maxK then (
			doErr (prePath @ [set], nt, String.concat [
			  "with a conflict for the following productions:\n  ",
			  String.concatWith "\n  " (map Prod.toString prods)
			]);
		        raise Fail "lookahead")
		      else (set, try (prePath @ [set], k+1, prods))
	        val branches = foldl (tryToks(prePath, k)) [] prods
	        in
	          debugs ["  trying k = ", Int.toString k];
	          P.ByTok (map finBranch branches)
	        end
          in
            debugs [" computing prediction tree for ", Nonterm.qualName nt];
	    try ([], 1, Nonterm.prods nt)
	    before debugs [" done"]
          end

    fun unionAll sets = foldl TSet.union TSet.empty sets

  (* compute a decision tree for an EBNF decision, e.g., for 
   * (A* B), the tree will predict true if A appears again and
   * false otherwise.
   *)
    fun computeEBNF(gla, nt) = let
	  fun tryToks (k, prePath) = let
	        fun lookProd prod = GLA.lookK (gla, prod, SOME prePath, k)
	        val trueToks = unionAll (map lookProd (Nonterm.prods nt))
		val falseToks = GLA.lookKFollow (gla, nt, SOME prePath, k)
		val isct = TSet.intersection (trueToks, falseToks)
		val trueOnly = TSet.difference (trueToks, isct)
		val falseOnly = TSet.difference (falseToks, isct)
		val choices = List.concat [
		      if TSet.isEmpty trueOnly then []
		        else [(trueOnly, Predict.Pick true)],
		      if TSet.isEmpty falseOnly then []
		        else [(falseOnly, Predict.Pick false)],
		      if TSet.isEmpty isct then []
		        else (if k <= maxK
			      then [(isct, tryToks (k+1, prePath @ [isct]))]
			      else (doErr (prePath @ [isct], nt, 
			                   "deciding between the subrule and "
					   ^ "the sequence following it:");
				    print "\n";
				    raise Fail "lookahead"))]
	        in
	          Predict.ByTok choices
	        end
          in
(*
debugs [" EBNF: ", Nonterm.qualName nt, "\n"];
*)
            tryToks (1, [])
          end

    fun mkPM (grm, gla) = let
          val LLKSpec.Grammar {sortedTops, nterms, ...} = grm
          fun doNT (nt, prodMap) =
	        NMap.insert (prodMap, nt, compute(gla, nt))
	  fun doEBNF (nt, ebnfMap) =
		 NMap.insert (ebnfMap, nt, computeEBNF(gla, nt))
	(* foldr ==> do innermost predictions first *)
	  val prodMapTops = foldr doNT NMap.empty (List.concat sortedTops)
	  val prodMap = foldl doNT prodMapTops (List.filter Nonterm.isSubrule nterms)
	  val ebnfMap = foldl doEBNF NMap.empty (List.filter Nonterm.isEBNF nterms)
	  fun mkFn map nt = valOf (NMap.find (map, nt))
          in
            Predict.PMaps {
	      prodPredict = mkFn prodMap,
	      ebnfPredict = mkFn ebnfMap
            }
          end

  end