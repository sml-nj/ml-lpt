(* repair.sml
 *
 * COPYRIGHT (c) 2006
 * John Reppy (http://www.cs.uchicago.edu/~jhr)
 * Aaron Turon (http://www.cs.uchicago.edu/~adrassi)
 * All rights reserved.
 *
 * Representation and pretty-printing of ml-antlr repair actions
 *)

structure Repair = struct

  datatype 'a repair_action
    = Insert of 'a list
    | Delete of 'a list
    | Subst of {
	old : 'a list, 
	new : 'a list
      }
    | FailureAt of 'a

  type 'a repair = StreamPos.pos * 'a repair_action

  fun actionToString tokToString repair = let
    val toksToString = (String.concatWith " ") o (map tokToString)
    in case repair
	of Insert toks => "inserting " ^ toksToString toks
	 | Delete toks => "deleting " ^ toksToString toks
	 | Subst {old, new} => 
	     "substituting " ^ toksToString new ^ " for "
	     ^ toksToString old
	 | FailureAt tok => "syntax error at " ^ toksToString [tok]
    end

  fun repairToString tokToString sm (pos, repair) = 
      (StreamPos.toString sm pos ^ ": " ^ actionToString tokToString repair)

end