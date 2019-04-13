%{
#include <stdlib.h>
#include <string.h>
#include "def.tab.hh"
#define printf(...)

extern int yylineno;
int yyerror(const char *msg,...);
%}
%%
\+								{return '+';} 
\*								{return '*';}
\(								{return '(';}
\)								{return ')';}
\{								{return '{';}
\}								{return '}';}
\/								{return '/';}
\-								{return '-';}
\^								{return '^';}
\=								{return '=';}
\<								{return '<';}
\>								{return '>';}
\<\=							{return LEQ;}
\>\=							{return GEQ;}
\=\=							{return EQ;}
\!\=							{return NEQ;}
\-\>							{printf("pointer/sizeptr\n");return 'p';}
"i32"							{printf("INT_32\n"); return INT_32;};
"d32"							{printf("DOUB_32\n"); return DOUB_32;};
"c8"							{printf("CHAR_8\n"); return CHAR_8;};
"if"							{printf("IF\n"); return IF;};
"while"							{printf("WHILE\n"); return WHILE;};
"pushheap"						{printf("PUSHHEAP\n"); return PUSHHEAP;};
"str"							{printf("STRING\n"); return STRING;};
"speaki"						{return SPEAKI;}
"speakf"						{return SPEAKF;}
"speaks"						{return SPEAKS;}
"scani"							{return SCANI;};
"scanf"							{return SCANF;};

([1-9][0-9]*|0)\.[0-9]+			{printf("float "); yylval.dval = atoi(yytext);return DOUBLE_VAL;};
[1-9][0-9]*|0					{printf("integer "); yylval.ival = atoi(yytext);return INTEGER_VAL;}	
[_a-zA-Z][_a-zA-Z0-9]*			{printf("nazwa "); yylval.text = strdup(yytext);return IDENTIFER;}
\;								{return ';';}
\ |\t       {;}
\n			{yylineno++ ;}
.			{yyerror("Blad leksykalny\n");}
%%
int yyerror(const char *msg,...)
{
	printf("%d: %s", yylineno, msg);
	exit(1);
}