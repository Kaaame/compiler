%{
#include <string.h>
#include <stdio.h>
#include <fstream>
#include <stack>
#include <string>
#include <sstream>
#include <iostream>
#include <vector>
#include <map>

#define OUTPUT_STREAM stdout
#define printf(x)

#define INFILE_ERROR 1
#define OUTFILE_ERROR 2
//#define OUTPUT_STREAM stdout//i know of if def etc

FILE *dropfile;
extern "C" int yylex();
extern "C" int yyerror(const char *msg,...);
extern FILE* yyout;
extern FILE* yyin;

using namespace std;

typedef struct
{
	string value;
	int token;
} stack_pair;

stack<stack_pair> gStack;
stack<string> gEtiqStack;

map<string, int> dataSegmentSymbols;
vector<string> textSegment;

static int var_num = 0;
static int etiq_num = 0;
int last_op = 0;

void remove_pair(char op);
void generate_mips_asm(stack_pair *op1, stack_pair *op2, char op);
void make_line_asm(stack_pair *, int);
void make_conv_asm(stack_pair *, int);
void make_op_asm(stack_pair *, stack_pair *, char);
void make_store_asm(stack_pair *);
void write_textseg();
void write_dataseg();
void make_jmp_asm(int, string);
void gen_syscall(int);


stack_pair gEl;
string gStringEl;
/*
type
	: INT_32 IDENTIFER
	| DOUB_32 IDENTIFER
	| CHAR_8 IDENTIFER
	;
printf
	: SPEAK IDENTIFER
	| SPEAK INTEGER_VAL
	| SPEAK DOUBLE_VAL
	;
*/
%}
%union 
{char *text;
int	ival;
double dval;};
%token <text> IDENTIFER
%token <ival> INTEGER_VAL
%token <dval> DOUBLE_VAL
%token IF PUSHHEAP WHILE STRING FOR
%token LEQ EQ NEQ GEQ
%token INT_32 DOUB_32 CHAR_8
%token SPEAKI SPEAKF SPEAKS SCANI SCANF
%%
multistmt
	: multistmt stmt		{printf("multistmt\n");}
	| stmt					{printf("stmt\n");}
	;
stmt
	: assign ';'			{;}
	| io_expr ';'
	| if_expr				{}
	;
assign
	: IDENTIFER '=' expr	{fprintf(dropfile, "%s = ", $1);
							gEl.value = $1; gEl.token = IDENTIFER;
							gStack.push(gEl);
							remove_pair('=');}
	;
if_expr
	: if_begin '{' multistmt '}'{string res = gEtiqStack.top() + ":\n";
								gEtiqStack.pop();
								textSegment.push_back(res);}
	;
if_begin
	: IF '(' cond_expr ')'	{string lbl = "LBL" + to_string(etiq_num);
							make_jmp_asm(last_op, lbl);}
	;
cond_expr
	: expr op_logic expr
	;
io_expr
	: SPEAKI '(' expr ')'	{/*gen_syscall*/}
	| SPEAKF '(' expr ')'
	| SPEAKS '(' expr ')'
	| SCANI '(' expr ')'
	| SCANF '(' expr ')'
	;
expr
	: expr '+' component 	{fprintf(dropfile, " + ");remove_pair('+');}
	| expr '-' component     {fprintf(dropfile, " - ");remove_pair('-');}
	| component       		{printf("single expression\n");}
	;
component
	:component '*' factor	{fprintf(dropfile, " * ");remove_pair('*');}
	|component '/' factor	{fprintf(dropfile, " / ");remove_pair('/');}
	|factor		        	{printf("single component\n");}
	;
op_logic
	: '<'					{last_op = '<';}
	| GEQ					{last_op = GEQ;}
	| '>'					{last_op = '>';}
	| LEQ					{last_op = LEQ;}
	| EQ					{last_op = EQ;}
	| NEQ					{last_op = NEQ;}
	;
factor
	:IDENTIFER				{fprintf(dropfile, "%s ", $1);
							gEl.value = $1; gEl.token = IDENTIFER;
							gStack.push(gEl);} 
	|INTEGER_VAL            {fprintf(dropfile, "%d ", $1);
							gEl.value = to_string($1); gEl.token = INTEGER_VAL;
							gStack.push(gEl);}
    |DOUBLE_VAL				{fprintf(dropfile, "%f ", $1);
							gEl.value = to_string($1); gEl.token = DOUBLE_VAL;
							gStack.push(gEl);}
	|'(' expr ')'			{printf("expression in parentheses\n");}
	;
%%
void write_textseg()
{
	fprintf(yyout, ".text\n");
	for(const auto &it : textSegment)
	{
		//cout << it;
		fprintf(yyout,"\t%s", it.c_str());
	}
}

void write_dataseg()
{
	ostringstream oss;
	fprintf(yyout, ".data\n");
	for(map<string,int>::iterator it = dataSegmentSymbols.begin();
		it != dataSegmentSymbols.end(); ++it)
	{
		oss << it->first <<":\t";
		if(it->second == INTEGER_VAL)
		{
			oss <<".word\t0\n";
		}
		else
		{
			oss <<".word\t0\n";
			//oss <<".double\t0.0\n";
		}
		//cout << oss.str();
		fprintf(yyout, "\t%s", oss.str().c_str());
		oss.str("");
		oss.clear();
	}
}
void gen_syscall(int type)
{
	ostringstream oss;
	stack_pair op1;
	string pt;
	oss << "#" ;
	
	switch(type)
	{
		//SPEAKI SPEAKF SPEAKS SCANI SCANF
		case SPEAKI:
			pt = "SPEAKI(";
		break;
		case SPEAKF:
			pt = "SPEAKF(";
		break;
		case SPEAKS:
			pt = "SPEAKS(";
		break;
		case SCANI:
			pt = "SCANI(";
		break;
		case SCANF:
			pt = "SCANF(";
		break;		
	}

	op1 = gStack.top();
	gStack.pop();

	oss << op1.value << ")\n";
	textSegment.push_back(oss.str());
	oss.str("");
	oss.clear();

	

	make_line_asm(&op1, 0);
}

void make_jmp_asm(int condition, string label)
{
	ostringstream oss;
	stack_pair op1;
	stack_pair op2;

	string op_cond;

	oss << "#" << label << " ";
	//beq, bne, blt, ble, bgt, bge
	switch(condition)
	{
		case EQ://!=
			oss << "==" << " ";
			op_cond = "bne";
		break;

		case NEQ://==
			oss << "!=" << " ";
			op_cond = "beq";
		break;

		case '<'://>=
			oss << "<" << " ";
			op_cond = "bgt";
		break;

		case GEQ://<
			oss << ">=" << " ";
			op_cond = "blt";
		break;

		case '>'://<=
			oss << ">" << " ";
			op_cond = "ble";
		break;

		case LEQ://>
			oss << "<=" << " ";
			op_cond = "bgt";
		break;
	}
	
	
	

	op1 = gStack.top();
	gStack.pop();

	op2 = gStack.top();
	gStack.pop();

	oss  << op_cond << " " << op2.value << " " << op1.value << "\n";
	//cout << oss.str();
	textSegment.push_back(oss.str());
	oss.str("");
	oss.clear();

	make_line_asm(&op2, 0);
	make_line_asm(&op1, 1);
	oss << op_cond << " $t0, $t1, " << label << "\n";
	gEtiqStack.push(label);
	textSegment.push_back(oss.str());
	etiq_num++;
	//write_textseg();
}

void make_line_asm(stack_pair *arg, int nr)
{
	ostringstream oss;
	switch(arg->token)
	{
		case INTEGER_VAL:
		{
			oss << "li $t" << to_string(nr) << ", "<< arg->value << "\n";
		}
		break;
		case IDENTIFER:
		{
			oss << "lw $t" << to_string(nr) << ", "<< arg->value << "\n";
		}
		break;
		case DOUBLE_VAL:
		{
			oss << "l.s $t" << to_string(nr) << ", "<< arg->value << "\n";
		}
		break;
	}
	//cout << oss.str() << endl;
	textSegment.push_back(oss.str());
}

void make_conv_asm(stack_pair *arg, int type)
{

}

void make_op_asm(stack_pair *left, stack_pair *right, char op)
{
	ostringstream oss;

	switch(op)
	{
		case '+':
		{
			oss << "add";
		}
		break;
		case '-':
		{
			oss << "sub";
		}
		break;
		case '*':
		{
			oss << "mul";

		}
		break;
		case '/':
		{
			oss << "div";
		}
		break;
	}
	
	if(left->token == INTEGER_VAL && right->token == INTEGER_VAL)
	{
		oss << " $t0, $t0, $t1\n";
	}
	else if(left->token == IDENTIFER && right->token == INTEGER_VAL ||
			left->token == INTEGER_VAL && right->token == IDENTIFER)
	{
		oss << " $t0, $t0, $t1\n";
	}
	else
	{
		//oss << ".s $f0, $f0, $f1\n";
	}
	//cout << oss.str() << endl;
	textSegment.push_back(oss.str());
}

void make_store_asm(stack_pair *arg)
{
	ostringstream oss;
	// if(arg->token == INTEGER_VAL)
	// {
	// 	oss << "sw $t0, retval_" << var_num << "\n";
	// }
	// else if(arg->token == IDENTIFER)
	// {
		oss << "sw $t0, " << arg->value << "\n\n";
	// }
	// else
	// {
	// 	;
	// }
	//cout << oss.str() << endl;
	textSegment.push_back(oss.str());

}

void generate_mips_asm(stack_pair *left, stack_pair *right, char op)
{
	make_line_asm(left, 0);
	make_line_asm(right, 1);
	make_op_asm(left, right, op);
	make_store_asm(left);
	//makelineasm(z1, 0)
	//optional conversion flaot->int->float
	//makelineasm(z1, 1)
	//optional conversion flaot->int->float
	//makeoperation(z1, z2, op)
	//makestore
}

void remove_pair(char op)
{
	stack_pair op1;
	stack_pair op2;

	op1 = gStack.top();
	gStack.pop();

	op2 = gStack.top();
	gStack.pop();

	ostringstream oss;
	//if op1.type == LC ->li
	//   if op1.type == LF -> FLOAT_TMP ->l.s
	//if op1.type == ID -> INT ->lw t
	//   if op1.type == ID -> FLOAT ->l.s f

	//generate_mips_asm(&op2, &op1, op);
	oss << "#retval_" << var_num << " = " << op2.value << " " << op1.value << " " << op << "\n";
	textSegment.push_back(oss.str());
	//cout << oss.str() << endl;
	oss.str("");
	oss.clear();

	if(op != '=')
	{
		oss << "retval_" << var_num;
		gEl.value = oss.str();
		gEl.token = IDENTIFER;
		dataSegmentSymbols.insert(pair<string, int>(oss.str(), INTEGER_VAL));//wynika z op1 i op2
		gStack.push(gEl);
		var_num++;

		make_line_asm(&op2, 0);
		make_line_asm(&op1, 1);
		make_op_asm(&op2, &op1, op);
		make_store_asm(&gEl);

	}
	else
	{
		make_line_asm(&op2, 0);
		make_store_asm(&op1);
		
		dataSegmentSymbols.insert(pair<string, int>(op1.value, IDENTIFER));//przeniesc instrukcje do miejsca deklaracji
	}
}

int main(int argc, char **argv)
{
	if (argc>1)
	{
		yyin = fopen(argv[1], "r");
		if (yyin==NULL)
		{
			printf("Błąd\n");
			return INFILE_ERROR;
		}
		if (argc>2)
		{
			yyout=fopen(argv[2], "w");
			if (yyout==NULL)
			{
				printf("Błąd\n");
				return OUTFILE_ERROR;
			}
		}
	}

    dropfile = fopen("RPN_output.res", "wr");
    if(dropfile == NULL)
    {
        return -1;
    }

	

    yyparse();
	//fprint(yyout, "\t.data");
	write_dataseg();
	write_textseg();
	fclose(dropfile);

	// fstream fsthree;
	fstream fsrpn;
	// fsthree.open("thrices.res", fstream::out);
	fsrpn.open("RPN_output.res", fstream::in);

	while(!gStack.empty())
	{

		// gEl = gStack.top();
		// cout << gEl.value << '\n';
		// gStack.pop();
		yyerror("Brak pustego stosu!");
	}
	
	//yyout to FILE*

	// fsthree.close();
	fsrpn.close();
    return 0;
}