nasm -f elf64 -o ./build/main.o ./utils.nasm
ld ./build/main.o -o ./build/main
./build/main