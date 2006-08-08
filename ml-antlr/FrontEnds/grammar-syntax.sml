(* grammar-syntax.sml
 *
 * COPYRIGHT (c) 2005
 * John Reppy (http://www.cs.uchicago.edu/~jhr)
 * Aaron Turon (http://www.cs.uchicago.edu/~adrassi)
 * All rights reserved.
 *
 * Parse tree for grammar input.
 *)

structure GrammarSyntax =
  struct

    type action = String.string
    datatype action_style
      = ActNormal
      | ActDebug
      | ActUnit

    datatype rule = RULE of {
	lhs : Atom.atom,
	formals : Atom.atom list,
	alts : alt list
      }

    and alt = ALT of {
	items : item list,
	action : action option,
	try : bool,
	pred : sem_pred option
      }

    and item
      = SYMBOL of Atom.atom * action option
      | SUBRULE of alt list	(* ( ... ) *)
      | CLOS of item		(* ( ... )* *)
      | POSCLOS of item		(* ( ... )+ *)
      | OPT of item		(* ( ... )? *)

    withtype sem_pred = action

    type ty = string
    type constr = (Atom.atom * ty option * Atom.atom option)

    datatype grammar = GRAMMAR of {
	defs : string,
	rules : rule list,
	toks : constr list,
	actionStyle : action_style
      }

    fun mkGrammar() = GRAMMAR {
	  defs = "",
	  rules = [],
	  toks = [],
	  actionStyle = ActNormal
        }

    fun updDefs (g, new) = let
          val GRAMMAR {defs, rules, toks, actionStyle} = g
          in GRAMMAR {defs = new, rules = rules, 
		      toks = toks, actionStyle = actionStyle} end

    fun updToks (g, new) = let
          val GRAMMAR {defs, rules, toks, actionStyle} = g
          in GRAMMAR {defs = defs, rules = rules, 
		      toks = new, actionStyle = actionStyle} end

    fun updActionStyle (g, new) = let
          val GRAMMAR {defs, rules, toks, actionStyle} = g
          in GRAMMAR {defs = defs, rules = rules, 
		      toks = toks, actionStyle = new} end

    fun debugAct g = updActionStyle (g, ActDebug)
    fun unitAct g = updActionStyle (g, ActUnit)

    fun addRule (g, new) = let
          val GRAMMAR {defs, rules, toks, actionStyle} = g
          in GRAMMAR {defs = defs, rules = rules@[new], 
		      toks = toks, actionStyle = actionStyle} end

    fun setToTry (ALT {items, action, try, pred}) = 
	  ALT {items = items, action = action, try = true, pred = pred}

    fun addAction (ALT {items, action = NONE, try, pred}, act) = 
	  ALT {items = items, action = SOME act, try = try, pred = pred}
      | addAction _ = raise Fail "BUG: only one action allowed"

  end