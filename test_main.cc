/*
 * =====================================================================================
 *
 *       Filename:  test_main.cc
 *
 *    Description:  
 *
 *        Version:  1.0
 *        Created:  11/06/2014 11:55:10 PM
 *       Revision:  none
 *       Compiler:  gcc
 *
 *         Author:  YOUR NAME (), 
 *        Company:  
 *
 * =====================================================================================
 */
#include "sql_token.h"
void print_sql(string s)
{
	vector<sql_token>  tokens;
	sql_lex(s,tokens);
	for(int i=0; i<tokens.size(); i++){
		sql_token &tk=tokens[i];
		size_t keyword_len=0;
		const char *keyword = sql_token_get_name(tk.token_id, &keyword_len);
		printf("%d\t%s\t%s\n",tk.token_id,tk.text.c_str(),keyword);
	}
}
int main()
{
	print_sql("SElect * FROM DB.TB;");
	print_sql("SElect * FROM DB.TB;");
	return 0;

}
