(* ml-ulex.lex
 *
 * COPYRIGHT (c) 2006 
 * John Reppy (http://www.cs.uchicago.edu/~jhr)
 * Aaron Turon (http://www.cs.uchicago.edu/~adrassi)
 * All rights reserved.
 *
 * (With some code borrowed from ml-yacc)
 *)

%defs (
  val comLvl : int ref = ref 0		(* nesting depth of comments *)
  val comStart : int ref = ref 0	(* start line of current comment *)

  fun eof () = (
        if (!comLvl > 0)
          then print("unclosed comment starting at line " ^ Int.toString(!comStart) ^ "\n")
          else ();
        Tok.EOF)

  val text : string list ref = ref []
  fun addText s = (text := s::(!text))
  fun clrText () = (text := [])
  fun getText () = concat (rev (!text))

  val pcount = ref 0
  fun inc (ri as ref i) = (ri := i+1)
  fun dec (ri as ref i) = (ri := i-1)

  fun chomp s = String.substring (s, 1, String.size s - 2)
);

(*
%let eol=("\n"|"\013\n"|"\013");
%let ws=("\009"|"\011"|"\012"|" "|{eol});
*)
%let eol="\n";
%let ws=("\t"|" "|{eol});
%let lc=[a-z];
%let uc=[A-Z];
%let alpha=({lc}|{uc});
%let digit=[0-9];
%let int=digit*;
%let idchars=({alpha}|{digit}|"_");
%let id={alpha}{idchars}*;
%let qualid ={id}".";
%let tyvar="'"{idchars}*;

%states STRING COM CODE CHARCLASS DIRECTIVE CHARSET;

%name MLULexLex;
(* %charset utf8; *)

<INITIAL,DIRECTIVE,CHARSET,CHARCLASS>{ws}+	
	=> (continue());

<INITIAL>"%defs"	=> (YYBEGIN CODE; clrText(); Tok.KW_defs);
<INITIAL>"%name"	=> (YYBEGIN DIRECTIVE; Tok.KW_name);
<INITIAL>"%states"	=> (YYBEGIN DIRECTIVE; Tok.KW_states);
<INITIAL>"%let"		=> (YYBEGIN DIRECTIVE; Tok.KW_let);
<INITIAL>"%charset"	=> (YYBEGIN CHARSET; Tok.KW_charset);

<DIRECTIVE>{id}	=> (Tok.ID yytext);
<DIRECTIVE>","	=> (Tok.COMMA);
<DIRECTIVE>";"	=> (YYBEGIN INITIAL; Tok.SEMI);
<DIRECTIVE>"="	=> (YYBEGIN INITIAL; Tok.EQ);
<DIRECTIVE>">"	=> (YYBEGIN INITIAL; Tok.GT);
<DIRECTIVE>.	=> (YYBEGIN INITIAL; REJECT());

<CHARSET>"utf8" | "UTF8" => (YYBEGIN INITIAL; Tok.UTF8);
<CHARSET>"ascii7" | "ASCII7" => (YYBEGIN INITIAL; Tok.ASCII7);
<CHARSET>"ascii8" | "ASCII8" => (YYBEGIN INITIAL; Tok.ASCII8);
<CHARSET>";"	=> (YYBEGIN INITIAL; Tok.SEMI);
<CHARSET>.	=> (YYBEGIN INITIAL; REJECT());

<INITIAL>"|"	=> (Tok.BAR); 
<INITIAL>"."	=> (Tok.DOT); 
<INITIAL>"$"	=> (Tok.DOLLAR); 
<INITIAL>"+"	=> (Tok.PLUS); 
<INITIAL>"*"	=> (Tok.STAR);
<INITIAL>"?"	=> (Tok.QUERY);
<INITIAL>";"	=> (Tok.SEMI);
<INITIAL>"("	=> (Tok.LP);
<INITIAL>")"	=> (Tok.RP);
<INITIAL>"["	=> (YYBEGIN CHARCLASS; Tok.LSB);
<INITIAL>"]"	=> (Tok.RSB);
<INITIAL>"{" {id} "}"
		=> (Tok.ID (chomp yytext));
<INITIAL>"<"	=> (YYBEGIN DIRECTIVE; Tok.LT);
<INITIAL>">"	=> (Tok.GT);
<INITIAL>","	=> (Tok.COMMA);
<INITIAL>"/"	=> (Tok.SLASH);
<INITIAL>"="	=> (Tok.EQ);
<INITIAL>"=>"	=> (YYBEGIN CODE; clrText(); Tok.DARROW);
<INITIAL>"\""	=> (YYBEGIN STRING; clrText(); 
		    ignore(continue() before YYBEGIN INITIAL);
		    (Tok.STRING o valOf o String.fromString o getText)());

<CHARCLASS>"^"	=> (Tok.CARAT);
<CHARCLASS>"-"	=> (Tok.DASH);
<INITIAL,CHARCLASS>"\\" ([A-Za-z] | [0-9]{3} | "\\")
	=> (let val c = Char.fromString yytext
            in case c
                of SOME c' => Tok.CHAR c'
		 | NONE => Tok.CHAR (String.sub (yytext, 1))
            end);
<CHARCLASS>"]"	=> (YYBEGIN INITIAL; Tok.RSB);
<CHARCLASS>.	=> (Tok.CHAR (String.sub (yytext, 0)));

<INITIAL>"(*" 
	=> (comLvl := 1; comStart := !yylineno; YYBEGIN COM; 
	    ignore(continue() before YYBEGIN INITIAL);
	    continue());
<CODE>"(*"
	=> (comLvl := 1; comStart := !yylineno; YYBEGIN COM; 
	    addText yytext;
	    ignore(continue() before YYBEGIN CODE);
	    continue());

<COM>"(*" 
	=> (addText yytext; comLvl := !comLvl+1; continue());
<COM>"*)"        
	=> (addText yytext; comLvl := !comLvl-1; 
	    if (!comLvl = 0) 
	      then (Tok.BOGUS) 
	      else continue());
<COM>.|{eol}
	=> (addText yytext; continue());

<CODE>"("	=> (if !pcount = 0 then () else addText yytext;
		    inc pcount; continue());
<CODE>")"	=> (dec pcount; 
		    if !pcount = 0 then
		      (YYBEGIN INITIAL; Tok.CODE (getText()))
		    else (addText yytext; continue()));
<CODE>"\""	=> (addText yytext; YYBEGIN STRING; 
		    ignore(continue() before YYBEGIN CODE);
		    addText "\""; continue());
<CODE>[^()"]+	=> (addText yytext; continue());

<STRING>"\""	=> (Tok.BOGUS);
<STRING>{eol}	=> (addText yytext; print ("unclosed string");
 	            Tok.BOGUS);
<STRING>"\\"	=> (addText yytext; continue());
<STRING>"\\\\"	=> (addText yytext; continue());
<STRING>"\\\""	=> (addText yytext; continue());
<STRING>[^"\\\n\013]+ 
		=> (addText yytext; continue());

<INITIAL>.	=> (Tok.CHAR (String.sub (yytext, 0)));
.		=> (print (concat[Int.toString (!yylineno), ": illegal character '", 
				  String.toCString yytext, "'\n"]);
		    continue());

