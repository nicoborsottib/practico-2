# Parte A - calc_sum en ASM puro (program.s)
# Uso:  gdb -x sesion-parteA.gdb ./program
#
# Cada 'echo' marca un punto de captura. Para ir parando y sacar las
# capturas a mano, comentá el resto y avanzá con los comandos sueltos.

echo \n===== CAPTURA 2: breakpoints y arranque =====\n
break _start
break calc_sum
run

echo \n===== CAPTURA 3: registros al arrancar =====\n
info registers rsp rbp rip

echo \n===== CAPTURA 4: argumentos cargados, antes del call =====\n
stepi
stepi
info registers rdi rsi
x/1gx $rsp

echo \n===== CAPTURA 5: dentro de calc_sum, ANTES del prologo =====\n
stepi
x/1gx $rsp
disassemble _start
info registers rsp rbp

echo \n===== CAPTURA 6: DESPUES del prologo, frame armado =====\n
stepi
stepi
stepi
info registers rsp rbp
x/4gx $rsp

echo \n===== CAPTURA 7: locales escritas en el stack =====\n
stepi
stepi
x/4gx $rsp

echo \n===== CAPTURA 8: cuerpo ejecutado, resultado en rax =====\n
stepi
stepi
info registers rax

echo \n===== CAPTURA 9: epilogo, stack restaurado =====\n
stepi
stepi
info registers rsp rbp rax

echo \n===== CAPTURA 10: ret, vuelta a _start =====\n
stepi
info registers rsp rbp rax rip
