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

enum register_num
{
	$t0,$t1,//general purpose
	$t2,$t3,
	$t4,$t5,
	$t6,$t7,

	$a0,$a1,
	$a2,$a3,

	$v0,$v1,
	
	$f0,$f1,
	$f2,$f3,
	$f4,$f5,
	$f6,$f7,
	$f12,
	INVALID_REGISTER
};

static map<register_num, string> register_names
{
	{$t0, "$t0"},{$t1, "$t1"},
	{$t2, "$t2"},{$t3, "$t3"},
	{$t4, "$t4"},{$t5, "$t5"},
	{$t6, "$t6"},{$t7, "$t7"},

	{$a0, "$a0"},{$a1, "$a1"},
	{$a3, "$a3"},{$a3, "$a3"},

	{$v0, "$v0"},{$v1, "$v1"},//return values from functions
	
	{$f0, "$f0"},{$f1, "$f1"},
	{$f2, "$f2"},{$f3, "$f3"},
	{$f4, "$f4"},{$f5, "$f5"},//temporary float register
	{$f6, "$f6"},{$f7, "$f7"},
	{$f12, "$f12"}
};

struct arr_info
{
	vector<int> sizes;
	vector<int> dims;
};

vector<int> gArrDims;
vector<int> gArrSizes;

struct var_info
{
	int type;
	string value;
	string name;
	arr_info size;
	register_num register_valE;
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
vector<stack_pair> gArrAccess;

map<var_info, int> dataSegmentSymbols;

vector<string> functionSegment;
vector<string> textSegment;
vector<string> dataSegment;
vector<string> *writeSegment = &textSegment;

static int var_num = 0;
static int float_var_num = 0;
static int for_num = 0;
static int etiq_num = 0;
static int float_num = 0;
static int last_op = 0;
static int else_op = 0;

void remove_pair(char op);
void make_line_asm(stack_pair *, register_num);
void load_addr_asm(stack_pair *, register_num);
register_num make_conv_asm(stack_pair *, register_num);
void make_op_asm(char, int, register_num, register_num, register_num);
void make_op_asm(char, int, register_num, register_num, int);
void make_store_asm(register_num, string, int);

void write_textseg();
void write_dataseg();

void store_global(stack_pair);
void find_dataseg_item(string, stack_pair *);

void make_cond_jmp_asm(int, string, register_num, register_num);
void make_uncond_jmp_asm(string);
void gen_syscall(int, string);

void make_for_begin_asm(string, int);
void make_for_expr_asm();

void make_arr_access_asm(string);
void write_to_index_asm();

string conv_register_to_string(register_num);
register_num assign_free_register(int);
void free_register(stack_pair);

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
%token INT_32 FLOAT_32 CSTR ARR ADDR FUNCTION
%token SPEAKI SPEAKF SPEAKS SCANI SCANF
%token NFUNC CFUNC
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
	| arr_decl ';'
	| function_expr
	| function_call ';'
	;
function_call
	: CFUNC IDENTIFER
		{
			writeSegment->push_back("jal " + string($2) + "\n");
		}
	;
function_expr
	: function_begin '{' multistmt '}'
		{
			writeSegment->push_back("jr $ra\n");
			writeSegment->push_back("#end of function");
			writeSegment = &textSegment;
		}
	| function_begin '{' '}'
		{
			writeSegment->push_back("jr $ra\n");
			writeSegment->push_back("#end of function");
			writeSegment = &textSegment;
		}
	;
function_begin
	: NFUNC IDENTIFER '('')'
		{
			writeSegment = &functionSegment;
			writeSegment->push_back("#function " + string($2) + "\n");
		}
	;
type
	: INT_32 IDENTIFER
		{
			gEl.info.name = $2; gEl.info.value = "0";
			
			gEl.info.type = INT_32;
			gEl.token = IDENTIFER;
			store_global(gEl);
		}
	| FLOAT_32 IDENTIFER //'=' DOUBLE_VAL
		{	//tu cos zrobic
			gEl.info.name = $2; gEl.info.value = "0.0";
			gEl.info.type = FLOAT_32;
			gEl.token = IDENTIFER;
			store_global(gEl);
		}
	| CSTR IDENTIFER '=' STR_LITERAL
		{
			gEl.info.name = $2; gEl.info.value = $4;
			gEl.info.type = CSTR;
			gEl.token = IDENTIFER;

			store_global(gEl);
		}
	;
assign
	: IDENTIFER '=' expr
		{
			fprintf(dropfile, "%s = ", $1);
			//gEl.info.name = $1; gEl.token = IDENTIFER;
			find_dataseg_item($1, &gEl);
			gStack.push(gEl);
			remove_pair('=');
		}
	| IDENTIFER '=' arr_access
		{
			find_dataseg_item($1, &gEl);

			stack_pair arr;
			arr.info.name = "($t6)"; arr.token = IDENTIFER;//ptr_dereference
			if(gEl.info.type == INT_32)
			{
				arr.info.type = INT_32;
			}
			else
				arr.info.type = FLOAT_32;

			gStack.push(arr);
			
			gStack.push(gEl);

			remove_pair('=');
			gArrAccess.clear();
		}
	| arr_access '=' expr
		{
			stack_pair arr;

			gEl = gStack.top();
			gStack.pop();

			arr = gStack.top();
			gStack.pop();
			
			if(gEl.info.type == INT_32)
			{
				make_line_asm(&gEl, (register_num)0);
				make_store_asm((register_num)0, "($t6)", INT_32);//array ought to be in t6
			}
			else
			{
				make_line_asm(&gEl, (register_num)14);
				make_store_asm((register_num)14, "($t6)", FLOAT_32);//array ought to be in t6				
			}

			gArrAccess.clear();
		}

arr_access
	: IDENTIFER dim_access
		{
			stack_pair arr;
			find_dataseg_item($1, &arr);
			gStack.push(arr);
			
			writeSegment->push_back("#" + arr.info.name + " move to address\n");

			make_line_asm(&arr, (register_num)6);
			writeSegment->push_back("li $t3, 0\n");
			for(int i = 0; i < gArrAccess.size(); i++)
			{
				make_line_asm(&gArrAccess[i], (register_num)5);
				make_op_asm('*', INT_32, (register_num)7, (register_num)5, arr.info.size.sizes[i]);
				make_op_asm('+', INT_32, (register_num)3, (register_num)3, (register_num)7);

				writeSegment->push_back("\n");
			}
			make_op_asm('*', INT_32, (register_num)7, (register_num)3, 4);
			writeSegment->push_back("#Move addr by offset\n");			
			make_op_asm('+', INT_32, (register_num)6, (register_num)6, (register_num)7);
		}
	;
arr_decl
	: arr_start dim_decl
		{
			//cout << gEl.info.name << "\n";
			int dims = 1;
			gArrSizes.insert(gArrSizes.begin(), dims);
			for(int i = gArrDims.size() - 1; i >= 1; i--)
			{
				dims *= gArrDims[i];
				gArrSizes.insert(gArrSizes.begin(), dims);
				//cout <<"Inserting" << gArrDims[i] << "\t";
			}

			if(gArrSizes.size() != gArrDims.size())
				yyerror("WTF");
			
			dims = 0;
			for(int i = 0; i < gArrSizes.size(); i++)
			{
				dims += gArrSizes[i] * gArrDims[i];
			}

			gEl.info.size.dims = gArrDims;
			gEl.info.size.sizes = gArrSizes;

			gEl.info.value = "0 : " + to_string(dims);

			gArrDims.clear();
			gArrSizes.clear();

			store_global(gEl);
		}
	;
arr_start
	: INT_32 IDENTIFER
		{
			gEl.info.name = $2; gEl.info.type = INT_32;
			gEl.token = ARR;
		}
	| FLOAT_32 IDENTIFER
		{
			gEl.info.name = $2; gEl.info.type = FLOAT_32;
			gEl.token = ARR;
		}
	;
dim_decl
	: '[' size_const ']'
		{

		}
	;
size_const
	: size_const ',' size_value
	| size_value
	;
size_value
	: INTEGER_VAL	{gArrDims.push_back($1);}
	;
dim_access
	: '[' expr_const ']'
	;
expr_const
	: expr_const ',' expr_value
	| expr_value
	;
expr_value
	: expr
		{
			gEl = gStack.top();
			gStack.pop();
			gArrAccess.push_back(gEl);
		}
	;
if_expr
	: if_begin '{' multistmt '}'
		{
			string res = gEtiqStack.top() + ":\n";
			gEtiqStack.pop();
			writeSegment->push_back(res);//last label
		}
	| if_begin '{' multistmt '}' else_expr
		{
			string res = gEtiqStack.top() + ":\n";
			gEtiqStack.pop();
			writeSegment->push_back(res);//last label

			
		}
	;
else_expr
	: else_begin '{' multistmt '}'
		{										
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

			
			writeSegment->push_back(res);//last label
		}
	;
if_begin
	: IF '(' cond_expr ')'
		{
			string lbl = "LBL" + to_string(etiq_num);
			make_cond_jmp_asm(last_op, lbl, (register_num)0, (register_num)1);
			gEtiqStack.push(lbl);
			etiq_num++;
		}
	;
for_begin
	: FOR '(' IDENTIFER ';' cond_expr ';' INTEGER_VAL ')'
		{
			make_for_begin_asm($3, $7);
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
	:IDENTIFER
		{
			fprintf(dropfile, "%s ", $1);
			find_dataseg_item($1, &gEl);
			gStack.push(gEl);
		}
	|INTEGER_VAL
		{
			fprintf(dropfile, "%d ", $1);
			gEl.info.value = to_string($1); gEl.token = INTEGER_VAL;
			gEl.info.name = ""; /*gEl.info.size = NULL*/; gEl.info.type = INT_32;
			gStack.push(gEl);
		}
    |DOUBLE_VAL
		{
			fprintf(dropfile, "%f ", $1);
			//cout << $1;
			gEl.info.value = to_string($1); gEl.token = IDENTIFER;
			gEl.info.name = "float_" + to_string(float_num);
			/*gEl.info.size = NULL*/; gEl.info.type = DOUBLE_VAL;
			store_global(gEl);
			gStack.push(gEl);
			float_num++;
		}
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
	fprintf(yyout,"\tli $v0, 10\n");
	fprintf(yyout,"\tsyscall\n");
	

	for(const auto &it : functionSegment)
	{
		fprintf(yyout,"\t%s", it.c_str());
	}
}

void write_dataseg()
{
	ostringstream oss;
	fprintf(yyout, ".data\n");
	string hold;
	for (auto const& x : dataSegmentSymbols)
	{
		hold = x.first.name + ":\t";

		switch(x.first.type)
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

		hold += x.first.value + '\n';

		

		fprintf(yyout, "\t%s", hold.c_str());
		
	}
}

void find_dataseg_item(string name, stack_pair *res)
{
	for(map<var_info,int>::iterator it = dataSegmentSymbols.begin();
		it != dataSegmentSymbols.end(); ++it)
	{
		if(it->first.name == name)
		{
			//best way to copy it?
			res->token = it->second;
			res->info.name = it->first.name;
			
			res->info.size = it->first.size;
			res->info.value = it->first.value;
			res->info.type = it->first.type;

			break;
		}
	}
}

string conv_register_to_string(register_num rgstr)
{
	return register_names[rgstr];
}

void store_global(stack_pair el)
{
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

	dataSegmentSymbols.insert(pair<var_info, int>(el.info, el.token));
}

void gen_syscall(int type, string id)
{
	ostringstream oss;
	stack_pair op1;
	register_num rgstr;
	oss << "#" ;
	find_dataseg_item(id, &op1);

	switch(type)
	{
		//SPEAKI SPEAKF SPEAKS SCANI SCANF
		case SPEAKI:
			oss << "SPEAKI(";
			rgstr = $a0;
			op1.token = IDENTIFER;//change to function argument		
		break;
		case SPEAKF:
			oss << "SPEAKF(";
			rgstr = $f12;
			op1.token = IDENTIFER;
		break;
		case SPEAKS:
			oss << "SPEAKS(";
			rgstr = $a0;
			op1.token = CSTR;
		break;
		case SCANI:
			oss << "SCANI(";
			rgstr = $v0;
		break;
		case SCANF:
			oss << "SCANF(";
			rgstr = $f0;
		break;		
	}

	//op1.info.name = id;

	oss << op1.info.name << ")\n";
	writeSegment->push_back(oss.str());
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

	writeSegment->push_back(oss.str());
	oss.str("");
	oss.clear();
	if(type == SPEAKI || type == SPEAKF || type == SPEAKS)
	{
		make_line_asm(&op1, rgstr);
		oss << "syscall\n";
		writeSegment->push_back(oss.str());
	}
	else
	{
		oss << "syscall\n";
		writeSegment->push_back(oss.str());
		make_store_asm(rgstr, id, op1.info.type);
	}
	
}

//easily modifiable to not change initializing variable
void make_for_begin_asm(string begin_stmt_name, int iter_increase)
{
	//prepare labels for loop
	string firstlbl = "LBL" + to_string(etiq_num);
	etiq_num++;
	gEtiqStack.push(firstlbl);

	string lastlbl = "LBL" + to_string(etiq_num);
	etiq_num++;
	gEtiqStack.push(lastlbl);

	/*
	//copy content of init value to iterX
	stack_pair el;
	find_dataseg_item(begin_stmt_name, &el);
	el.info.name = "iterator" + to_string(for_num);//not enough
	for_num++;
	store_global(el);
	//cond_expr put those two on stack, and we have to swap begin_stmt_name
	
	stack_pair left_op = gStack.top();
	gStack.pop();

	stack_pair right_op = gStack.top();
	gStack.pop();//TODO
	*/


	writeSegment->push_back(firstlbl + ":\n");//last label

	//check if subsequent iterator values satisfy condition
	make_cond_jmp_asm(last_op, lastlbl, $t4, $t5);

	stack_pair el;
	find_dataseg_item(begin_stmt_name, &el);
	
	gEl.info.value = to_string(iter_increase); gEl.token = INTEGER_VAL;
	gEl.info.name = ""; /*gEl.info.size = NULL*/; gEl.info.type = INT_32;

	writeSegment->push_back("#it += " + to_string(iter_increase) + "\n");

	//increase iterator value
	make_line_asm(&el, $t4);
	make_line_asm(&gEl, $t5);//substitute magic nr?
	make_op_asm('+', INT_32, $t4, $t4, $t5);
	make_store_asm($t4, el.info.name, INT_32);
	/*this might be bad, icreasing iterator right after jmp*/
}

void make_for_expr_asm()
{
	string lastlbl = gEtiqStack.top();
	gEtiqStack.pop();

	string firstlbl = gEtiqStack.top();
	gEtiqStack.pop();

	make_uncond_jmp_asm(firstlbl);

	writeSegment->push_back(lastlbl + ":\n");//last label
}

void make_uncond_jmp_asm(string label)
{
	ostringstream oss;
	oss << "#jump to " << label << "\n";

	writeSegment->push_back(oss.str());
	oss.str("");
	oss.clear();

	oss << "j " << label << "\n\n";
	writeSegment->push_back(oss.str());

	//gEtiqStack.push(label);
}

void write_to_index_asm()
{
	gEl = gStack.top();
	gStack.pop();
	make_line_asm(&gEl, $t0);
	make_store_asm($t0, "($t6)", INT_32);//array ought to be in t6
}

void make_arr_access_asm(string arr_name, vector<int> dims)
{
	gEl = gStack.top();//index if expr type ~= int...
	gStack.pop();

	stack_pair arr;
	find_dataseg_item(arr_name, &arr);

	writeSegment->push_back("#" + arr.info.name +
							'[' + gEl.info.value + "]\n");
	make_line_asm(&gEl, $t7);//index
	make_line_asm(&arr, $t6);//array

	writeSegment->push_back("#generate addr(32bits) offset\n");
	make_op_asm('*', INT_32, $t7, $t7, 4);

	//move address relative to array

	writeSegment->push_back("#Move addr by offset\n");			
	make_op_asm('+', INT_32, $t6, $t6, $t7);

	//gEl.info.name = "$t6"; gEl.token = INT_32;//gotta have float arrays?
}

void load_addr_asm(stack_pair *arg, register_num rgstr)
{
	ostringstream oss;
	oss << "lw " << conv_register_to_string(rgstr) << ", "<< arg->info.name << "\n";
	writeSegment->push_back(oss.str());
}

void make_cond_jmp_asm(int condition, string label, register_num rgstr1, register_num rgstr2)
{
	ostringstream oss;
	stack_pair op1;
	stack_pair op2;

	string op_cond;

	oss << "#" << label << " ";
	//beq, bne, blt, ble, bgt, bge
	switch(condition)
	{
		case EQ://== -> !=
			oss << "==" << " ";
			op_cond = "bne";
		break;

		case NEQ://!= -> ==
			oss << "!=" << " ";
			op_cond = "beq";
		break;

		case '<'://< -> >=
			oss << "<" << " ";
			op_cond = "bge";
		break;

		case GEQ://>= -> <
			oss << ">=" << " ";
			op_cond = "blt";
		break;

		case '>'://> -> <=
			oss << ">" << " ";
			op_cond = "ble";
		break;

		case LEQ://<= -> >
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
	writeSegment->push_back(oss.str());
	oss.str("");
	oss.clear();

	make_line_asm(&op2, rgstr1);
	make_line_asm(&op1, rgstr2);
	oss << op_cond << " " << conv_register_to_string(rgstr1)
					<< ", " << conv_register_to_string(rgstr2)
					<< ", " << label << "\n";
	//gEtiqStack.push(label);
	writeSegment->push_back(oss.str());
}

void make_line_asm(stack_pair *arg, register_num rgstr)
{
	ostringstream oss;
	switch(arg->token)
	{
		case INT_32:
		case INTEGER_VAL:
		{
			oss << "li "<< conv_register_to_string(rgstr) << ", "<< arg->info.value << "\n";
		}
		break;
		case IDENTIFER:
		case ADDR:
		{
			// if(arg->info.type == INTEGER_VAL || arg->info.type == INT_32)
			//cout << "DOUBLE_VAL = " << DOUBLE_VAL << " FLOAT = " << FLOAT_32 << "ARG_TYPE = " << arg->info.type << "\n";
			// switch(arg->info.type)
			// {
			// 	DOUBLE_VAL:
			// 	FLOAT_32:
			// 	cout << "co jest kurwa";
			// 	oss << "l.s " << conv_register_to_string(rgstr) << ", "<< arg->info.name << "\n";
			// 	break;
			// 	default:
			// 	cout << "co jest chuja";
			// 	oss << "lw "<< conv_register_to_string(rgstr) << ", " << arg->info.name << "\n";
			// 	break;
			// }
			if(arg->info.type == DOUBLE_VAL)
			{
				oss << "l.s " << conv_register_to_string(rgstr) << ", "<< arg->info.name << "\n";
			}
			else if(arg->info.type == FLOAT_32)
			{
				oss << "l.s " << conv_register_to_string(rgstr) << ", "<< arg->info.name << "\n";
			}
			else
			{
				oss << "lw "<< conv_register_to_string(rgstr) << ", " << arg->info.name << "\n";

			}
			// if(arg->info.type != DOUBLE_VAL || arg->info.type != FLOAT_32)
			// 	oss << "lw "<< conv_register_to_string(rgstr) << ", " << arg->info.name << "\n";
			// else
			// 	oss << "l.s " << conv_register_to_string(rgstr) << ", "<< arg->info.name << "\n";
		}
		break;
		case FLOAT_32:
		case DOUBLE_VAL:
		{
			oss << "l.s "<< conv_register_to_string(rgstr) << ", "<< arg->info.value << "\n";
		}
		break;
		case ARR:
		case CSTR:
		{
			oss << "la "<< conv_register_to_string(rgstr) << ", "<< arg->info.name << "\n";
		}
		break;
	}
	//cout << oss.str() << endl;
	writeSegment->push_back(oss.str());
}

register_num make_conv_asm(stack_pair *arg, register_num from)
{
	register_num ret_rgstr = (register_num)((int)from + 14);
	// if(arg->info.type == FLOAT_32 || arg->info.type == DOUBLE_VAL)
	// 	return ret_rgstr;
	
	ostringstream oss;
	oss << "mtc1 " << conv_register_to_string(from) << ", " << conv_register_to_string(ret_rgstr) << "\n";
	oss << "cvt.s.w " << conv_register_to_string(ret_rgstr) << ", " <<
						conv_register_to_string(ret_rgstr) << "\n";

	//if(arg->token != IDENTIFER)
	//arg->info.type = FLOAT_32;

	writeSegment->push_back(oss.str());

	return ret_rgstr;
}

void make_op_asm(char op, int type, register_num rgstr_save,
				register_num op1, int op2)
{
	ostringstream oss;
	//string rgstr = ((type == INT_32) ? "$t" : "$f");
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

		oss << " "  << conv_register_to_string(rgstr_save) << ", "
					<< conv_register_to_string(op1) << ", "
					<< to_string(op2) << "\n";


	writeSegment->push_back(oss.str());
}

void make_op_asm(char op, int type, register_num rgstr_save,
				register_num op1, register_num op2)
{
	//consider using stack element
	ostringstream oss;
	//string rgstr = ((type == INT_32) ? "$t" : "$f");
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

		oss << " "  << conv_register_to_string(rgstr_save) << ", "
					<< conv_register_to_string(op1) << ", "
					<< conv_register_to_string(op2) << "\n";


	writeSegment->push_back(oss.str());
}

void make_store_asm(register_num from, string to, int type)
{
	ostringstream oss;
	if(type == INT_32 || type == INTEGER_VAL)
		oss << "sw " << conv_register_to_string(from) << ", " << to << "\n\n";
	else
		oss << "s.s " << conv_register_to_string(from) << ", " << to << "\n\n";

	writeSegment->push_back(oss.str());

}

void remove_pair(char op)
{
	stack_pair op1;
	stack_pair op2;

	register_num rgstr0;
	register_num rgstr1;

	op1 = gStack.top();
	gStack.pop();

	op2 = gStack.top();
	gStack.pop();

	ostringstream oss;

	string tmpval;

	// cout << "FLOAT_32 = " << FLOAT_32 << "\n";
	// cout << "INT_32 = " << INT_32 << "\n";

	// cout << op1.info.name << " " << op1.info.type << "\n";
	// cout << op2.info.name << " " << op2.info.type << "\n";

	int operation_type = INT_32;

	//tmpval = "i32val_" + to_string(var_num++);

	if(op1.info.type == DOUBLE_VAL || op2.info.type == DOUBLE_VAL ||
		op1.info.type == FLOAT_32 || op2.info.type == FLOAT_32)
	{
		tmpval = "f32val_" + to_string(float_var_num);
	}
	else
	{
		tmpval = "i32val_" + to_string(var_num);
	}
	

	//if op1.type == LC ->li
	//   if op1.type == LF -> FLOAT_TMP ->l.s
	//if op1.type == ID -> INT ->lw t
	//   if op1.type == ID -> FLOAT ->l.s f

	//generate_mips_asm(&op2, &op1, op);
	//oss << "#retval_" << var_num << " = ";

	

	if(op != '=')
	{
		if(op1.info.type == DOUBLE_VAL || op2.info.type == DOUBLE_VAL ||
		op1.info.type == FLOAT_32 || op2.info.type == FLOAT_32)
		{
			float_var_num++;
		}
		else
		{
			var_num++;
		}
		if(op1.info.type == DOUBLE_VAL || op1.info.type == FLOAT_32)
		{
			rgstr1 = $f1;
		}
		else
		{
			rgstr1 = $t1;
		}

		if(op2.info.type == DOUBLE_VAL || op2.info.type == FLOAT_32)
		{
			rgstr0 = $f0;
		}
		else
		{
			rgstr0 = $t0;
		}

		oss << "#" << tmpval << " = ";
		if(op2.token == IDENTIFER)
		{
			oss << op2.info.name;
		}
		else
		{
			oss << op2.info.value;
		}

		oss << " " << op << " ";

		if(op1.token == IDENTIFER)
		{
			oss << op1.info.name;
		}
		else
		{
			oss << op1.info.value;
		}
		oss << "\n";

		writeSegment->push_back(oss.str());
		oss.str("");
		oss.clear();

		if(op1.info.type == DOUBLE_VAL || op2.info.type == DOUBLE_VAL ||
			op1.info.type == FLOAT_32 || op2.info.type == FLOAT_32)
		{
			operation_type = FLOAT_32;
		}
		//var_num++;

		make_line_asm(&op2, rgstr0);
		if((op2.info.type == INT_32 || op2.info.type == INTEGER_VAL)
			&& (op1.info.type == FLOAT_32 || op1.info.type == DOUBLE_VAL ))
		{
			operation_type = FLOAT_32;
			rgstr0 = make_conv_asm(&op2, rgstr0);
			//cout << "rgstr = " << conv_register_to_string(rgstr0) << "\n";
		}


		make_line_asm(&op1, rgstr1);
		if((op1.info.type == INT_32 || op1.info.type == INTEGER_VAL)
			&& (op2.info.type == FLOAT_32 || op2.info.type == DOUBLE_VAL ))
		{
			operation_type = FLOAT_32;
			rgstr1 = make_conv_asm(&op1, rgstr1);
			//cout << "rgstr = " << conv_register_to_string(rgstr1) << "\n";
		}

		// if(op1.info.type == DOUBLE_VAL || op2.info.type == DOUBLE_VAL ||
		// 	op1.info.type == FLOAT_32 || op2.info.type == FLOAT_32)
		// {
		// 	operation_type = FLOAT_32;
		// 	make_conv_asm(&op1, rgstr1);
		// }
		make_op_asm(op, operation_type, rgstr0, rgstr0, rgstr1);

		oss << tmpval;
		gEl.info.value = "0";
		gEl.info.name = oss.str();
		/*gEl.info.size = NULL;*/
		gEl.info.type = operation_type;
		gEl.token = IDENTIFER;
		store_global(gEl);
		gStack.push(gEl);

		make_store_asm(rgstr0, gEl.info.name, operation_type);

	}
	else
	{
		if(op2.info.type == DOUBLE_VAL ||
		op2.info.type == FLOAT_32)
		{
			operation_type = FLOAT_32;
			rgstr0 = $f0;
		}
		else
		{
			rgstr0 = $t0;
		}

		oss << "#";
		if(op2.token == IDENTIFER)
		{
			oss << op2.info.name;
		}
		else
		{
			oss << op2.info.value;
		}

		oss << " " << op << " ";

		if(op1.token == IDENTIFER)
		{
			oss << op1.info.name;
		}
		else
		{
			oss << op1.info.value;
		}


		if(op1.info.type == FLOAT_32)
		{

			if(op2.info.type == FLOAT_32)
			{

			}
			else if(op2.info.type == DOUBLE_VAL)
			{

			}
			else
				yyerror("Invalid conversion!");			
		}
		if(op1.info.type == INT_32 && (op2.info.type != INT_32))
		{
			yyerror("Invalid conversion!");			
		}

		oss << "\n";
		
		writeSegment->push_back(oss.str());
		oss.str("");
		oss.clear();

		make_line_asm(&op2, rgstr0);
		make_store_asm(rgstr0, op1.info.name, operation_type);
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