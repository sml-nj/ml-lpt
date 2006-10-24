structure MLULexLex  = struct

(* utf8.sml
 *
 * COPYRIGHT (c) 2004 The Moby Project (moby.cs.uchicago.edu)
 * All rights reserved.
 * USED WITH PERMISSION
 *
 * Routines for working with UTF8 encoded strings.
 *
 *	Unicode value		1st byte    2nd byte    3rd byte    4th byte
 *	-----------------	--------    --------    --------    --------
 *	00000000 0xxxxxxx	0xxxxxxx	
 *	00000yyy yyxxxxxx	110yyyyy    10xxxxxx
 *	zzzzyyyy yyxxxxxx	1110zzzz    10yyyyyy	10xxxxxx
 *	110110ww wwzzzzyy+
 *	110111yy yyxxxxxx	11110uuu    10uuzzzz	10yyyyyy    10xxxxxx!
 *
 * (!) where uuuuu = wwww+1
 *
 * TODO:
 *    Add support for surrogate pairs (this will require changing the type
 *    of wchar to Word32.word).
 *)

  structure yyUTF8 = struct

    structure W = Word
    type wchar = W.word

    exception Incomplete
	(* raised by some operations when applied to incomplete strings. *)

    fun getu getc strm = let
          fun getContByte (strm, wc) = (case getc strm
	        of NONE => raise Incomplete
		 | SOME(c, strm') => let
		     val b = W.fromInt(Char.ord c)
		     in
		       if (W.andb(0wxc0, b) = 0wx80)
		       then (strm', W.orb(W.<<(wc, 0w6), W.andb(0wx3f, b)))
		       else raise Incomplete
		     end
   	       (* end case *))
          in case getc strm
	      of NONE => NONE
	       | SOME(c, strm') => let
		   val w = W.fromInt(Char.ord c)
		   in
		     if (w < 0w128)
		     then SOME (w, strm')
		     else (case (W.andb(0wxe0, w))
			    of 0wxc0 => let
				 val (strm', wc) = getContByte(strm', W.andb(0wx1f, w))
				 in
				   SOME (wc, strm')
			         end
			     | 0wxe0 => let
				 val (strm', wc) =
				       getContByte(
					 getContByte(strm', W.andb(0wx0f, w)))
			         in
				   SOME (wc, strm')
				 end
			     | _ => raise Incomplete
			   (* end case *))
		   end
             (* end case *)
	  end

    end

    structure yyInput : sig

        type stream
	val mkStream : (int -> string) -> stream
	val getc : stream -> (Char.char * stream) option
	val getpos : stream -> int
	val subtract : stream * stream -> Substring.substring
	val eof : stream -> bool

      end = struct

        val chunkSize = 4096

        datatype stream = S of (buf * int)
	and buf = B of {
	    data : string,
	    basePos : int,
	    more : more ref,
	    inputN : int -> string
          }
	and more = UNKNOWN | YES of buf | NO
        
	fun mkStream inputN = 
	      (S (B {data = "", basePos = 0, 
		     more = ref UNKNOWN,
		     inputN = inputN},
		  0))

	fun getc (S (buf as B {data, basePos, more, inputN}, pos)) = 
	      if pos < String.size data then
		SOME (String.sub (data, pos), S (buf, pos+1))
	      else (case !more
		     of NO => NONE
		      | YES buf' => getc (S (buf', 0))
		      | UNKNOWN => 
			  (case inputN chunkSize
			    of "" => (more := NO; NONE)
			     | data' => let 
				 val buf' = B {data = data',
					       basePos = basePos + 
						 String.size data,
					       more = ref UNKNOWN,
					       inputN = inputN}
			         in
				   more := YES buf';
				   getc (S (buf', 0))
			         end
			   (* end case *))
		    (* end case *))

	fun getpos (S (B {basePos, ...}, pos)) = basePos + pos

	fun subtract (new, old) = let
	      val (S (B {data = ndata, basePos = nbasePos, ...}, npos)) = new
	      val (S (B {data = odata, basePos = obasePos, 
			 more, inputN}, opos)) = old
	      in
	        if nbasePos = obasePos then
		  Substring.substring (ndata, opos, npos-opos)
		else case !more
		      of NO =>      raise Fail "BUG: yyInput.subtract, but buffers are unrelated"
		       | UNKNOWN => raise Fail "BUG: yyInput.subtract, but buffers are unrelated"
		       | YES buf => 
			   Substring.extract (
			     Substring.concat [
			       Substring.extract (odata, opos, NONE),
			       subtract (new, S (buf, 0))],
			     0, NONE)
	      end

	fun eof (S (B {data, more, ...}, pos)) = 
	      pos >= String.size data andalso 
	      (case !more
		of NO => true
		 | _ => false)

      end

    datatype 'a yymatch 
      = yyNO_MATCH
      | yyMATCH of yyInput.stream * 'a action * 'a yymatch
    withtype 'a action = yyInput.stream * 'a yymatch -> 'a

    datatype yystart_state = 
COM | CODE | STRING | CHARSET | CHARCLASS | INITIAL | DIRECTIVE
    structure UserDeclarations = 
      struct

 
  val comLvl : int ref = ref 0		(* nesting depth of comments *)
  val comStart : int ref = ref 0	(* start line of current comment *)

  type lex_result = Tok.token

  val text : string list ref = ref []
  fun addText s = (text := s::(!text))
  fun clrText () = (text := [])
  fun getText () = concat (rev (!text))

  val pcount = ref 0
  fun inc (ri as ref i) = (ri := i+1)
  fun dec (ri as ref i) = (ri := i-1)

  fun chomp s = String.substring (s, 1, String.size s - 2)


      end

    exception yyEOF

    fun mk yyins = let
        (* current start state *)
          val yyss = ref INITIAL
	  fun YYBEGIN ss = (yyss := ss)
	(* current input stream *)
          val yystrm = ref yyins
	(* get one char of input *)
	  val yygetc = yyUTF8.getu yyInput.getc 
	(* create yytext *)
	  fun yymksubstr(strm) = yyInput.subtract (strm, !yystrm)
	  fun yymktext(strm) = Substring.string (yymksubstr strm)
          open UserDeclarations
          fun lex 
(yyarg as ()) = let
            fun yystuck (yyNO_MATCH) = raise Fail "stuck state"
	      | yystuck (yyMATCH (strm, action, old)) = 
		  action (strm, old)
	    val yypos = yyInput.getpos (!yystrm)
	    fun yygetlineNo(_) = 0
	    fun continue() = 
let
fun yyAction0 (strm, lastMatch) = (yystrm := strm;  continue())
fun yyAction1 (strm, lastMatch) = (yystrm := strm;
       YYBEGIN CODE; clrText(); Tok.KW_defs)
fun yyAction2 (strm, lastMatch) = (yystrm := strm;
       YYBEGIN DIRECTIVE; Tok.KW_name)
fun yyAction3 (strm, lastMatch) = (yystrm := strm;
       YYBEGIN DIRECTIVE; Tok.KW_states)
fun yyAction4 (strm, lastMatch) = (yystrm := strm;
       YYBEGIN DIRECTIVE; Tok.KW_let)
fun yyAction5 (strm, lastMatch) = (yystrm := strm;
       YYBEGIN CHARSET; Tok.KW_charset)
fun yyAction6 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;  Tok.ID yytext
      end
fun yyAction7 (strm, lastMatch) = (yystrm := strm;  Tok.COMMA)
fun yyAction8 (strm, lastMatch) = (yystrm := strm;  YYBEGIN INITIAL; Tok.SEMI)
fun yyAction9 (strm, lastMatch) = (yystrm := strm;  YYBEGIN INITIAL; Tok.EQ)
fun yyAction10 (strm, lastMatch) = (yystrm := strm;  YYBEGIN INITIAL; Tok.GT)
fun yyAction11 (strm, lastMatch) = let
      val oldStrm = !(yystrm)
      fun REJECT () = (yystrm := oldStrm; yystuck(lastMatch))
      in
        yystrm := strm;  YYBEGIN INITIAL; REJECT()
      end
fun yyAction12 (strm, lastMatch) = (yystrm := strm;  YYBEGIN INITIAL; Tok.UTF8)
fun yyAction13 (strm, lastMatch) = (yystrm := strm;
       YYBEGIN INITIAL; Tok.ASCII7)
fun yyAction14 (strm, lastMatch) = (yystrm := strm;
       YYBEGIN INITIAL; Tok.ASCII8)
fun yyAction15 (strm, lastMatch) = (yystrm := strm;  YYBEGIN INITIAL; Tok.SEMI)
fun yyAction16 (strm, lastMatch) = let
      val oldStrm = !(yystrm)
      fun REJECT () = (yystrm := oldStrm; yystuck(lastMatch))
      in
        yystrm := strm;  YYBEGIN INITIAL; REJECT()
      end
fun yyAction17 (strm, lastMatch) = (yystrm := strm;  Tok.BAR)
fun yyAction18 (strm, lastMatch) = (yystrm := strm;  Tok.DOT)
fun yyAction19 (strm, lastMatch) = (yystrm := strm;  Tok.DOLLAR)
fun yyAction20 (strm, lastMatch) = (yystrm := strm;  Tok.PLUS)
fun yyAction21 (strm, lastMatch) = (yystrm := strm;  Tok.STAR)
fun yyAction22 (strm, lastMatch) = (yystrm := strm;  Tok.QUERY)
fun yyAction23 (strm, lastMatch) = (yystrm := strm;  Tok.SEMI)
fun yyAction24 (strm, lastMatch) = (yystrm := strm;  Tok.LP)
fun yyAction25 (strm, lastMatch) = (yystrm := strm;  Tok.RP)
fun yyAction26 (strm, lastMatch) = (yystrm := strm;
       YYBEGIN CHARCLASS; Tok.LSB)
fun yyAction27 (strm, lastMatch) = (yystrm := strm;  Tok.RSB)
fun yyAction28 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;  Tok.ID (chomp yytext)
      end
fun yyAction29 (strm, lastMatch) = let
      val yysubstr = yymksubstr(strm)
      in
        yystrm := strm;
         (Tok.REPEAT o valOf o Int.fromString o 
		     Substring.string o (Substring.triml 1) o
		     (Substring.trimr 1)) yysubstr
      end
fun yyAction30 (strm, lastMatch) = (yystrm := strm;  YYBEGIN DIRECTIVE; Tok.LT)
fun yyAction31 (strm, lastMatch) = (yystrm := strm;  Tok.GT)
fun yyAction32 (strm, lastMatch) = (yystrm := strm;  Tok.COMMA)
fun yyAction33 (strm, lastMatch) = (yystrm := strm;  Tok.SLASH)
fun yyAction34 (strm, lastMatch) = (yystrm := strm;  Tok.EQ)
fun yyAction35 (strm, lastMatch) = (yystrm := strm;
       YYBEGIN CODE; clrText(); Tok.DARROW)
fun yyAction36 (strm, lastMatch) = (yystrm := strm;
       YYBEGIN STRING; clrText(); 
		    ignore(continue() before YYBEGIN INITIAL);
		    (Tok.STRING o valOf o String.fromString o getText)())
fun yyAction37 (strm, lastMatch) = (yystrm := strm;  Tok.CARAT)
fun yyAction38 (strm, lastMatch) = (yystrm := strm;  Tok.DASH)
fun yyAction39 (strm, lastMatch) = let
      val yylineno = ref(yygetlineNo(!(yystrm)))
      val yytext = yymktext(strm)
      in
        yystrm := strm;
         let val c = Char.fromString yytext
            in case c
                of SOME c' => Tok.CHAR c'
		 | NONE => (print (concat [
		     Int.toString (!yylineno), ": unknown escape sequence '", 
		     yytext, "'\n"]);
		     continue())
            end
      end
fun yyAction40 (strm, lastMatch) = (yystrm := strm;  YYBEGIN INITIAL; Tok.RSB)
fun yyAction41 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;  Tok.CHAR (String.sub (yytext, 0))
      end
fun yyAction42 (strm, lastMatch) = let
      val yylineno = ref(yygetlineNo(!(yystrm)))
      in
        yystrm := strm;
         comLvl := 1; comStart := !yylineno; YYBEGIN COM; 
	    ignore(continue() before YYBEGIN INITIAL);
	    continue()
      end
fun yyAction43 (strm, lastMatch) = let
      val yylineno = ref(yygetlineNo(!(yystrm)))
      val yytext = yymktext(strm)
      in
        yystrm := strm;
         comLvl := 1; comStart := !yylineno; YYBEGIN COM; 
	    addText yytext;
	    ignore(continue() before YYBEGIN CODE);
	    continue()
      end
fun yyAction44 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;  addText yytext; comLvl := !comLvl+1; continue()
      end
fun yyAction45 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;
         addText yytext; comLvl := !comLvl-1; 
	    if (!comLvl = 0) 
	      then (Tok.BOGUS) 
	      else continue()
      end
fun yyAction46 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;  addText yytext; continue()
      end
fun yyAction47 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;
         if !pcount = 0 then () else addText yytext;
		    inc pcount; continue()
      end
fun yyAction48 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;
         dec pcount; 
		    if !pcount = 0 then
		      (YYBEGIN INITIAL; Tok.CODE (getText()))
		    else (addText yytext; continue())
      end
fun yyAction49 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;
         addText yytext; YYBEGIN STRING; 
		    ignore(continue() before YYBEGIN CODE);
		    addText "\""; continue()
      end
fun yyAction50 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;  addText yytext; continue()
      end
fun yyAction51 (strm, lastMatch) = (yystrm := strm;  Tok.BOGUS)
fun yyAction52 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;
         addText yytext; print ("unclosed string");
 	            Tok.BOGUS
      end
fun yyAction53 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;  addText yytext; continue()
      end
fun yyAction54 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;  addText yytext; continue()
      end
fun yyAction55 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;  addText yytext; continue()
      end
fun yyAction56 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;  addText yytext; continue()
      end
fun yyAction57 (strm, lastMatch) = let
      val yytext = yymktext(strm)
      in
        yystrm := strm;  Tok.CHAR (String.sub (yytext, 0))
      end
fun yyAction58 (strm, lastMatch) = let
      val yylineno = ref(yygetlineNo(!(yystrm)))
      val yytext = yymktext(strm)
      in
        yystrm := strm;
         print (concat[Int.toString (!yylineno), ": illegal character '", 
				  String.toCString yytext, "'\n"]);
		    continue()
      end
fun yyQ115 (strm, lastMatch) = yyAction7(strm, yyNO_MATCH)
fun yyQ116 (strm, lastMatch) = yyAction8(strm, yyNO_MATCH)
fun yyQ117 (strm, lastMatch) = yyAction9(strm, yyNO_MATCH)
fun yyQ118 (strm, lastMatch) = yyAction10(strm, yyNO_MATCH)
fun yyQ119 (strm, lastMatch) = yyAction11(strm, yyMATCH(strm, yyAction58, yyNO_MATCH))
fun yyQ123 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction6(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx5B
              then yyAction6(strm, yyNO_MATCH)
            else if inp < 0wx5B
              then if inp = 0wx3A
                  then yyAction6(strm, yyNO_MATCH)
                else if inp < 0wx3A
                  then if inp <= 0wx2F
                      then yyAction6(strm, yyNO_MATCH)
                      else yyQ123(strm', yyMATCH(strm, yyAction6, yyNO_MATCH))
                else if inp <= 0wx40
                  then yyAction6(strm, yyNO_MATCH)
                  else yyQ123(strm', yyMATCH(strm, yyAction6, yyNO_MATCH))
            else if inp = 0wx60
              then yyAction6(strm, yyNO_MATCH)
            else if inp < 0wx60
              then if inp = 0wx5F
                  then yyQ123(strm', yyMATCH(strm, yyAction6, yyNO_MATCH))
                  else yyAction6(strm, yyNO_MATCH)
            else if inp <= 0wx7A
              then yyQ123(strm', yyMATCH(strm, yyAction6, yyNO_MATCH))
              else yyAction6(strm, yyNO_MATCH)
      (* end case *))
fun yyQ120 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction6(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx5B
              then yyAction6(strm, yyNO_MATCH)
            else if inp < 0wx5B
              then if inp = 0wx3A
                  then yyAction6(strm, yyNO_MATCH)
                else if inp < 0wx3A
                  then if inp <= 0wx2F
                      then yyAction6(strm, yyNO_MATCH)
                      else yyQ123(strm', yyMATCH(strm, yyAction6, yyNO_MATCH))
                else if inp <= 0wx40
                  then yyAction6(strm, yyNO_MATCH)
                  else yyQ123(strm', yyMATCH(strm, yyAction6, yyNO_MATCH))
            else if inp = 0wx60
              then yyAction6(strm, yyNO_MATCH)
            else if inp < 0wx60
              then if inp = 0wx5F
                  then yyQ123(strm', yyMATCH(strm, yyAction6, yyNO_MATCH))
                  else yyAction6(strm, yyNO_MATCH)
            else if inp <= 0wx7A
              then yyQ123(strm', yyMATCH(strm, yyAction6, yyNO_MATCH))
              else yyAction6(strm, yyNO_MATCH)
      (* end case *))
fun yyQ37 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction0(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyAction0(strm, yyNO_MATCH)
            else if inp < 0wxE
              then if inp = 0wx9
                  then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                else if inp < 0wx9
                  then yyAction0(strm, yyNO_MATCH)
                else if inp = 0wxD
                  then yyQ37(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                  else yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
            else if inp = 0wx20
              then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
              else yyAction0(strm, yyNO_MATCH)
      (* end case *))
and yyQ36 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction0(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyAction0(strm, yyNO_MATCH)
            else if inp < 0wxE
              then if inp = 0wx9
                  then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                else if inp < 0wx9
                  then yyAction0(strm, yyNO_MATCH)
                else if inp = 0wxD
                  then yyQ37(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                  else yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
            else if inp = 0wx20
              then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
              else yyAction0(strm, yyNO_MATCH)
      (* end case *))
fun yyQ121 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction0(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyAction0(strm, yyNO_MATCH)
            else if inp < 0wxE
              then if inp = 0wx9
                  then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                else if inp < 0wx9
                  then yyAction0(strm, yyNO_MATCH)
                else if inp = 0wxD
                  then yyQ37(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                  else yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
            else if inp = 0wx20
              then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
              else yyAction0(strm, yyNO_MATCH)
      (* end case *))
fun yyQ122 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction0(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyAction0(strm, yyNO_MATCH)
            else if inp < 0wxE
              then if inp = 0wx9
                  then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                else if inp < 0wx9
                  then yyAction0(strm, yyNO_MATCH)
                else if inp = 0wxD
                  then yyQ37(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                  else yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
            else if inp = 0wx20
              then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
              else yyAction0(strm, yyNO_MATCH)
      (* end case *))
fun yyQ6 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => if yyInput.eof(strm)
              then raise yyEOF
              else yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx2D
              then yyQ119(strm', lastMatch)
            else if inp < 0wx2D
              then if inp = 0wxD
                  then yyQ121(strm', lastMatch)
                else if inp < 0wxD
                  then if inp = 0wxA
                      then yyQ36(strm', lastMatch)
                    else if inp < 0wxA
                      then if inp = 0wx9
                          then yyQ122(strm', lastMatch)
                          else yyQ119(strm', lastMatch)
                      else yyQ122(strm', lastMatch)
                else if inp = 0wx21
                  then yyQ119(strm', lastMatch)
                else if inp < 0wx21
                  then if inp = 0wx20
                      then yyQ122(strm', lastMatch)
                      else yyQ119(strm', lastMatch)
                else if inp = 0wx2C
                  then yyQ115(strm', lastMatch)
                  else yyQ119(strm', lastMatch)
            else if inp = 0wx3F
              then yyQ119(strm', lastMatch)
            else if inp < 0wx3F
              then if inp = 0wx3C
                  then yyQ119(strm', lastMatch)
                else if inp < 0wx3C
                  then if inp = 0wx3B
                      then yyQ116(strm', lastMatch)
                      else yyQ119(strm', lastMatch)
                else if inp = 0wx3D
                  then yyQ117(strm', lastMatch)
                  else yyQ118(strm', lastMatch)
            else if inp = 0wx5B
              then yyQ119(strm', lastMatch)
            else if inp < 0wx5B
              then if inp <= 0wx40
                  then yyQ119(strm', lastMatch)
                  else yyQ120(strm', lastMatch)
            else if inp = 0wx61
              then yyQ120(strm', lastMatch)
            else if inp < 0wx61
              then yyQ119(strm', lastMatch)
            else if inp <= 0wx7A
              then yyQ120(strm', lastMatch)
              else yyQ119(strm', lastMatch)
      (* end case *))
fun yyQ61 (strm, lastMatch) = yyAction17(strm, yyNO_MATCH)
fun yyQ62 (strm, lastMatch) = yyAction18(strm, yyNO_MATCH)
fun yyQ63 (strm, lastMatch) = yyAction19(strm, yyNO_MATCH)
fun yyQ64 (strm, lastMatch) = yyAction20(strm, yyNO_MATCH)
fun yyQ65 (strm, lastMatch) = yyAction21(strm, yyNO_MATCH)
fun yyQ66 (strm, lastMatch) = yyAction22(strm, yyNO_MATCH)
fun yyQ67 (strm, lastMatch) = yyAction23(strm, yyNO_MATCH)
fun yyQ114 (strm, lastMatch) = yyAction42(strm, yyNO_MATCH)
fun yyQ68 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction24(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx2A
              then yyQ114(strm', yyMATCH(strm, yyAction24, yyNO_MATCH))
              else yyAction24(strm, yyNO_MATCH)
      (* end case *))
fun yyQ69 (strm, lastMatch) = yyAction25(strm, yyNO_MATCH)
fun yyQ70 (strm, lastMatch) = yyAction26(strm, yyNO_MATCH)
fun yyQ71 (strm, lastMatch) = yyAction27(strm, yyNO_MATCH)
fun yyQ72 (strm, lastMatch) = yyAction30(strm, yyNO_MATCH)
fun yyQ73 (strm, lastMatch) = yyAction31(strm, yyNO_MATCH)
fun yyQ74 (strm, lastMatch) = yyAction32(strm, yyNO_MATCH)
fun yyQ75 (strm, lastMatch) = yyAction33(strm, yyNO_MATCH)
fun yyQ113 (strm, lastMatch) = yyAction35(strm, yyNO_MATCH)
fun yyQ76 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction34(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx3E
              then yyQ113(strm', yyMATCH(strm, yyAction34, yyNO_MATCH))
              else yyAction34(strm, yyNO_MATCH)
      (* end case *))
fun yyQ77 (strm, lastMatch) = yyAction36(strm, yyNO_MATCH)
fun yyQ78 (strm, lastMatch) = yyAction57(strm, yyNO_MATCH)
fun yyQ79 (strm, lastMatch) = yyAction58(strm, yyNO_MATCH)
fun yyQ58 (strm, lastMatch) = yyAction39(strm, yyNO_MATCH)
fun yyQ60 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx30
              then yyQ58(strm', lastMatch)
            else if inp < 0wx30
              then yystuck(lastMatch)
            else if inp <= 0wx39
              then yyQ58(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ59 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx30
              then yyQ60(strm', lastMatch)
            else if inp < 0wx30
              then yystuck(lastMatch)
            else if inp <= 0wx39
              then yyQ60(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ80 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction57(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx5B
              then yyAction57(strm, yyNO_MATCH)
            else if inp < 0wx5B
              then if inp = 0wx3A
                  then yyAction57(strm, yyNO_MATCH)
                else if inp < 0wx3A
                  then if inp <= 0wx2F
                      then yyAction57(strm, yyNO_MATCH)
                      else yyQ59(strm', yyMATCH(strm, yyAction57, yyNO_MATCH))
                else if inp <= 0wx40
                  then yyAction57(strm, yyNO_MATCH)
                  else yyQ58(strm', yyMATCH(strm, yyAction57, yyNO_MATCH))
            else if inp = 0wx61
              then yyQ58(strm', yyMATCH(strm, yyAction57, yyNO_MATCH))
            else if inp < 0wx61
              then if inp = 0wx5C
                  then yyQ58(strm', yyMATCH(strm, yyAction57, yyNO_MATCH))
                  else yyAction57(strm, yyNO_MATCH)
            else if inp <= 0wx7A
              then yyQ58(strm', yyMATCH(strm, yyAction57, yyNO_MATCH))
              else yyAction57(strm, yyNO_MATCH)
      (* end case *))
fun yyQ112 (strm, lastMatch) = yyAction29(strm, yyNO_MATCH)
fun yyQ109 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx3A
              then yystuck(lastMatch)
            else if inp < 0wx3A
              then if inp <= 0wx2F
                  then yystuck(lastMatch)
                  else yyQ109(strm', lastMatch)
            else if inp = 0wx7D
              then yyQ112(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ111 (strm, lastMatch) = yyAction28(strm, yyNO_MATCH)
fun yyQ110 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx5F
              then yyQ110(strm', lastMatch)
            else if inp < 0wx5F
              then if inp = 0wx3A
                  then yystuck(lastMatch)
                else if inp < 0wx3A
                  then if inp <= 0wx2F
                      then yystuck(lastMatch)
                      else yyQ110(strm', lastMatch)
                else if inp = 0wx41
                  then yyQ110(strm', lastMatch)
                else if inp < 0wx41
                  then yystuck(lastMatch)
                else if inp <= 0wx5A
                  then yyQ110(strm', lastMatch)
                  else yystuck(lastMatch)
            else if inp = 0wx7B
              then yystuck(lastMatch)
            else if inp < 0wx7B
              then if inp = 0wx60
                  then yystuck(lastMatch)
                  else yyQ110(strm', lastMatch)
            else if inp = 0wx7D
              then yyQ111(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ81 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction58(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx41
              then yyQ110(strm', yyMATCH(strm, yyAction58, yyNO_MATCH))
            else if inp < 0wx41
              then if inp = 0wx30
                  then yyQ109(strm', yyMATCH(strm, yyAction58, yyNO_MATCH))
                else if inp < 0wx30
                  then yyAction58(strm, yyNO_MATCH)
                else if inp <= 0wx39
                  then yyQ109(strm', yyMATCH(strm, yyAction58, yyNO_MATCH))
                  else yyAction58(strm, yyNO_MATCH)
            else if inp = 0wx61
              then yyQ110(strm', yyMATCH(strm, yyAction58, yyNO_MATCH))
            else if inp < 0wx61
              then if inp <= 0wx5A
                  then yyQ110(strm', yyMATCH(strm, yyAction58, yyNO_MATCH))
                  else yyAction58(strm, yyNO_MATCH)
            else if inp <= 0wx7A
              then yyQ110(strm', yyMATCH(strm, yyAction58, yyNO_MATCH))
              else yyAction58(strm, yyNO_MATCH)
      (* end case *))
fun yyQ108 (strm, lastMatch) = yyAction5(strm, yyNO_MATCH)
fun yyQ107 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx74
              then yyQ108(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ106 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx65
              then yyQ107(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ105 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx73
              then yyQ106(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ104 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx72
              then yyQ105(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ103 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx61
              then yyQ104(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ85 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx68
              then yyQ103(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ102 (strm, lastMatch) = yyAction4(strm, yyNO_MATCH)
fun yyQ101 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx74
              then yyQ102(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ86 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx65
              then yyQ101(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ100 (strm, lastMatch) = yyAction3(strm, yyNO_MATCH)
fun yyQ99 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx73
              then yyQ100(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ98 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx65
              then yyQ99(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ97 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx74
              then yyQ98(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ96 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx61
              then yyQ97(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ87 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx74
              then yyQ96(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ95 (strm, lastMatch) = yyAction2(strm, yyNO_MATCH)
fun yyQ94 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx65
              then yyQ95(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ93 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx6D
              then yyQ94(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ88 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx61
              then yyQ93(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ92 (strm, lastMatch) = yyAction1(strm, yyNO_MATCH)
fun yyQ91 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx73
              then yyQ92(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ90 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx66
              then yyQ91(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ89 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx65
              then yyQ90(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ82 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction57(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx6D
              then yyAction57(strm, yyNO_MATCH)
            else if inp < 0wx6D
              then if inp = 0wx64
                  then yyQ89(strm', yyMATCH(strm, yyAction57, yyNO_MATCH))
                else if inp < 0wx64
                  then if inp = 0wx63
                      then yyQ85(strm', yyMATCH(strm, yyAction57, yyNO_MATCH))
                      else yyAction57(strm, yyNO_MATCH)
                else if inp = 0wx6C
                  then yyQ86(strm', yyMATCH(strm, yyAction57, yyNO_MATCH))
                  else yyAction57(strm, yyNO_MATCH)
            else if inp = 0wx73
              then yyQ87(strm', yyMATCH(strm, yyAction57, yyNO_MATCH))
            else if inp < 0wx73
              then if inp = 0wx6E
                  then yyQ88(strm', yyMATCH(strm, yyAction57, yyNO_MATCH))
                  else yyAction57(strm, yyNO_MATCH)
              else yyAction57(strm, yyNO_MATCH)
      (* end case *))
fun yyQ83 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction0(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyAction0(strm, yyNO_MATCH)
            else if inp < 0wxE
              then if inp = 0wx9
                  then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                else if inp < 0wx9
                  then yyAction0(strm, yyNO_MATCH)
                else if inp = 0wxD
                  then yyQ37(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                  else yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
            else if inp = 0wx20
              then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
              else yyAction0(strm, yyNO_MATCH)
      (* end case *))
fun yyQ84 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction0(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyAction0(strm, yyNO_MATCH)
            else if inp < 0wxE
              then if inp = 0wx9
                  then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                else if inp < 0wx9
                  then yyAction0(strm, yyNO_MATCH)
                else if inp = 0wxD
                  then yyQ37(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                  else yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
            else if inp = 0wx20
              then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
              else yyAction0(strm, yyNO_MATCH)
      (* end case *))
fun yyQ5 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => if yyInput.eof(strm)
              then raise yyEOF
              else yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx2D
              then yyQ78(strm', lastMatch)
            else if inp < 0wx2D
              then if inp = 0wx23
                  then yyQ78(strm', lastMatch)
                else if inp < 0wx23
                  then if inp = 0wxD
                      then yyQ83(strm', lastMatch)
                    else if inp < 0wxD
                      then if inp = 0wxA
                          then yyQ36(strm', lastMatch)
                        else if inp < 0wxA
                          then if inp = 0wx9
                              then yyQ84(strm', lastMatch)
                              else yyQ78(strm', lastMatch)
                          else yyQ84(strm', lastMatch)
                    else if inp = 0wx21
                      then yyQ78(strm', lastMatch)
                    else if inp < 0wx21
                      then if inp = 0wx20
                          then yyQ84(strm', lastMatch)
                          else yyQ78(strm', lastMatch)
                      else yyQ77(strm', lastMatch)
                else if inp = 0wx29
                  then yyQ69(strm', lastMatch)
                else if inp < 0wx29
                  then if inp = 0wx26
                      then yyQ78(strm', lastMatch)
                    else if inp < 0wx26
                      then if inp = 0wx24
                          then yyQ63(strm', lastMatch)
                          else yyQ82(strm', lastMatch)
                    else if inp = 0wx28
                      then yyQ68(strm', lastMatch)
                      else yyQ78(strm', lastMatch)
                else if inp = 0wx2B
                  then yyQ64(strm', lastMatch)
                else if inp = 0wx2A
                  then yyQ65(strm', lastMatch)
                  else yyQ74(strm', lastMatch)
            else if inp = 0wx40
              then yyQ78(strm', lastMatch)
            else if inp < 0wx40
              then if inp = 0wx3C
                  then yyQ72(strm', lastMatch)
                else if inp < 0wx3C
                  then if inp = 0wx30
                      then yyQ78(strm', lastMatch)
                    else if inp < 0wx30
                      then if inp = 0wx2E
                          then yyQ62(strm', lastMatch)
                          else yyQ75(strm', lastMatch)
                    else if inp = 0wx3B
                      then yyQ67(strm', lastMatch)
                      else yyQ78(strm', lastMatch)
                else if inp = 0wx3E
                  then yyQ73(strm', lastMatch)
                else if inp = 0wx3D
                  then yyQ76(strm', lastMatch)
                  else yyQ66(strm', lastMatch)
            else if inp = 0wx5E
              then yyQ78(strm', lastMatch)
            else if inp < 0wx5E
              then if inp = 0wx5C
                  then yyQ80(strm', lastMatch)
                else if inp < 0wx5C
                  then if inp = 0wx5B
                      then yyQ70(strm', lastMatch)
                      else yyQ78(strm', lastMatch)
                  else yyQ71(strm', lastMatch)
            else if inp = 0wx7C
              then yyQ61(strm', lastMatch)
            else if inp < 0wx7C
              then if inp = 0wx7B
                  then yyQ81(strm', lastMatch)
                  else yyQ78(strm', lastMatch)
            else if inp = 0wx7D
              then yyQ79(strm', lastMatch)
              else yyQ78(strm', lastMatch)
      (* end case *))
fun yyQ51 (strm, lastMatch) = yyAction37(strm, yyNO_MATCH)
fun yyQ52 (strm, lastMatch) = yyAction38(strm, yyNO_MATCH)
fun yyQ53 (strm, lastMatch) = yyAction40(strm, yyNO_MATCH)
fun yyQ54 (strm, lastMatch) = yyAction41(strm, yyNO_MATCH)
fun yyQ55 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction58(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx5B
              then yyAction58(strm, yyNO_MATCH)
            else if inp < 0wx5B
              then if inp = 0wx3A
                  then yyAction58(strm, yyNO_MATCH)
                else if inp < 0wx3A
                  then if inp <= 0wx2F
                      then yyAction58(strm, yyNO_MATCH)
                      else yyQ59(strm', yyMATCH(strm, yyAction58, yyNO_MATCH))
                else if inp <= 0wx40
                  then yyAction58(strm, yyNO_MATCH)
                  else yyQ58(strm', yyMATCH(strm, yyAction58, yyNO_MATCH))
            else if inp = 0wx61
              then yyQ58(strm', yyMATCH(strm, yyAction58, yyNO_MATCH))
            else if inp < 0wx61
              then if inp = 0wx5C
                  then yyQ58(strm', yyMATCH(strm, yyAction58, yyNO_MATCH))
                  else yyAction58(strm, yyNO_MATCH)
            else if inp <= 0wx7A
              then yyQ58(strm', yyMATCH(strm, yyAction58, yyNO_MATCH))
              else yyAction58(strm, yyNO_MATCH)
      (* end case *))
fun yyQ56 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction0(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyAction0(strm, yyNO_MATCH)
            else if inp < 0wxE
              then if inp = 0wx9
                  then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                else if inp < 0wx9
                  then yyAction0(strm, yyNO_MATCH)
                else if inp = 0wxD
                  then yyQ37(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                  else yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
            else if inp = 0wx20
              then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
              else yyAction0(strm, yyNO_MATCH)
      (* end case *))
fun yyQ57 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction0(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyAction0(strm, yyNO_MATCH)
            else if inp < 0wxE
              then if inp = 0wx9
                  then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                else if inp < 0wx9
                  then yyAction0(strm, yyNO_MATCH)
                else if inp = 0wxD
                  then yyQ37(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                  else yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
            else if inp = 0wx20
              then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
              else yyAction0(strm, yyNO_MATCH)
      (* end case *))
fun yyQ4 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => if yyInput.eof(strm)
              then raise yyEOF
              else yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx21
              then yyQ54(strm', lastMatch)
            else if inp < 0wx21
              then if inp = 0wxB
                  then yyQ57(strm', lastMatch)
                else if inp < 0wxB
                  then if inp = 0wx9
                      then yyQ57(strm', lastMatch)
                    else if inp = 0wxA
                      then yyQ36(strm', lastMatch)
                      else yyQ54(strm', lastMatch)
                else if inp = 0wxE
                  then yyQ54(strm', lastMatch)
                else if inp < 0wxE
                  then if inp = 0wxD
                      then yyQ56(strm', lastMatch)
                      else yyQ57(strm', lastMatch)
                else if inp = 0wx20
                  then yyQ57(strm', lastMatch)
                  else yyQ54(strm', lastMatch)
            else if inp = 0wx5C
              then yyQ55(strm', lastMatch)
            else if inp < 0wx5C
              then if inp = 0wx2D
                  then yyQ52(strm', lastMatch)
                  else yyQ54(strm', lastMatch)
            else if inp = 0wx5E
              then yyQ51(strm', lastMatch)
            else if inp = 0wx5D
              then yyQ53(strm', lastMatch)
              else yyQ54(strm', lastMatch)
      (* end case *))
fun yyQ28 (strm, lastMatch) = yyAction15(strm, yyNO_MATCH)
fun yyQ29 (strm, lastMatch) = yyAction16(strm, yyMATCH(strm, yyAction58, yyNO_MATCH))
fun yyQ46 (strm, lastMatch) = yyAction13(strm, yyNO_MATCH)
fun yyQ47 (strm, lastMatch) = yyAction14(strm, yyNO_MATCH)
fun yyQ45 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx38
              then yyQ47(strm', lastMatch)
            else if inp < 0wx38
              then if inp = 0wx37
                  then yyQ46(strm', lastMatch)
                  else yystuck(lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ50 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx49
              then yyQ45(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ49 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx49
              then yyQ50(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ48 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx43
              then yyQ49(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ30 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction16(strm, yyMATCH(strm, yyAction58, yyNO_MATCH))
        | SOME(inp, strm') =>
            if inp = 0wx53
              then yyQ48(strm', yyMATCH(strm, yyAction16, yyMATCH(strm, yyAction58, yyNO_MATCH)))
              else yyAction16(strm, yyMATCH(strm, yyAction58, yyNO_MATCH))
      (* end case *))
fun yyQ44 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx69
              then yyQ45(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ43 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx69
              then yyQ44(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ42 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx63
              then yyQ43(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ31 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction16(strm, yyMATCH(strm, yyAction58, yyNO_MATCH))
        | SOME(inp, strm') =>
            if inp = 0wx73
              then yyQ42(strm', yyMATCH(strm, yyAction16, yyMATCH(strm, yyAction58, yyNO_MATCH)))
              else yyAction16(strm, yyMATCH(strm, yyAction58, yyNO_MATCH))
      (* end case *))
fun yyQ40 (strm, lastMatch) = yyAction12(strm, yyNO_MATCH)
fun yyQ39 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx38
              then yyQ40(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ41 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx46
              then yyQ39(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ32 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction16(strm, yyMATCH(strm, yyAction58, yyNO_MATCH))
        | SOME(inp, strm') =>
            if inp = 0wx54
              then yyQ41(strm', yyMATCH(strm, yyAction16, yyMATCH(strm, yyAction58, yyNO_MATCH)))
              else yyAction16(strm, yyMATCH(strm, yyAction58, yyNO_MATCH))
      (* end case *))
fun yyQ38 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx66
              then yyQ39(strm', lastMatch)
              else yystuck(lastMatch)
      (* end case *))
fun yyQ33 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction16(strm, yyMATCH(strm, yyAction58, yyNO_MATCH))
        | SOME(inp, strm') =>
            if inp = 0wx74
              then yyQ38(strm', yyMATCH(strm, yyAction16, yyMATCH(strm, yyAction58, yyNO_MATCH)))
              else yyAction16(strm, yyMATCH(strm, yyAction58, yyNO_MATCH))
      (* end case *))
fun yyQ34 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction0(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyAction0(strm, yyNO_MATCH)
            else if inp < 0wxE
              then if inp = 0wx9
                  then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                else if inp < 0wx9
                  then yyAction0(strm, yyNO_MATCH)
                else if inp = 0wxD
                  then yyQ37(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                  else yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
            else if inp = 0wx20
              then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
              else yyAction0(strm, yyNO_MATCH)
      (* end case *))
fun yyQ35 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction0(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyAction0(strm, yyNO_MATCH)
            else if inp < 0wxE
              then if inp = 0wx9
                  then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                else if inp < 0wx9
                  then yyAction0(strm, yyNO_MATCH)
                else if inp = 0wxD
                  then yyQ37(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
                  else yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
            else if inp = 0wx20
              then yyQ36(strm', yyMATCH(strm, yyAction0, yyNO_MATCH))
              else yyAction0(strm, yyNO_MATCH)
      (* end case *))
fun yyQ3 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => if yyInput.eof(strm)
              then raise yyEOF
              else yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx3C
              then yyQ29(strm', lastMatch)
            else if inp < 0wx3C
              then if inp = 0wxD
                  then yyQ34(strm', lastMatch)
                else if inp < 0wxD
                  then if inp = 0wxA
                      then yyQ36(strm', lastMatch)
                    else if inp < 0wxA
                      then if inp = 0wx9
                          then yyQ35(strm', lastMatch)
                          else yyQ29(strm', lastMatch)
                      else yyQ35(strm', lastMatch)
                else if inp = 0wx21
                  then yyQ29(strm', lastMatch)
                else if inp < 0wx21
                  then if inp = 0wx20
                      then yyQ35(strm', lastMatch)
                      else yyQ29(strm', lastMatch)
                else if inp = 0wx3B
                  then yyQ28(strm', lastMatch)
                  else yyQ29(strm', lastMatch)
            else if inp = 0wx56
              then yyQ29(strm', lastMatch)
            else if inp < 0wx56
              then if inp = 0wx42
                  then yyQ29(strm', lastMatch)
                else if inp < 0wx42
                  then if inp = 0wx41
                      then yyQ30(strm', lastMatch)
                      else yyQ29(strm', lastMatch)
                else if inp = 0wx55
                  then yyQ32(strm', lastMatch)
                  else yyQ29(strm', lastMatch)
            else if inp = 0wx62
              then yyQ29(strm', lastMatch)
            else if inp < 0wx62
              then if inp = 0wx61
                  then yyQ31(strm', lastMatch)
                  else yyQ29(strm', lastMatch)
            else if inp = 0wx75
              then yyQ33(strm', lastMatch)
              else yyQ29(strm', lastMatch)
      (* end case *))
fun yyQ20 (strm, lastMatch) = yyAction51(strm, yyNO_MATCH)
fun yyQ21 (strm, lastMatch) = yyAction52(strm, yyNO_MATCH)
fun yyQ26 (strm, lastMatch) = yyAction54(strm, yyNO_MATCH)
fun yyQ27 (strm, lastMatch) = yyAction55(strm, yyNO_MATCH)
fun yyQ22 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction53(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx23
              then yyAction53(strm, yyNO_MATCH)
            else if inp < 0wx23
              then if inp = 0wx22
                  then yyQ27(strm', yyMATCH(strm, yyAction53, yyNO_MATCH))
                  else yyAction53(strm, yyNO_MATCH)
            else if inp = 0wx5C
              then yyQ26(strm', yyMATCH(strm, yyAction53, yyNO_MATCH))
              else yyAction53(strm, yyNO_MATCH)
      (* end case *))
fun yyQ25 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction56(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
            else if inp < 0wxE
              then if inp = 0wxB
                  then yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
                else if inp < 0wxB
                  then if inp = 0wxA
                      then yyAction56(strm, yyNO_MATCH)
                      else yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
                else if inp = 0wxD
                  then yyAction56(strm, yyNO_MATCH)
                  else yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
            else if inp = 0wx23
              then yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
            else if inp < 0wx23
              then if inp = 0wx22
                  then yyAction56(strm, yyNO_MATCH)
                  else yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
            else if inp = 0wx5C
              then yyAction56(strm, yyNO_MATCH)
              else yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
      (* end case *))
fun yyQ23 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction56(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
            else if inp < 0wxE
              then if inp = 0wxB
                  then yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
                else if inp < 0wxB
                  then if inp = 0wxA
                      then yyAction56(strm, yyNO_MATCH)
                      else yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
                else if inp = 0wxD
                  then yyAction56(strm, yyNO_MATCH)
                  else yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
            else if inp = 0wx23
              then yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
            else if inp < 0wx23
              then if inp = 0wx22
                  then yyAction56(strm, yyNO_MATCH)
                  else yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
            else if inp = 0wx5C
              then yyAction56(strm, yyNO_MATCH)
              else yyQ25(strm', yyMATCH(strm, yyAction56, yyNO_MATCH))
      (* end case *))
fun yyQ24 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction52(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxA
              then yyQ21(strm', yyMATCH(strm, yyAction52, yyNO_MATCH))
              else yyAction52(strm, yyNO_MATCH)
      (* end case *))
fun yyQ2 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => if yyInput.eof(strm)
              then raise yyEOF
              else yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyQ23(strm', lastMatch)
            else if inp < 0wxE
              then if inp = 0wxB
                  then yyQ23(strm', lastMatch)
                else if inp < 0wxB
                  then if inp = 0wxA
                      then yyQ21(strm', lastMatch)
                      else yyQ23(strm', lastMatch)
                else if inp = 0wxD
                  then yyQ24(strm', lastMatch)
                  else yyQ23(strm', lastMatch)
            else if inp = 0wx23
              then yyQ23(strm', lastMatch)
            else if inp < 0wx23
              then if inp = 0wx22
                  then yyQ20(strm', lastMatch)
                  else yyQ23(strm', lastMatch)
            else if inp = 0wx5C
              then yyQ22(strm', lastMatch)
              else yyQ23(strm', lastMatch)
      (* end case *))
fun yyQ14 (strm, lastMatch) = yyAction48(strm, yyNO_MATCH)
fun yyQ15 (strm, lastMatch) = yyAction49(strm, yyNO_MATCH)
fun yyQ17 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction50(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx23
              then yyQ17(strm', yyMATCH(strm, yyAction50, yyNO_MATCH))
            else if inp < 0wx23
              then if inp = 0wx22
                  then yyAction50(strm, yyNO_MATCH)
                  else yyQ17(strm', yyMATCH(strm, yyAction50, yyNO_MATCH))
            else if inp = 0wx28
              then yyAction50(strm, yyNO_MATCH)
            else if inp < 0wx28
              then yyQ17(strm', yyMATCH(strm, yyAction50, yyNO_MATCH))
            else if inp <= 0wx29
              then yyAction50(strm, yyNO_MATCH)
              else yyQ17(strm', yyMATCH(strm, yyAction50, yyNO_MATCH))
      (* end case *))
fun yyQ16 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction50(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx23
              then yyQ17(strm', yyMATCH(strm, yyAction50, yyNO_MATCH))
            else if inp < 0wx23
              then if inp = 0wx22
                  then yyAction50(strm, yyNO_MATCH)
                  else yyQ17(strm', yyMATCH(strm, yyAction50, yyNO_MATCH))
            else if inp = 0wx28
              then yyAction50(strm, yyNO_MATCH)
            else if inp < 0wx28
              then yyQ17(strm', yyMATCH(strm, yyAction50, yyNO_MATCH))
            else if inp <= 0wx29
              then yyAction50(strm, yyNO_MATCH)
              else yyQ17(strm', yyMATCH(strm, yyAction50, yyNO_MATCH))
      (* end case *))
fun yyQ19 (strm, lastMatch) = yyAction43(strm, yyNO_MATCH)
fun yyQ18 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction47(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx2A
              then yyQ19(strm', yyMATCH(strm, yyAction47, yyNO_MATCH))
              else yyAction47(strm, yyNO_MATCH)
      (* end case *))
fun yyQ1 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => if yyInput.eof(strm)
              then raise yyEOF
              else yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wx23
              then yyQ16(strm', lastMatch)
            else if inp < 0wx23
              then if inp = 0wxB
                  then yyQ16(strm', lastMatch)
                else if inp < 0wxB
                  then if inp = 0wxA
                      then yyQ17(strm', lastMatch)
                      else yyQ16(strm', lastMatch)
                else if inp = 0wx22
                  then yyQ15(strm', lastMatch)
                  else yyQ16(strm', lastMatch)
            else if inp = 0wx29
              then yyQ14(strm', lastMatch)
            else if inp < 0wx29
              then if inp = 0wx28
                  then yyQ18(strm', lastMatch)
                  else yyQ16(strm', lastMatch)
              else yyQ16(strm', lastMatch)
      (* end case *))
fun yyQ7 (strm, lastMatch) = yyAction46(strm, yyNO_MATCH)
fun yyQ8 (strm, lastMatch) = yyAction46(strm, yyNO_MATCH)
fun yyQ9 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction46(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wxA
              then yyQ8(strm', yyMATCH(strm, yyAction46, yyNO_MATCH))
              else yyAction46(strm, yyNO_MATCH)
      (* end case *))
fun yyQ13 (strm, lastMatch) = yyAction45(strm, yyNO_MATCH)
fun yyQ10 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction46(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx29
              then yyQ13(strm', yyMATCH(strm, yyAction46, yyNO_MATCH))
              else yyAction46(strm, yyNO_MATCH)
      (* end case *))
fun yyQ12 (strm, lastMatch) = yyAction44(strm, yyNO_MATCH)
fun yyQ11 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => yyAction46(strm, yyNO_MATCH)
        | SOME(inp, strm') =>
            if inp = 0wx2A
              then yyQ12(strm', yyMATCH(strm, yyAction46, yyNO_MATCH))
              else yyAction46(strm, yyNO_MATCH)
      (* end case *))
fun yyQ0 (strm, lastMatch) = (case (yygetc(strm))
       of NONE => if yyInput.eof(strm)
              then raise yyEOF
              else yystuck(lastMatch)
        | SOME(inp, strm') =>
            if inp = 0wxE
              then yyQ7(strm', lastMatch)
            else if inp < 0wxE
              then if inp = 0wxB
                  then yyQ7(strm', lastMatch)
                else if inp < 0wxB
                  then if inp = 0wxA
                      then yyQ8(strm', lastMatch)
                      else yyQ7(strm', lastMatch)
                else if inp = 0wxD
                  then yyQ9(strm', lastMatch)
                  else yyQ7(strm', lastMatch)
            else if inp = 0wx29
              then yyQ7(strm', lastMatch)
            else if inp < 0wx29
              then if inp = 0wx28
                  then yyQ11(strm', lastMatch)
                  else yyQ7(strm', lastMatch)
            else if inp = 0wx2A
              then yyQ10(strm', lastMatch)
              else yyQ7(strm', lastMatch)
      (* end case *))
in
  (case (!(yyss))
   of COM => yyQ0(!(yystrm), yyNO_MATCH)
    | CODE => yyQ1(!(yystrm), yyNO_MATCH)
    | STRING => yyQ2(!(yystrm), yyNO_MATCH)
    | CHARSET => yyQ3(!(yystrm), yyNO_MATCH)
    | CHARCLASS => yyQ4(!(yystrm), yyNO_MATCH)
    | INITIAL => yyQ5(!(yystrm), yyNO_MATCH)
    | DIRECTIVE => yyQ6(!(yystrm), yyNO_MATCH)
  (* end case *))
end
	    in continue() end
          in 
            lex 
	    handle IO.Io{cause, ...} => raise cause
          end
    
    type tok = UserDeclarations.lex_result
    datatype str = EVAL of tok * strm | UNEVAL of (unit -> tok)
    and strm = STRM of str ref

    fun lex(STRM (ref(EVAL t))) = SOME t
      | lex(STRM (s as ref(UNEVAL f))) = let
	  val tok = f()
          val t = (tok, STRM(ref(UNEVAL f))) 
          in
	    s := EVAL t; 
	    SOME(t)
          end
	  handle yyEOF => NONE

    fun streamify inputN = STRM(ref(UNEVAL (mk (yyInput.mkStream inputN))))

(*    fun cons(a,s) = STRM(ref(EVAL(a,s))) *)

  end
