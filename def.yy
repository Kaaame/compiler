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
#define printf(...)

#define INFILE_ERROR 1
#define OUTFILE_ERROR 2

FILE *dropfile;
extern "C" int yylex();
extern "C" int yyerror(const char *msg,...);
extern FILE* yyout;
extern FILE* yyin;

using namespace std;

//struct var_info;

struct var_info
{
	int size;
	int type;
	string value;
	string name;
	//int register?
	//overloading lt op, so we can use this struct as key in dataSegmentSymbols
	bool operator< (const var_info& el) const
	{
		return (name.compare(el.name));
	}
};



struct stack_pair
{
	var_info info;
	int token;
};

stack<stack_pair> gStack;
stack<string> gEtiqStack;

map<var_info, int> dataSegmentSymbols;
vector<string> textSegment;
vector<string> dataSegment;

static int var_num = 0;
//static int for_num = 0;
static int etiq_num = 0;
int last_op = 0;
int else_op = 0;

void remove_pair(char op);
void generate_mips_asm(stack_pair *op1, stack_pair *op2, char op);
void make_line_asm(stack_pair *, string, int);
void load_addr_asm(stack_pair *, int);
void make_conv_asm(stack_pair *, int);
void make_op_asm(char, int, int, int);
void make_store_asm(string, int, string);

void write_textseg();
void write_dataseg();

void store_global(stack_pair);
void find_dataseg_item(string, stack_pair *);

void make_cond_jmp_asm(int, string, int, int);
void make_uncond_jmp_asm(string);
void gen_syscall(int, string);

void make_for_begin_asm(string, int);
void make_for_expr_asm();

stack_pair gEl;
string gStringEl;

%}
%union 
{char *text;
int	ival;
double dval;};
%token <text> IDENTIFER
%token <ival> INTEGER_VAL
%token <dval> DOUBLE_VAL
%token <text> STR_LITERAL
%token IF ELSE PUSHHEAP WHILE STRING FOR
%token LEQ EQ NEQ GEQ
%token INT_32 FLOAT_32 CSTR 
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
	| type ';'				{/*dataSegmentSymbols.insert(pair<string, int>(gStringEl, INT_32));*/;}
	| for_expr
	//| type assign ';'
	;
type
	: INT_32 IDENTIFER							{
													/*cout << "$2 = " << $2 << "\n";*/
													gEl.info.name = $2; gEl.info.value = "0";
													gEl.info.size = 1; gEl.info.type = INT_32;
													gEl.token = IDENTIFER;
													store_global(gEl);
													/*dataSegmentSymbols.insert(pair<string, int>($2, INT_32));*/
												}
	| FLOAT_32 IDENTIFER						{	
													gEl.info.name = $2; gEl.info.value = "0.0";
													gEl.info.size = 1; gEl.info.type = FLOAT_32;
													gEl.token = IDENTIFER;
													store_global(gEl);
													/*dataSegmentSymbols.insert(pair<string, int>($2, FLOAT_32));*/
												}
	| CSTR IDENTIFER '=' STR_LITERAL			{
													gEl.info.name = $2; gEl.info.value = $4;
													gEl.info.size = 1; gEl.info.type = CSTR;
													gEl.token = IDENTIFER;

													store_global(gEl);
													/*gEl.value = $2;
													gEl.token = IDENTIFER;
													gStack.push(gEl);*/
												}
	;
assign
	: IDENTIFER '=' expr	{fprintf(dropfile, "%s = ", $1);
							gEl.info.name = $1; gEl.token = IDENTIFER;
							gStack.push(gEl);
							remove_pair('=');}
	;
if_expr
	: if_begin '{' multistmt '}'			{
												string res = gEtiqStack.top() + ":\n";
												gEtiqStack.pop();
												textSegment.push_back(res);//last label
											}
	| if_begin '{' multistmt '}' else_expr	{
												string res = gEtiqStack.top() + ":\n";
												gEtiqStack.pop();
												textSegment.push_back(res);//last label

												
											}
	;
else_expr
	: else_begin '{' multistmt '}'		{
											
											// string res = gEtiqStack.top() + ":\n";
											// gEtiqStack.pop();
											// textSegment.push_back(res);
										}
	;
for_expr
	: for_begin '{' multistmt '}'
									{
										make_for_expr_asm();
									}
	|	for_begin '{' '}'
									{
										make_for_expr_asm();
										// string lastlbl = gEtiqStack.top();
										// gEtiqStack.pop();

										// string firstlbl = gEtiqStack.top();
										// gEtiqStack.pop();

										// make_uncond_jmp_asm(firstlbl);

										// textSegment.push_back(lastlbl + ":\n");//last label
									}
	;
else_begin
	: ELSE
		{
			string res = gEtiqStack.top() + ":\n";
			gEtiqStack.pop();

			string lbl = "LBL" + to_string(etiq_num);
			make_uncond_jmp_asm(lbl);
			gEtiqStack.push(lbl);
			etiq_num++;

			
			textSegment.push_back(res);//last label
		}
	;
if_begin
	: IF '(' cond_expr ')'	{
								string lbl = "LBL" + to_string(etiq_num);
								make_cond_jmp_asm(last_op, lbl, 0, 1);
								gEtiqStack.push(lbl);
								etiq_num++;
							}
	;
for_begin
	: FOR '(' IDENTIFER ';' cond_expr ';' INTEGER_VAL ')'
							{
								make_for_begin_asm($3, $7);

								// string firstlbl = "LBL" + to_string(etiq_num);
								// etiq_num++;
								// gEtiqStack.push(firstlbl);

								// string lastlbl = "LBL" + to_string(etiq_num);
								// etiq_num++;
								// gEtiqStack.push(lastlbl);

								// textSegment.push_back(firstlbl + ":\n");//last label
								
								// make_cond_jmp_asm(last_op, lastlbl, 4, 5);

								// stack_pair el;
								// find_dataseg_item($3, &el);
								
								// gEl.info.value = to_string($7); gEl.token = INTEGER_VAL;
								// gEl.info.name = ""; gEl.info.size = 0; gEl.info.type = INT_32;

								// textSegment.push_back("#it += " + to_string($7) + "\n");
								// make_line_asm(&el, "$t", 4);
								// make_line_asm(&gEl, "$t", 5);//substitute magic nr?
								// make_op_asm('+', INT_32, 4, 5);
								// make_store_asm("$t", 4, el.info.name);
								/*this might be bad, icreasing iterator right after jmp*/
							}
	;
cond_expr
	: expr op_logic expr
	;
io_expr
	: SPEAKI '(' IDENTIFER ')'		{gen_syscall(SPEAKI, $3);}
	| SPEAKF '(' IDENTIFER ')'		{gen_syscall(SPEAKF, $3);}
	| SPEAKS '(' IDENTIFER ')'	{gen_syscall(SPEAKS, $3);}
	| SCANI '(' IDENTIFER ')'	{gen_syscall(SCANI, $3);}
	| SCANF '(' IDENTIFER ')'	{gen_syscall(SCANF, $3);}
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
							gEl.info.name = $1; gEl.token = IDENTIFER; gEl.info.value = ""; gEl.info.size = 0;
							gStack.push(gEl);}
	|INTEGER_VAL            {fprintf(dropfile, "%d ", $1);
							gEl.info.value = to_string($1); gEl.token = INTEGER_VAL;
							gEl.info.name = ""; gEl.info.size = 0; gEl.info.type = INT_32;
							gStack.push(gEl);}
    |DOUBLE_VAL				{fprintf(dropfile, "%f ", $1);
							gEl.info.value = to_string($1); gEl.token = DOUBLE_VAL;
							gEl.info.name = ""; gEl.info.size = 0; gEl.info.type = FLOAT_32;
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
	// for(const auto &it : dataSegment)
	// {
	// 	fprintf(yyout,"\t%s\n", it.c_str());
	// }
	for (auto const& x : dataSegmentSymbols)
	{
		oss << x.first.name <<":\t";
		switch(x.second)
		{
			case INTEGER_VAL:
			{
				oss <<".word\t0\n";
				break;
			}
			case FLOAT_32:
			{
				oss <<".float\t0\n";
				break;
			}
			case CSTR:
			{
				oss <<".ascii\t0\n";
				break;
			}
			default:
			{
				oss <<".word\t0\n";
				break;
			}
		}
		fprintf(yyout, "\t%s", oss.str().c_str());
		oss.str("");
		oss.clear();
	}
	// for(map<var_info,int>::iterator it = dataSegmentSymbols.begin();
	// 	it != dataSegmentSymbols.end(); ++it)
	// {
	// 	auto name = it->first;
	// 	oss << name.name <<":\t";
	// 	switch(it->second)
	// 	{
	// 		case INTEGER_VAL:
	// 		{
	// 			oss <<".word\t0\n";
	// 			break;
	// 		}
	// 		case FLOAT_32:
	// 		{
	// 			oss <<".float\t0\n";
	// 			break;
	// 		}
	// 		case CSTR:
	// 		{
	// 			oss <<".ascii\t0\n";
	// 			break;
	// 		}
	// 		default:
	// 		{
	// 			oss <<".word\t0\n";
	// 			break;
	// 		}
	// 	}
	// 	fprintf(yyout, "\t%s", oss.str().c_str());
	// 	oss.str("");
	// 	oss.clear();
	// }
}

void find_dataseg_item(string name, stack_pair *res)
{
	for(map<var_info,int>::iterator it = dataSegmentSymbols.begin();
		it != dataSegmentSymbols.end(); ++it)
	{
		if(it->first.name == name)
		{
			//best way to copy it?
			res->token = IDENTIFER;
			res->info.name = it->first.name;
			res->info.size = it->first.size;
			res->info.value = it->first.value;
			res->info.type = it->first.type;

			break;
		}
	}
}

void store_global(stack_pair el)
{
	// cout <<"var_name = " << var_name << "\n";
	// cout <<"type = " << type << "\n";
	// cout <<"var_value = " << var_value << "\n";

	string hold = el.info.name + ":\t";

	switch(el.info.type)
	{
		case INTEGER_VAL:
		case INT_32:
		{
			hold += ".word\t";
			break;
		}
		case FLOAT_32:
		case DOUBLE_VAL:
		{
			hold += ".float\t";
			break;
		}
		case CSTR:
		case IDENTIFER:
		{
			hold += ".asciiz\t";
			break;
		}
		default:
		{
			hold += ".word\t";
			break;
		}
	}

	hold += el.info.value;

	//dataSegment.push_back(hold);
	dataSegmentSymbols.insert(pair<var_info, int>(el.info, el.token));

}

void gen_syscall(int type, string id)
{
	ostringstream oss;
	stack_pair op1;
	string rgstr;
	oss << "#" ;
	
	switch(type)
	{
		//SPEAKI SPEAKF SPEAKS SCANI SCANF
		case SPEAKI:
			oss << "SPEAKI(";
			rgstr = "$a";
			op1.token = IDENTIFER;//change to function argument		
		break;
		case SPEAKF:
			oss << "SPEAKF(";
			rgstr = "$f";
			op1.token = IDENTIFER;
		break;
		case SPEAKS:
			oss << "SPEAKS(";
			rgstr = "$a";
			op1.token = CSTR;
		break;
		case SCANI:
			oss << "SCANI(";
			rgstr = "$v";
		break;
		case SCANF:
			oss << "SCANF(";
			rgstr = "$f";
		break;		
	}

	//op1 = gStack.top();
	//gStack.pop();
	//op1.token = type;
	op1.info.name = id;

	oss << op1.info.name << ")\n";
	textSegment.push_back(oss.str());
	//cout << oss.str();
	oss.str("");
	oss.clear();

	switch(type)
	{
		//SPEAKI SPEAKF SPEAKS SCANI SCANF
		case SPEAKI:
			oss << "li $v0, 1\n";
		break;
		case SPEAKF:
			oss << "li $v0, 2\n";
		break;
		case SPEAKS:
			oss << "li $v0, 4\n";
		break;
		case SCANI:
			oss << "li $v0, 5\n";
		break;
		case SCANF:
			oss << "li $v0, 6\n";
		break;		
	
	}

	//make_line_asm(&op1, 0);

	textSegment.push_back(oss.str());
	oss.str("");
	oss.clear();
	if(type == SPEAKI || type == SPEAKF || type == SPEAKS)
	{
		make_line_asm(&op1, rgstr, 0);
		oss << "syscall\n";
		textSegment.push_back(oss.str());
	}
	else
	{
		oss << "syscall\n";
		textSegment.push_back(oss.str());
		make_store_asm(rgstr, 0, id);
	}
	
}

//easily modifiable to not change initializing variable
void make_for_begin_asm(string begin_stmt_name, int iter_increase)
{
	string firstlbl = "LBL" + to_string(etiq_num);
	etiq_num++;
	gEtiqStack.push(firstlbl);

	string lastlbl = "LBL" + to_string(etiq_num);
	etiq_num++;
	gEtiqStack.push(lastlbl);

	textSegment.push_back(firstlbl + ":\n");//last label
	
	make_cond_jmp_asm(last_op, lastlbl, 4, 5);

	stack_pair el;
	find_dataseg_item(begin_stmt_name, &el);
	
	gEl.info.value = to_string(iter_increase); gEl.token = INTEGER_VAL;
	gEl.info.name = ""; gEl.info.size = 0; gEl.info.type = INT_32;

	textSegment.push_back("#it += " + to_string(iter_increase) + "\n");
	make_line_asm(&el, "$t", 4);
	make_line_asm(&gEl, "$t", 5);//substitute magic nr?
	make_op_asm('+', INT_32, 4, 5);
	make_store_asm("$t", 4, el.info.name);
	/*this might be bad, icreasing iterator right after jmp*/
}

void make_for_expr_asm()
{
	string lastlbl = gEtiqStack.top();
	gEtiqStack.pop();

	string firstlbl = gEtiqStack.top();
	gEtiqStack.pop();

	make_uncond_jmp_asm(firstlbl);

	textSegment.push_back(lastlbl + ":\n");//last label
}

void make_uncond_jmp_asm(string label)
{
	ostringstream oss;
	oss << "#jump to " << label << "\n";

	textSegment.push_back(oss.str());
	oss.str("");
	oss.clear();

	oss << "j " << label << "\n\n";
	textSegment.push_back(oss.str());

	//gEtiqStack.push(label);
}

void load_addr_asm(stack_pair *arg, int nr)
{
	ostringstream oss;
	oss << "lw $a" << to_string(nr) << ", "<< arg->info.name << "\n";
	textSegment.push_back(oss.str());
}

void make_cond_jmp_asm(int condition, string label, int rgstr1, int rgstr2)
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

	if(op2.token == IDENTIFER)
	{
		oss << op2.info.name;
	}
	else
	{
		oss << op2.info.value;
	}

	oss << " " << op_cond << " ";

	if(op1.token == IDENTIFER)
	{
		oss << op1.info.name;
	}
	else
	{
		oss << op1.info.value;
	}

	oss << "\n";
	//cout << oss.str();
	textSegment.push_back(oss.str());
	oss.str("");
	oss.clear();

	make_line_asm(&op2, "$t", rgstr1);
	make_line_asm(&op1, "$t", rgstr2);
	oss << op_cond  << " $t" << to_string(rgstr1)
					<< ", $t" << rgstr2 << ", " << label << "\n";
	//gEtiqStack.push(label);
	textSegment.push_back(oss.str());
}

void make_line_asm(stack_pair *arg, string rgstr, int nr)
{
	ostringstream oss;
	switch(arg->token)
	{
		case INTEGER_VAL:
		{
			oss << "li "<< rgstr << to_string(nr) << ", "<< arg->info.value << "\n";
		}
		break;
		case IDENTIFER:
		{
			oss << "lw "<< rgstr << to_string(nr) << ", "<< arg->info.name << "\n";
		}
		break;
		case DOUBLE_VAL:
		{
			oss << "l.s "<< rgstr << to_string(nr) << ", "<< arg->info.value << "\n";
		}
		case CSTR:
		{
			oss << "la "<< rgstr << to_string(nr) << ", "<< arg->info.name << "\n";
		}
		break;
	}
	//cout << oss.str() << endl;
	textSegment.push_back(oss.str());
}

void make_conv_asm(stack_pair *arg, int type)
{

}

void make_op_asm(char op, int type, int nr_to, int nr_sec)
{
	ostringstream oss;
	string rgstr = ((type == INT_32) ? "$t" : "$f"); 
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
	if(type == FLOAT_32)
	{
		oss << ".s";
	}
	// if(left->token == INTEGER_VAL && right->token == INTEGER_VAL)
	// {
	// 	oss << " $t0, $t0, $t1\n";
	// }
	// else if(left->token == IDENTIFER && right->token == INTEGER_VAL ||
	// 		left->token == INTEGER_VAL && right->token == IDENTIFER)
	// {
		oss << " "  << rgstr << to_string(nr_to) << ", "
					<< rgstr << to_string(nr_to) << ", "
					<< rgstr << to_string(nr_sec) << "\n";

		//oss << " $t0, $t0, $t1\n";
	// }//??????????????????????????????????????
	// else
	// {
	// 	//oss << ".s $f0, $f0, $f1\n";
	// }
	//cout << oss.str() << endl;
	textSegment.push_back(oss.str());
}

void make_store_asm(string from, int fromnr, string to)
{
	ostringstream oss;
	// if(arg->token == INTEGER_VAL)
	// {
	// 	oss << "sw $t0, retval_" << var_num << "\n";
	// }
	// else if(arg->token == IDENTIFER)
	// {
		//oss << "sw $t0, " << arg->value << "\n\n";
		oss << "sw " << from << to_string(fromnr) << ", " << to << "\n\n";
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
	// make_line_asm(left, 0);
	// make_line_asm(right, 1);
	// make_op_asm(left, right, op);
	// make_store_asm(left);



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
	oss << "#retval_" << var_num << " = ";
	if(op2.token == IDENTIFER)
	{
		oss << op2.info.name;
	}
	else
	{
		oss << op2.info.value;
	}

	oss << " ";

	if(op1.token == IDENTIFER)
	{
		oss << op1.info.name;
	}
	else
	{
		oss << op1.info.value;
	}

	oss << " " << op << "\n";
	textSegment.push_back(oss.str());
	// cout << "op1 name = "	<< op1.info.name	<< '\n'
	// 	 << "op1 value = "	<< op1.info.value	<< "\n";
	//cout << oss.str() << endl;
	oss.str("");
	oss.clear();

	string rgstr;//op1 i op2

	if(op != '=')
	{
		oss << "retval_" << var_num;
		//gEl.value = oss.str();
		gEl.info.value = "0";
		gEl.info.name = oss.str();
		gEl.info.size = 1;
		gEl.info.type = INT_32;
		gEl.token = IDENTIFER;
		//dataSegmentSymbols.insert(pair<string, int>(oss.str(), INTEGER_VAL));//wynika z op1 i op2
		store_global(gEl);
		gStack.push(gEl);
		var_num++;

		make_line_asm(&op2, "$t", 0);
		make_line_asm(&op1, "$t", 1);
		make_op_asm(op, INT_32, 0, 1);
		//make_store_asm(&gEl);
		make_store_asm("$t", 0, gEl.info.name);
		//make_store_asm("$t", 0, gEl.value);

	}
	else
	{
		make_line_asm(&op2, "$t", 0);
		//make_store_asm(&op1);
		make_store_asm("$t", 0, op1.info.name);
		
		//dataSegmentSymbols.insert(pair<string, int>(op1.value, IDENTIFER));//przeniesc instrukcje do miejsca deklaracji
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

	if(!gStack.empty())
	{
		yyerror("Brak pustego stosu!");
	}
	
	//yyout to FILE*

	// fsthree.close();
	fsrpn.close();
    return 0;
}