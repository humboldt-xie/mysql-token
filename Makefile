all:
	flex++ -o sql-tokenizer.cc sql-tokenizer.l
	g++ -c sql-tokenizer.cc 
	ar crv libsql-tokenizer.a sql-tokenizer.o
	g++ -o test_main test_main.cc -L./ -lsql-tokenizer -lfl

clean:
	rm libsql-tokenizer.a  sql-tokenizer.cc  test_main ./*.o
