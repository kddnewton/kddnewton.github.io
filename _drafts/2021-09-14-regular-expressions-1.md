https://github.com/k-takata/Onigmo/blob/master/doc/RE
https://learnbyexample.github.io/Ruby_Regexp/
https://www.unicode.org/reports/tr18/
https://github.com/jaynetics/regexp_property_values
https://github.com/ammar/regexp_parser
https://www.debuggex.com/

EXPR          ::= SUBEXPR QUANTIFIER? ("|"? SUBEXPR QUANTIFIER?)*

SUBEXPR       ::= "."
                | "^"
                | "$"
                | "(" EXPR ")"
                | "(" "?" (":" | "=" | "!" | ("<" ("=" | "!")) | "~" | ">" | "<" NAME ">" | "'" NAME "'" | "(" (NAME | NUMBER) ")" (EXPR "|")? | [imx] ("-" [imx])?) EXPR ")"
                | "\" POSITIVE
                | "\" [aBDdGHhKRSsWwXZz]
                | "\" "b" ("{" [gwls] "}")?
                | "\" "k" "<" ("-"? POSITIVE LEVEL? | NAME) ">"
                | "\" "k" "'" ("-"? POSITIVE LEVEL? | NAME) "'"
                | "\" "g" "<" (("+" | "-")? NUMBER | NAME) ">"
                | "\" "g" "'" (("+" | "-")? NUMBER | NAME) "'"
                | "\" "q" "{" (CODE_POINT (" " CODE_POINT)*)? "}"
                | CLASS
                | CODE_POINT

QUANTIFIER    ::= ("?" | "*" | "+") ("?" | "+")?
                | "{" (NUMBER "," NUMBER? | ","? NUMBER) "}" "?"?

CLASS         ::= "[" "^"? ITEM (("||" | "&&" | "--" | "~~")? ITEM)* "]"
                | "[" ":" "^"? PROPERTY ":]"
                | "[" "." CODEPOINT+ "." "]"
                | "[" "=" CODEPOINT "=" "]"
                | "\" "p" "{" "^"? PROPERTY "}"
                | "\" "P" "{" PROPERTY "}"

ITEM          ::= CLASS
                | CHARACTER ("-" CHARACTER)?

PROPERTY      ::= NAME                                          /* binary unicode property */
                | NAME (":" | "=" | "≠" | "!" "=") VALUE        /* unicode property */
                | NAME ("|" NAME)*                              /* script or category property value */

VALUE         ::= NAME ("|" NAME)*                              /* unicode property value */
                | "/" EXPR "/"
                | "@" PROPERTY "@"

CHARACTER     ::= "\" [abefnrtv]
                | "\" [0-9] [0-9] [0-9]
                | "\" "x" HEX HEX
                | "\" "u" HEX HEX HEX HEX
                | "\" "u" "{" HEX+ (SPACE+ HEX+)* "}"
                | "\" "N" "{" NAME "}"
                | "\" CODEPOINT
                | CODEPOINT

CODEPOINT     ::= [#x0-#x10FFFF]

NAME          ::= [a-zA-Z]+                                     /* Letter|Mark|Number|Connector_Punctuation */
HEX           ::= [a-fA-F0-9]
SPACE         ::= #x9 | #xA | #xD | #x20

DIGIT         ::= [0-9]
NUMBER        ::= DIGIT+
POSITIVE      ::= [1-9] DIGIT*
LEVEL         ::= ("+" | "-") NUMBER
