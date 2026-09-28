# Parte 1 — Stack frames en x86-64 con GDB

**TP2 — Sistemas de Computación (UNC)** · Ing. Javier Jorge

Integrantes: Nicolás Borsotti Bosco · Santiago Valentín Ciacci · Ignacio Ariel Leguizamón

---

## Objetivo

Verificar experimentalmente, con el depurador, cómo se construye y se destruye un
**stack frame** en la arquitectura x86-64 bajo la convención de llamadas
**System V AMD64 ABI**. Concretamente:

- dónde y cómo se pasan los argumentos de una función;
- quién coloca la dirección de retorno y en qué posición de memoria;
- qué hacen exactamente el prólogo y el epílogo de una función;
- por qué el stack crece hacia direcciones de memoria más bajas.

Este trabajo es la base del requisito **R6** del TP (*"se debe utilizar el stack para
enviar parámetros y devolver resultados"*): antes de forzar el paso de parámetros por la
pila hay que poder observar la pila.

## Material y ambiente

| Componente | Versión |
|---|---|
| Sistema operativo | Ubuntu (x86-64) |
| Ensamblador | GNU `as` (binutils) |
| Linker | GNU `ld` |
| Compilador | `gcc` |
| Depurador | `gdb` |

Código fuente analizado: repositorio de cátedra
[`stackframe`](https://gitlab.com/nicoborsottib/stackframe), carpeta `asm hello world`
(`program.s`) y raíz (`main.c` + `suma.s`).

> El procedimiento reproducible, con todos los comandos y las salidas esperadas, está en
> [`guia.md`](guia.md).

---

## Parte A — Función en ASM puro (`program.s`)

Programa sin biblioteca C: `_start` llama a `calc_sum(10, 20)`, que arma su propio stack
frame, guarda los argumentos como variables locales, los suma y devuelve el resultado.
El programa termina con la syscall `exit` usando ese resultado como código de salida.

### A.1 Compilación y ejecución

```bash
as -g --gdwarf-2 -o program.o program.s
ld -o program program.o
./program; echo $?
```

![Compilación y ejecución](capturas/01-compilacion.png)

El programa no imprime texto en pantalla: devuelve **30** como código de salida, que es
el resultado de 10 + 20. Por eso se consulta con `echo $?`.

### A.2 Estado inicial

```
break _start
break calc_sum
run
info registers rsp rbp rip
```

![Breakpoints y arranque](capturas/02-breakpoints.png)

![Registros iniciales](capturas/03-registros-iniciales.png)

`%rbp` vale **0**. `_start` es el punto de entrada del proceso: no fue invocado por
ninguna función, de modo que no existe ningún frame anterior al que anclarse. El valor
de `%rsp` en este momento es la referencia contra la cual se comparan todos los estados
posteriores.

### A.3 Carga de argumentos

```
stepi
stepi
info registers rdi rsi
x/1gx $rsp
```

![Argumentos en registros](capturas/04-argumentos-registros.png)

Los argumentos quedan en `%rdi` = 10 (`0xa`) y `%rsi` = 20 (`0x14`), exactamente el orden
que fija la ABI para el primer y segundo parámetro entero.

En este punto `x/1gx $rsp` devuelve `0x1`, que **no** es una dirección de retorno: es el
`argc` que el kernel deja en la cima de la pila al iniciar el proceso. La dirección de
retorno todavía no existe porque el `call` no se ejecutó.

### A.4 Entrada a la función: la dirección de retorno

```
stepi
x/1gx $rsp
disassemble _start
info registers rsp rbp
```

![Dirección de retorno](capturas/05-direccion-retorno.png)

Resultado central de esta parte. Tres hechos simultáneos:

1. `%rsp` **disminuyó exactamente 8 bytes**. Lo hizo la instrucción `call` al apilar la
   dirección de retorno. Se comprueba que la pila crece hacia direcciones menores.
2. En la cima de la pila aparece el valor `0x401030`.
3. En el desensamblado de `_start`, la dirección `0x401030` corresponde a `_start+19`,
   es decir, **la instrucción inmediatamente posterior al `call`**.

La dirección de retorno no es una abstracción del apunte: es un valor concreto,
depositado por el hardware en una posición de memoria identificable.

### A.5 El prólogo construye el frame

```
stepi        # pushq %rbp
stepi        # movq %rsp, %rbp
stepi        # subq $16, %rsp
info registers rsp rbp
x/4gx $rsp
```

![Frame armado](capturas/06-frame-armado.png)

El comando `x/4gx $rsp` examina cuatro elementos de 8 bytes (*giant words*) en
hexadecimal a partir de `%rsp`. La estructura resultante:

| Offset desde `%rsp` | Equivale a | Contenido |
|---|---|---|
| +0  | `-16(%rbp)` | variable local `b` (sin inicializar) |
| +8  | `-8(%rbp)`  | variable local `a` (sin inicializar) |
| +16 | `0(%rbp)`   | `%rbp` del llamador |
| +24 | `8(%rbp)`   | dirección de retorno |

`%rbp` marca la frontera del frame: **offsets positivos** corresponden a datos que
colocó el llamador; **offsets negativos**, a variables locales de la función actual.

### A.6 Escritura de las variables locales

```
stepi        # movq %rdi, -8(%rbp)
stepi        # movq %rsi, -16(%rbp)
x/4gx $rsp
```

![Locales escritas](capturas/07-locales-escritas.png)

Aparecen `0x14` (20) y `0xa` (10) en las posiciones reservadas. Se observa directamente
el traslado de los argumentos desde los registros hacia la memoria del stack frame.

### A.7 Cuerpo de la función

```
stepi
stepi
info registers rax
```

![Resultado en rax](capturas/08-resultado-rax.png)

`%rax` = `0x1e` = **30**. La función leyó ambas variables locales desde la pila, las
sumó y dejó el resultado en `%rax`, el registro que la ABI designa para el valor de
retorno.

### A.8 El epílogo destruye el frame

```
stepi        # movq %rbp, %rsp
stepi        # popq %rbp
info registers rsp rbp rax
```

![Epílogo](capturas/09-epilogo.png)

`movq %rbp,%rsp` libera el espacio de las variables locales y `popq %rbp` restaura el
base pointer del llamador. `%rsp` vuelve a apuntar a la dirección de retorno, en el mismo
estado que en A.4.

### A.9 Retorno y simetría

```
stepi        # ret
info registers rsp rbp rax rip
```

![Retorno](capturas/10-retorno.png)

`%rip` pasa a valer `0x401030` = `_start+19`: la instrucción `ret` extrajo de la pila la
dirección que el `call` había depositado y saltó a ella. `%rsp` recupera su valor
inicial.

El recorrido completo del stack pointer durante la llamada:

```
inicio  →   call   →  prólogo  →  epílogo  →   ret
 caa0       ca98        ca80       ca98        caa0
```

La construcción y la destrucción del frame son **simétricas**. Si esa simetría se rompe
—por ejemplo, omitiendo el `popq %rbp`— la instrucción `ret` extraería un valor
incorrecto y el programa saltaría a una dirección arbitraria.

---

## Parte B — Función en ASM invocada desde C (`main.c` + `suma.s`)

Caso equivalente al que utilizará el TP: código C que llama a una rutina escrita en
ensamblador y enlazada por separado.

### B.1 Compilación con símbolos de depuración

```bash
as --64 -g -o suma.o suma.s
gcc -g3 -O0 -c main.c -o main.o
gcc -o programa main.o suma.o
./programa
```

![Compilación ejemplo 1](capturas/11-compilacion-e1.png)

Los flags `-g3` (información de depuración) y `-O0` (sin optimizaciones) son necesarios:
con optimizaciones activas el compilador puede eliminar el prólogo del frame o mantener
variables únicamente en registros, y la sesión de depuración dejaría de corresponderse
con el código fuente.

La verificación con `nm suma.o` muestra el símbolo con marca `T`, indicando que reside
en la sección `.text` y es global, por lo que el linker puede resolverlo desde `main.o`.

### B.2 Preparación de los argumentos por parte del compilador

```
break main.c:14
run
disassemble main
```

![Disassemble main](capturas/12-disassemble-main.png)

El desensamblado de `main` muestra el ciclo completo de una llamada, generado
automáticamente por GCC:

- las variables `a` = 10 (`0xa`) y `b` = 25 (`0x19`) se almacenan en offsets negativos
  desde `%rbp`;
- se recuperan de la pila y se ubican en `%rdi` y `%rsi`, usando `%rax` y `%rdx` como
  registros intermedios;
- se ejecuta `call`;
- al retornar, `%rax` se guarda inmediatamente en la variable `resultado`.

Ninguna de estas instrucciones fue escrita por el programador: es el compilador
aplicando la convención System V AMD64.

### B.3 Variables locales antes de la llamada

```
info locals
info registers rsp rbp
```

![Variables locales](capturas/13-locales-main.png)

`a` y `b` contienen sus valores. `resultado` muestra un valor sin sentido: está
declarada pero aún no se le asignó nada, de modo que exhibe el contenido previo de esa
posición de memoria.

### B.4 Instrucción `call`

```
stepi
stepi
stepi
stepi
info registers rip rdi rsi
```

![Antes del call](capturas/14-antes-del-call.png)

Son **cuatro** instrucciones desde el breakpoint hasta el `call`. Los argumentos están
ubicados: `%rdi` = 10, `%rsi` = 25.

### B.5 Dentro de la rutina en ensamblador

```
stepi
info registers rip rsp
x/1gx $rsp
disassemble suma
```

![Dentro de suma](capturas/15-dentro-de-suma.png)

`%rsp` disminuye 8 bytes y en la cima aparece la dirección de `main+47`, la instrucción
posterior al `call`, coincidente con lo observado en B.2.

Obsérvese que `suma` **no construye stack frame**: consta de tres instrucciones
(`mov`, `add`, `ret`). Se trata de una *leaf function* — no invoca a ninguna otra rutina
ni utiliza variables locales, por lo que no necesita prólogo ni epílogo. Contrasta con
`calc_sum` de la Parte A, que sí los construye. El prólogo no es un requisito formal de
toda función, sino un mecanismo que se emplea cuando hace falta.

### B.6 Valor de retorno

```
stepi
stepi
info registers rax
stepi
info registers rip rsp rax
```

![Resultado y retorno](capturas/16-resultado-retorno.png)

`%rax` = `0x23` = **35** = 10 + 25. Tras el `ret`, `%rip` retorna a `main+47` y `%rsp`
recupera su valor previo a la llamada. La instrucción siguiente de `main` transfiere
`%rax` a la variable `resultado`.

---

## Conclusiones

1. **El paso de argumentos sigue un contrato estricto.** Los primeros seis argumentos
   enteros viajan en `%rdi`, `%rsi`, `%rdx`, `%rcx`, `%r8` y `%r9`, en ese orden; el
   valor de retorno regresa siempre en `%rax`. Se verificó tanto en código ensamblador
   escrito a mano como en código generado por GCC.

2. **La dirección de retorno es un dato en memoria.** La deposita la instrucción `call`
   en la cima de la pila y la extrae `ret`. Se la pudo localizar en una dirección
   concreta y contrastar con el desensamblado del llamador.

3. **El stack crece hacia direcciones menores.** Cada `call` y cada `push` decrementan
   `%rsp` en 8 bytes; la reserva de variables locales lo decrementa en el tamaño
   solicitado.

4. **El frame se construye y se destruye simétricamente.** Al finalizar la llamada,
   `%rsp` y `%rbp` recuperan exactamente sus valores previos. Esa simetría es la
   condición que permite que `ret` retorne al punto correcto.

5. **El prólogo es opcional.** Una función hoja que no requiere variables locales puede
   prescindir de él, como quedó evidenciado al comparar `calc_sum` con `suma`.

Estos resultados habilitan la Parte 2, donde se analiza el caso en que los argumentos
**no** caben en los seis registros disponibles y el compilador debe transferirlos por la
pila — el mecanismo que el TP debe utilizar para satisfacer el requisito R6.

---

## Archivos

| Archivo | Contenido |
|---|---|
| [`guia.md`](guia.md) | Procedimiento reproducible: comandos y salidas esperadas |
| `capturas/` | Capturas de pantalla de la sesión |
