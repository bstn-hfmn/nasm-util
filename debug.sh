nasm -f elf64 -o ./build/main.o ./utils.nasm
gcc -o ./build/main ./build/main.o -nostdlib -no-pie

gdb ./build/main