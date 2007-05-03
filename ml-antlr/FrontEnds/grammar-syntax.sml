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

    type span = Err.span
    type code = span * String.string
    type symbol = Atom.atom
    type name = string
    type ty = string
    type constr = (symbol * ty option * Atom.atom option)

    datatype decl
      = NAME of name
      | START of symbol
      | ENTRY of symbol
      | KEYWORD of symbol
      | DEFS of code
      | TOKEN of constr
      | IMPORT of {
	  filename : string,
	  dropping : (span * symbol) list
	}
      | REFCELL of name * ty * code
      | RULE of {
	  lhs : symbol,
	  formals : name list,
	  rhs : rhs
	}
      | NONTERM of symbol * ty

    and rhs = RHS of {
	  items : (string option * (span * item)) list,
	  try : bool,
	  predicate : code option,
	  action : code option,
	  loc : span
        }

    and item
      = SYMBOL of symbol * code option
      | SUBRULE of rhs list	(* ( ... ) *)
      | CLOS of span * item	(* ( ... )* *)
      | POSCLOS of span * item	(* ( ... )+ *)
      | OPT of span * item	(* ( ... )? *)

    type grammar = (span * decl) list

    local
      fun ppDecl (_, NAME n) = "%name"
	| ppDecl (_, START s) = "%start"
	| ppDecl (_, ENTRY s) = "%entry"
	| ppDecl (_, KEYWORD s) = "%keywords"
	| ppDecl (_, DEFS c) = "%defs"
	| ppDecl (_, TOKEN cstr) = "%tokens"
	| ppDecl (_, NONTERM cstr) = "%nonterm"
	| ppDecl (_, IMPORT {filename, dropping}) = "%import"
	| ppDecl (_, REFCELL (n, ty, c)) = "%refcell"
	| ppDecl (_, RULE {lhs, formals, rhs}) = "-- rule: " ^ (Atom.toString lhs)
    in
    fun ppGrammar decls = String.concatWith "\n" (map ppDecl decls)
    end

  end
