ninja -Cbuild
build/bin/clang -emit-llvm -target tlcs900 -c test-program.c -o test-program.bc
build/bin/llvm-dis test-program.bc 
build/bin/llc -march=tlcs900 -O2 -filetype=asm test-program.bc -o test-program.S
