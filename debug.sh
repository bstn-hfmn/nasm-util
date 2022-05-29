nasm -felf64 ./utils.nasm -o ./build/main.o  && ld ./build/main.o -o ./build/main.out && ./build/main.out
gcc -o ./build/main ./build/main.o -nostdlib -no-pie

gdb ./build/main