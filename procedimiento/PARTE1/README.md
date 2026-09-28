# Parte 1 — Anatomía del stack frame en x86-64

Primer acercamiento práctico a las convenciones de llamada. El objetivo es observar con
el depurador cómo se construye y se destruye el marco de pila de una función, dónde
quedan los argumentos y quién coloca la dirección de retorno.

Se trabajó sobre el material de cátedra
[`stackframe`](https://gitlab.com/nicoborsottib/stackframe), en dos escenarios:

- **A.** Una función en ensamblador puro, sin biblioteca C, que arma su propio marco.
- **B.** Una función en ensamblador invocada desde C, que es el caso que usará el TP.

El procedimiento reproducible completo, con todos los comandos y sus salidas esperadas,
está en [`guia.md`](guia.md). Los scripts [`sesion-parteA.gdb`](sesion-parteA.gdb) y
[`sesion-parteB.gdb`](sesion-parteB.gdb) permiten repetir cada sesión de una sola vez.

---

## A. Función en ensamblador puro

El programa `program.s` no usa la biblioteca de C. Su punto de entrada `_start` llama a
`calc_sum(10, 20)`, que construye un marco de pila, guarda los argumentos como variables
locales, los suma y devuelve el resultado. El programa finaliza con la syscall `exit`
usando ese resultado como código de salida.

### A.1 Compilación y ejecución

```bash
as -g --gdwarf-2 -o program.o program.s
ld -o program program.o
./program; echo $?
```

Se ensambla con `-g --gdwarf-2` para incluir información de depuración, y se enlaza
directamente con `ld` porque el programa no necesita la biblioteca estándar de C.

![Compilación y ejecución](capturas/01-compilacion.png)

El programa devuelve **30**, que es 10 + 20. Como no imprime nada por pantalla, el
resultado se consulta con `echo $?`.

### A.2 Puesta en marcha del depurador

```
gdb ./program
```

Y dentro de GDB, **un comando por línea**:

```
break _start
break calc_sum
run
info registers rsp rbp rip
```

En este punto `%rbp` vale `0`. Es coherente: `_start` es el punto de entrada del proceso
y no fue invocado por ninguna función, de modo que no hay ningún marco anterior al que
anclarse. El valor de `%rsp` en este instante es la referencia con la que se comparan
todos los estados posteriores.

Los dos primeros `stepi` ejecutan `movq $10,%rdi` y `movq $20,%rsi`, dejando los
argumentos en los registros que la ABI asigna al primer y segundo parámetro entero.

Conviene observar acá que `x/1gx $rsp` devuelve `0x1`, que **no** es una dirección de
retorno: es el `argc` que el kernel deja en la cima de la pila al iniciar el proceso. La
dirección de retorno todavía no existe, porque el `call` no se ejecutó.

### A.3 La dirección de retorno

```
stepi
x/1gx $rsp
disassemble _start
```

![Dirección de retorno](capturas/02-direccion-retorno.png)

Este es el resultado central de la parte A. Se verifican tres hechos a la vez:

1. `%rsp` **bajó exactamente 8 bytes**. Lo hizo la instrucción `call` al apilar la
   dirección de retorno. Queda comprobado que la pila crece hacia direcciones menores.
2. En la cima de la pila aparece el valor `0x401030`.
3. En el desensamblado de `_start`, `0x401030` es `_start+19`: **la instrucción
   inmediatamente posterior al `call`**.

La dirección de retorno deja de ser un concepto del apunte y pasa a ser un número
concreto, ubicado en una posición de memoria que se puede señalar y contrastar.

### A.4 El prólogo construye el marco

```
stepi        # pushq %rbp
stepi        # movq %rsp, %rbp
stepi        # subq $16, %rsp
x/4gx $rsp
stepi        # movq %rdi, -8(%rbp)
stepi        # movq %rsi, -16(%rbp)
x/4gx $rsp
```

El comando `x/4gx $rsp` examina cuatro elementos de 8 bytes (*giant words*) en
hexadecimal a partir de `%rsp`. GDB los imprime de a dos por línea.

![Marco armado con los datos](capturas/03-frame-y-locales.png)

La estructura que queda:

| Offset desde `%rsp` | Equivale a | Contenido |
|---|---|---|
| +0  | `-16(%rbp)` | variable local `b` → `0x14` (20) |
| +8  | `-8(%rbp)`  | variable local `a` → `0xa` (10) |
| +16 | `0(%rbp)`   | `%rbp` del llamador |
| +24 | `8(%rbp)`   | dirección de retorno |

`%rbp` funciona como frontera del marco: los **offsets positivos** corresponden a datos
que colocó el llamador, y los **negativos**, a variables locales de la función actual.

En la captura se ven los valores `0x14` y `0xa` ya escritos en las posiciones
reservadas: es el traslado de los argumentos desde los registros hacia la memoria del
marco, ocurriendo a la vista.

### A.5 Cuerpo, epílogo y retorno

Las instrucciones siguientes leen ambas locales desde la pila, las suman y dejan el
resultado en `%rax` (`0x1e` = 30), que es el registro donde la ABI manda devolver.

El epílogo revierte el prólogo: `movq %rbp,%rsp` libera el espacio de las locales y
`popq %rbp` restaura el base pointer del llamador. Finalmente `ret` extrae de la pila la
dirección que el `call` había depositado y salta a ella.

```
stepi
stepi
info registers rax
stepi
stepi
stepi
info registers rsp rbp rax rip
```

![Retorno y simetría](capturas/04-retorno-simetria.png)

`%rip` pasa a valer `0x401030` = `_start+19`, exactamente el número observado en A.3. Y
`%rsp` recupera su valor inicial.

El recorrido completo del stack pointer durante la llamada:

```
inicio   →   call   →  prólogo  →  epílogo  →   ret
 caa0        ca98        ca80        ca98        caa0
```

Construcción y destrucción son **simétricas**. Si esa simetría se rompiera —por ejemplo
omitiendo el `popq %rbp`— la instrucción `ret` extraería un valor equivocado y el
programa saltaría a una dirección arbitraria. Es la razón por la que el epílogo no es
opcional cuando hubo prólogo.

---

## B. Función en ensamblador invocada desde C

Mismo análisis, pero con código C que llama a una rutina escrita en ensamblador y
enlazada por separado. Es la situación que reproducirá el TP.

### B.1 Compilación con símbolos de depuración

```bash
as --64 -g -o suma.o suma.s
gcc -g3 -O0 -c main.c -o main.o
gcc -o programa main.o suma.o
./programa
```

Los flags no son opcionales: `-g3` incorpora información de depuración y `-O0`
desactiva las optimizaciones. Con optimizaciones activas el compilador puede eliminar el
prólogo del marco o mantener variables únicamente en registros, y la sesión de
depuración dejaría de corresponderse con el código fuente.

![Compilación C + ASM](capturas/05-compilacion-c-asm.png)

El enlazado emite un aviso — `missing .note.GNU-stack section implies executable stack`—
porque los archivos `.s` del material de cátedra no declaran esa sección. No afecta el
funcionamiento; se corrige agregando `.section .note.GNU-stack,"",@progbits` al final
del archivo.

La verificación con `nm suma.o | grep suma` devuelve `T suma`: la marca `T` indica que el
símbolo reside en la sección `.text` y es global, por lo que el linker puede resolverlo
desde `main.o`. Si apareciera `U`, faltaría la directiva `.globl`.

### B.2 El compilador aplicando la convención

```
gdb ./programa
```

```
break main.c:14
run
disassemble main
```

![Desensamblado de main](capturas/06-disassemble-main.png)

El desensamblado muestra el ciclo completo de una llamada, generado automáticamente por
GCC:

- las variables `a` = 10 (`0xa`) y `b` = 25 (`0x19`) se almacenan en offsets negativos
  desde `%rbp`;
- se recuperan de la pila y se ubican en `%rdi` y `%rsi`, usando `%rax` y `%rdx` como
  registros intermedios;
- se ejecuta `call`;
- al retornar, `%rax` se guarda de inmediato en la variable `resultado`.

Ninguna de estas instrucciones fue escrita por el programador. Es el compilador
cumpliendo la System V AMD64 ABI por su cuenta, que es precisamente el contrato que
permite que dos archivos compilados por separado —uno en C y otro en ensamblador—
puedan comunicarse.

Con `info locals` se observa además que `resultado` contiene un valor sin sentido: está
declarada pero todavía no se le asignó nada, de modo que exhibe el contenido previo de
esa posición de memoria.

### B.3 Dentro de la rutina en ensamblador

Desde el breakpoint hacen falta **cuatro** `stepi` para quedar parados en la instrucción
`call`, y uno más para entrar en la función.

```
stepi
stepi
stepi
stepi
info registers rip rdi rsi
stepi
info registers rip rsp
x/1gx $rsp
disassemble suma
```

![Dentro de suma](capturas/07-dentro-de-suma.png)

Antes del `call`, los argumentos están en su lugar: `%rdi` = 10 y `%rsi` = 25. Al entrar
en la función, `%rsp` bajó 8 bytes y en la cima aparece la dirección de `main+47`, la
instrucción posterior al `call`, coincidente con lo observado en B.2.

Un detalle que vale la pena señalar: **`suma` no construye marco de pila**. Son tres
instrucciones —`mov`, `add`, `ret`— sin prólogo ni epílogo. Se trata de una *leaf
function*: no invoca a ninguna otra rutina ni utiliza variables locales, así que no
necesita marco propio. Contrasta con `calc_sum` de la parte A, que sí lo construye. El
prólogo no es un requisito formal de toda función, sino un mecanismo que se emplea
cuando hace falta.

### B.4 El valor de retorno

```
stepi
stepi
info registers rax
stepi
info registers rip rsp rax
```

![Resultado y retorno](capturas/08-resultado.png)

`%rax` = `0x23` = **35** = 10 + 25. Tras el `ret`, `%rip` retorna a `main+47` y `%rsp`
recupera su valor previo a la llamada. La instrucción siguiente de `main` transfiere
`%rax` a la variable `resultado`, cerrando el ciclo.

---

## Conclusiones de la parte

1. **El pasaje de argumentos responde a un contrato estricto.** Los primeros seis
   argumentos enteros viajan en `%rdi`, `%rsi`, `%rdx`, `%rcx`, `%r8` y `%r9`, en ese
   orden; el valor de retorno regresa siempre en `%rax`. Se verificó tanto en código
   ensamblador escrito a mano como en código generado por el compilador.

2. **La dirección de retorno es un dato en memoria.** La deposita la instrucción `call`
   en la cima de la pila y la extrae `ret`. Se la pudo localizar en una dirección
   concreta y contrastar con el desensamblado del llamador, en los dos escenarios.

3. **La pila crece hacia direcciones menores.** Cada `call` decrementa `%rsp` en 8 bytes;
   la reserva de variables locales lo decrementa en el tamaño solicitado.

4. **El marco se construye y se destruye simétricamente.** Al finalizar la llamada,
   `%rsp` y `%rbp` recuperan exactamente sus valores previos. Esa simetría es la
   condición que permite que `ret` retorne al punto correcto.

5. **El prólogo es opcional.** Una función hoja que no requiere variables locales puede
   prescindir de él, como quedó evidenciado al comparar `calc_sum` con `suma`.

Con esto queda cubierto el caso en que los argumentos **sí** entran en los registros
disponibles. La Parte 2 aborda qué ocurre cuando son más de seis y el compilador debe
transferirlos por la pila, que es el mecanismo que el TP necesita para cumplir su
requisito central.

---

## Nota sobre las direcciones de memoria

Las direcciones del **stack** (`0x7fffffffca...`) dependen de las variables de entorno y
de la ruta del binario, de modo que varían entre máquinas. Lo que se mantiene constante
son los **valores** (`0xa`, `0x14`, `0x19`, `0x1e`, `0x23`), las direcciones de **código**
del programa sin PIE de la parte A (`0x401000`, `0x40101d`) y, sobre todo, las
**diferencias** entre direcciones, que son las que sostienen el análisis.
