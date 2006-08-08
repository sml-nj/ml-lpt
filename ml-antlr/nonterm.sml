(* nonterm.sml
 *
 * COPYRIGHT (c) 2006
 * John Reppy (http://www.cs.uchicago.edu/~jhr)
 * Aaron Turon (http://www.cs.uchicago.edu/~adrassi)
 * All rights reserved.
 *
 * Utility functions for the nonterm datatype.
 *)

structure Nonterm =
  struct

    datatype nonterm = datatype LLKSpec.nonterm

    fun toString (NT{name, id, ...}) = concat[
	    Atom.toString name (* , "/", Int.toString id *)
	  ]
    fun name (NT{name, ...}) = Atom.toString name

    fun qualName (nt as NT{binding = LLKSpec.WITHIN ntOwner, ...}) = (qualName ntOwner) ^ "_" ^ (name nt)
      | qualName nt = name nt

    fun isSubrule (NT{binding = LLKSpec.TOP, ...}) = false
      | isSubrule _ = true

    fun isEBNF (NT{isEBNF = v, ...}) = v

    fun prods (NT{prods, ...}) = !prods

    fun formals (NT{formals, ...}) = !formals

    fun compare (NT{id=a, ...}, NT{id=b, ...}) = Int.compare(a, b)
    fun lexCompare (NT{name=a, ...}, NT{name=b, ...}) =
	  String.compare(Atom.toString a, Atom.toString b)
    fun same (NT{id=a, ...}, NT{id=b, ...}) = (a = b)

    structure Ord = 
      struct
	type ord_key = nonterm
	val compare = compare
      end

    structure Set = RedBlackSetFn (Ord)
    structure Map = RedBlackMapFn (Ord)

    fun setToString s = let
	(* simple insertion sort to lexically order the set *)
	  fun ins (nt, []) = [nt]
	    | ins (nt, nt'::nts) = (case lexCompare(nt, nt')
		 of LESS => nt::nt'::nts
		  | _ => nt'::ins(nt, nts)
		(* end case *))
	  val nts = Set.foldl ins [] s
	  in
	    String.concat[
		"{", String.concatWith "," (List.map toString nts), "}"
	      ]
	  end

    structure SCC = GraphSCCFn (Ord)
    structure S = LLKSpec

  (* topologically sort the nonterminal dependency graph
   * rooted at start; return a list of nonterm lists
   *)
    fun topsort (start) = let
          fun prodItems (S.PROD {rhs, ...}) = rhs
          fun followItem (S.NONTERM (nt, _)) = 
	        if isSubrule nt then []
		else [nt]
	    | followItem (S.CLOS nt) = follow nt
	    | followItem (S.POSCLOS nt) = follow nt
	    | followItem (S.OPT nt) = follow nt
	    | followItem (S.TOK _) = []
          and followItems itms = List.concat (map followItem itms)
	  and follow nt =
	        List.concat (map (followItems o prodItems) 
				 (prods nt))
	  val scc = SCC.topOrder {root = start, follow = follow}
	  fun compToList (SCC.SIMPLE nt) = [nt]
	    | compToList (SCC.RECURSIVE nts) = nts
	  in
            map compToList scc
          end

  end