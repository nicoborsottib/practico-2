# Parte B - suma() en ASM invocada desde C (main.c + suma.s)
# Uso:  gdb -x sesion-parteB.gdb ./programa
#
# Compilar antes con simbolos de debug:
#   as --64 -g -o suma.o suma.s
#   gcc -g3 -O0 -c main.c -o main.o
#   gcc -o programa main.o suma.o

echo \n===== CAPTURA 12: como GCC prepara los argumentos =====\n
break main.c:14
run
disassemble main

echo \n===== CAPTURA 13: variables locales antes de la llamada =====\n
info locals
info registers rsp rbp

echo \n===== CAPTURA 14: parados EN el call (4 stepi) =====\n
stepi
stepi
stepi
stepi
info registers rip rdi rsi

echo \n===== CAPTURA 15: dentro de suma, direccion de retorno =====\n
stepi
info registers rip rsp
x/1gx $rsp
disassemble suma

echo \n===== CAPTURA 16: resultado en rax y vuelta a main =====\n
stepi
stepi
info registers rax
stepi
info registers rip rsp rax
