CC=gcc
CPP=g++
LEX=flex
YACC=bison
LD=gcc

all:	cmpl

cmpl:	def.tab.o lex.yy.o
	$(CPP) lex.yy.o def.tab.o -o cmpl -ll -std=c++11

lex.yy.o:	lex.yy.c
	$(CC) -c lex.yy.c

lex.yy.c: lexemes.l
	$(LEX) lexemes.l

def.tab.o:	def.tab.cc
	$(CPP) -c def.tab.cc -std=c++11

def.tab.cc:	def.yy
	$(YACC) -d def.yy

clean:
	rm -f *.o cmpl def.tab.cc lex.yy.c
