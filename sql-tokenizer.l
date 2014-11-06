%{
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <algorithm>
#include "sql_token.h"
using namespace std;


class mysqlFlexLexer:public yyFlexLexer
{
public:
	char quote_char;
	sql_token_id quote_token_id ;
	sql_token_id comment_token_id ;
	map<string,sql_token_id>  keywords;
	mysqlFlexLexer( FLEX_STD istream* arg_yyin = 0, FLEX_STD ostream* arg_yyout = 0 ):yyFlexLexer(arg_yyin,arg_yyout){
		quote_char = 0;
		quote_token_id = TK_UNKNOWN;
		comment_token_id = TK_UNKNOWN;
		for(int i=0; i<sizeof(sql_keywords)/sizeof(int); i++){
			sql_token_id token_id=sql_keywords[i];
			size_t keyword_len=0;
			const char *keyword = sql_token_get_name(token_id, &keyword_len);
			keyword += sizeof("TK_SQL_") - 1;
			keyword_len -= sizeof("TK_SQL_") - 1;
			keywords[string(keyword,keyword_len)]=token_id;
		}
	};

	sql_token_id sql_token_get_id_len(const char *name, size_t name_len) {
		string key(name,name_len);
		for(int i=0; i<key.size(); i++)key[i]=toupper(key[i]);
		//printf("key:%s\n",key.c_str());
		if(keywords.find(key)!=keywords.end()){
			return keywords[key];
		}
		return TK_LITERAL;
	}


	virtual int yylex(){}
	void sql_token_append_len(vector<sql_token> & tokens,sql_token_id token_id , const char *text, size_t text_len){
		tokens.push_back(sql_token(token_id,string(text,text_len)));
	}
	void sql_token_append_last_token_len(vector<sql_token> & tokens,sql_token_id token_id , const char *text, size_t text_len){
		if(tokens.size()>0){
			tokens[tokens.size()-1].text+=string(text,text_len);
		}
	}
	int yylex(sql_token_id & token_id,vector<sql_token> & tokens);
};

int sql_lex(string s,vector<sql_token> &tokens){
	stringstream m_stream(s);
	mysqlFlexLexer  m_flex(&m_stream);
	sql_token_id  token_id;
	while(m_flex.yylex(token_id,tokens) != 0)
		;
	return tokens.size();
}


#define YY_DECL int mysqlFlexLexer::yylex(sql_token_id & comment_token_id,vector<sql_token> & tokens)
int yyFlexLexer::yylex(){
}
#define GE_STR_LITERAL_WITH_LEN(txt) txt,strlen(txt)
%}

%x COMMENT LINECOMMENT QUOTED
%%
	/** comments */
"--"\r?\n       comment_token_id = TK_COMMENT;       sql_token_append_len(tokens, comment_token_id, GE_STR_LITERAL_WITH_LEN(""));
"/*"		comment_token_id = TK_COMMENT;       sql_token_append_len(tokens, comment_token_id, GE_STR_LITERAL_WITH_LEN("")); BEGIN(COMMENT);
"/*!"		comment_token_id = TK_COMMENT_MYSQL; sql_token_append_len(tokens, comment_token_id, GE_STR_LITERAL_WITH_LEN("")); BEGIN(COMMENT);
"--"[[:blank:]]		comment_token_id = TK_COMMENT; sql_token_append_len(tokens, comment_token_id, GE_STR_LITERAL_WITH_LEN("")); BEGIN(LINECOMMENT);
<COMMENT>[^*]*	sql_token_append_last_token_len(tokens, comment_token_id, yytext, yyleng);
<COMMENT>"*"+[^*/]*	sql_token_append_last_token_len(tokens, comment_token_id, yytext, yyleng);
<COMMENT>"*"+"/"	BEGIN(INITIAL);
<COMMENT><<EOF>>	BEGIN(INITIAL);
<LINECOMMENT>[^\n]* sql_token_append_last_token_len(tokens, comment_token_id, yytext, yyleng);
<LINECOMMENT>\r?\n	BEGIN(INITIAL);
<LINECOMMENT><<EOF>>	BEGIN(INITIAL);

	/** start of a quote string */
["'`]		{ BEGIN(QUOTED);  
		quote_char = *yytext; 
		switch (quote_char) { 
		case '\'': quote_token_id = TK_STRING; break; 
		case '"': quote_token_id = TK_STRING; break; 
		case '`': quote_token_id = TK_LITERAL; break; 
		} 
		sql_token_append_len(tokens, quote_token_id, GE_STR_LITERAL_WITH_LEN("")); }
<QUOTED>[^"'`\\]*	sql_token_append_last_token_len(tokens, quote_token_id, yytext, yyleng); /** all non quote or esc chars are passed through */
<QUOTED>"\\".		sql_token_append_last_token_len(tokens, quote_token_id, yytext, yyleng); /** add escaping */
<QUOTED>["'`]{2}	{ if (yytext[0] == yytext[1] && yytext[1] == quote_char) { 
				sql_token_append_last_token_len(tokens, quote_token_id, yytext + 1, yyleng - 1);  /** doubling quotes */
			} else {
				/** pick the first char and put the second back to parsing */
				yyless(1);
				sql_token_append_last_token_len(tokens, quote_token_id, yytext, yyleng);
			}
			}
<QUOTED>["'`]	if (*yytext == quote_char) { BEGIN(INITIAL); } else { sql_token_append_last_token_len(tokens, quote_token_id, yytext, yyleng); }
<QUOTED><<EOF>>	BEGIN(INITIAL);

	/** strings, quoting, literals */
[[:space:]]+	/** ignore WS */

	/* unquoted literals (and function names) are
	 * 
	 *   all alpha-nums that are not digits-only and NOT floats
	 *
	 * Floats are
	 *   1.1
	 *   1e+1
	 *   1.1e+1
	 *   .1e+1
	 * unquoted literals:
	 *   e1
	 *   1e
	 * complex cases
	 *   1e + 1 is a literal ("1e"), a plus ("+") and integer ("1")
	 *   1e+1e  is a float ("1e+1") and a literal ("e")
	 *   compare this to 1.1e which is INVALID (a broken scientific notation)
	 */
([[:digit:]]*".")?[[:digit:]]+[eE][-+]?[[:digit:]]+	sql_token_append_len(tokens, TK_FLOAT, yytext, yyleng);
	/* literals
	 * - be greedy and capture specifiers made up of up to 3 literals: lit.lit.lit
	 * - if it has a dot, split it into 3 tokens: lit dot lit
	 *
	 * when it comes to dots in specifiers spaces matter:
	 *   e1 . 1e + 1
	 *   e1.1e + 1
	 *   e1.1e+1 are all a literal ("e1"), a dot, a literal ("1e"), a plus and a integer ("1")
	 * but 
	 *   e1. 1e+1 is invalid as it is a literal ("e1"), a dot and a float ("1e+1")
	 */
[[:digit:]]*[[:alpha:]_@][[:alnum:]_@]*("."[[:digit:]]*[[:alpha:]_@][[:alnum:]_@]*){0,2}	{
		char *cur, *tk_start = yytext;
		size_t tk_len;

		for (cur = yytext; cur < yytext + yyleng; cur++) {
			if (*cur == '.') {
				tk_len = cur - tk_start;

				sql_token_append_len(tokens, sql_token_get_id_len(tk_start, tk_len), tk_start, tk_len);
				sql_token_append_len(tokens, TK_DOT, GE_STR_LITERAL_WITH_LEN("."));
				tk_start = cur + 1;
			}
		}
		/* copy the rest */
		tk_len = yytext + yyleng - tk_start;
		sql_token_append_len(tokens, sql_token_get_id_len(tk_start, tk_len), tk_start, tk_len);
	}
	/* literals followed by a ( are function names */
[[:digit:]]*[[:alpha:]_@][[:alnum:]_@]*("."[[:digit:]]*[[:alpha:]_@][[:alnum:]_@]*){0,2}\(	 {
		char *cur, *tk_start = yytext;
		size_t tk_len;

		yyless(yyleng - 1); /* on step back to track the parantheses correctly */

		/* split the matched string at the dots */
		for (cur = yytext; cur < yytext + yyleng; cur++) {
			if (*cur == '.') {
				tk_len = cur - tk_start;

				sql_token_append_len(tokens, sql_token_get_id_len(tk_start, tk_len), tk_start, tk_len);
				sql_token_append_len(tokens, TK_DOT, GE_STR_LITERAL_WITH_LEN("."));
				tk_start = cur + 1;
			}
		}
		tk_len = yytext + yyleng - tk_start;
		sql_token_append_len(tokens, TK_FUNCTION, tk_start, tk_len);
	}

[[:digit:]]+	sql_token_append_len(tokens, TK_INTEGER, yytext, yyleng);
[[:digit:]]*"."[[:digit:]]+	sql_token_append_len(tokens, TK_FLOAT, yytext, yyleng);
","		sql_token_append_len(tokens, TK_COMMA, yytext, yyleng);
"."		sql_token_append_len(tokens, TK_DOT, yytext, yyleng);

"<"		sql_token_append_len(tokens, TK_LT, yytext, yyleng);
">"		sql_token_append_len(tokens, TK_GT, yytext, yyleng);
"<="		sql_token_append_len(tokens, TK_LE, yytext, yyleng);
">="		sql_token_append_len(tokens, TK_GE, yytext, yyleng);
"="		sql_token_append_len(tokens, TK_EQ, yytext, yyleng);
"<>"		sql_token_append_len(tokens, TK_NE, yytext, yyleng);
"!="		sql_token_append_len(tokens, TK_NE, yytext, yyleng);

"("		sql_token_append_len(tokens, TK_OBRACE, yytext, yyleng);
")"		sql_token_append_len(tokens, TK_CBRACE, yytext, yyleng);
";"		sql_token_append_len(tokens, TK_SEMICOLON, yytext, yyleng);
":="		sql_token_append_len(tokens, TK_ASSIGN, yytext, yyleng);

"*"		sql_token_append_len(tokens, TK_STAR, yytext, yyleng);
"+"		sql_token_append_len(tokens, TK_PLUS, yytext, yyleng);
"/"		sql_token_append_len(tokens, TK_DIV, yytext, yyleng);
"-"		sql_token_append_len(tokens, TK_MINUS, yytext, yyleng);

"&"		sql_token_append_len(tokens, TK_BITWISE_AND, yytext, yyleng);
"&&"		sql_token_append_len(tokens, TK_LOGICAL_AND, yytext, yyleng);
"|"		sql_token_append_len(tokens, TK_BITWISE_OR, yytext, yyleng);
"||"		sql_token_append_len(tokens, TK_LOGICAL_OR, yytext, yyleng);

"^"		sql_token_append_len(tokens, TK_BITWISE_XOR, yytext, yyleng);

	/** the default rule */
.		sql_token_append_len(tokens, TK_UNKNOWN, yytext, yyleng);

%%
int yyFlexLexer::yywrap()
{
}
//Version 2.5               December 1994                        44
#if 0
int main( int /* argc */, char** /* argv */ )
{
	stringstream s("SElect * FROM DB.TB\n");
	sql_token_id  token_id;
	vector<sql_token>  tokens;
	mysqlFlexLexer * lexer = new mysqlFlexLexer(&s);
	while(lexer->yylex(token_id,tokens) != 0)
		;
	for(int i=0; i<tokens.size(); i++){
		sql_token &tk=tokens[i];
		printf("%d %s\n",tk.token_id,tk.text.c_str());
	}
	return 0;
}
#endif
