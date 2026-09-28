# Parte 1 — Stack frames en GDB (paso a paso con capturas)

Corresponde a la **Etapa 1.3** de `CONSIGNA.md`, más el **Ejemplo 1** del repo
`stackframe` (argumentos por registros).

Todos los comandos de este documento fueron ejecutados y verificados en Ubuntu x86-64
con `gcc` 13.3, `binutils` 2.42 y `gdb` 15.1. Las salidas que figuran como "lo que tenés
que ver" son salidas reales, no ejemplos inventados.

> **Sobre las direcciones de memoria.** Las direcciones del **stack** (`0x7fffffffca...`)
> dependen de tus variables de entorno y de la ruta del binario, así que en tu máquina
> van a ser distintas. Eso es normal y no es un error. Lo que **sí** tiene que coincidir:
> - las direcciones de **código** del hello world (`0x401000`, `0x40101d`), porque ese
>   binario no es PIE y se linkea en una dirección fija;
> - todos los **valores** (`0xa`, `0x14`, `0x19`, `0x1e`, `0x23`);
> - las **diferencias** entre direcciones (que `%rsp` baje 8, que baje 16, etc.).

---

## Parte A — El hello world (Etapa 1.3)

### A.0 Preparar

```bash
git clone https://gitlab.com/nicoborsottib/stackframe.git
cd stackframe/"asm hello world"
```

Recordá: el README del profe no incluye este `cd` y la carpeta tiene espacios en el
nombre, por eso las comillas.

---

### 📸 CAPTURA 1 — Compilar y correr

```bash
as -g --gdwarf-2 -o program.o program.s
ld -o program program.o
./program; echo $?
```

**Lo que tenés que ver:**

```
30
```

Nada más. El programa no imprime texto: termina con la syscall `exit` y el resultado de
la suma (10 + 20) queda como código de salida. Por eso el `echo $?`.

**Qué decir de esta captura:** que el programa ensambla, linkea y devuelve 30, o sea que
`calc_sum` hizo bien la suma.

---

### A.1 Entrar a GDB

```bash
gdb ./program
```

Todo lo que sigue va adentro del prompt `(gdb)`.

---

### 📸 CAPTURA 2 — Breakpoints y arranque

```
break _start
break calc_sum
run
```

**Lo que tenés que ver:**

```
Breakpoint 1 at 0x40101d: file program.s, line 33.
Breakpoint 2 at 0x401000: file program.s, line 12.

Breakpoint 1, _start () at program.s:33
33	    movq $10, %rdi          # Primer argumento = 10 (0xa)
```

**Qué decir:** pusimos un breakpoint en el punto de entrada y otro en la función. El
programa frenó en `_start`, antes de cargar el primer argumento.

---

### 📸 CAPTURA 3 — Estado inicial de los punteros

```
info registers rsp rbp rip
```

**Lo que tenés que ver:**

```
rsp            0x7fffffffcaa0      0x7fffffffcaa0
rbp            0x0                 0x0
rip            0x40101d            0x40101d <_start>
```

**Qué decir:** `%rbp` vale **0** porque `_start` es el punto de entrada del programa —
no lo llamó nadie, así que no hay ningún frame anterior que anclar. Anotá el valor de
`%rsp`: es la referencia contra la que vamos a comparar todo lo demás.

---

### 📸 CAPTURA 4 — Cargar los argumentos, antes del `call`

```
stepi
stepi
info registers rdi rsi
x/1gx $rsp
```

**Lo que tenés que ver:**

```
rdi            0xa                 10
rsi            0x14                20

0x7fffffffcaa0:	0x0000000000000001
```

**Qué decir:** los dos `stepi` ejecutaron `movq $10,%rdi` y `movq $20,%rsi`. Ahí está la
convención System V AMD64 en acción: el 1er argumento va a `%rdi`, el 2do a `%rsi`.

Y fijate en `x/1gx $rsp`: da **`0x1`**, no una dirección. Eso **todavía no es la dirección
de retorno** — el `call` no se ejecutó. Ese `1` es el `argc` que el kernel dejó en la cima
del stack al arrancar el proceso. Es un buen detalle para mencionar en la defensa.

---

### 📸 CAPTURA 5 — Entramos a `calc_sum`, antes del prólogo

```
stepi
x/1gx $rsp
disassemble _start
info registers rsp rbp
```

**Lo que tenés que ver:**

```
Breakpoint 2, calc_sum () at program.s:12
12	    pushq %rbp

0x7fffffffca98:	0x0000000000401030

Dump of assembler code for function _start:
   0x000000000040101d <+0>:	mov    $0xa,%rdi
   0x0000000000401024 <+7>:	mov    $0x14,%rsi
   0x000000000040102b <+14>:	call   0x401000 <calc_sum>
   0x0000000000401030 <+19>:	mov    %rax,%rdi
   0x0000000000401033 <+22>:	mov    $0x3c,%rax
   0x000000000040103a <+29>:	syscall
End of assembler dump.

rsp            0x7fffffffca98      0x7fffffffca98
rbp            0x0                 0x0
```

**Esta es la captura más importante de la Parte A.** Tres cosas juntas:

1. `%rsp` pasó de `...caa0` a `...ca98`: **bajó exactamente 8 bytes**. Eso lo hizo el
   `call` al apilar la dirección de retorno. Confirma que el stack crece hacia
   direcciones más bajas.
2. En la cima del stack ahora hay `0x401030`.
3. En el `disassemble`, `0x401030` es **`_start+19`**, la instrucción justo después del
   `call`.

O sea: podés señalar el número en la memoria y el número en el desensamblado y mostrar
que son el mismo. **Eso es la dirección de retorno, y la puso el `call`.** No hay que
creerle al apunte: se ve.

---

### 📸 CAPTURA 6 — Después del prólogo, el frame ya armado

```
stepi
stepi
stepi
info registers rsp rbp
x/4gx $rsp
```

**Lo que tenés que ver:**

```
rsp            0x7fffffffca80      0x7fffffffca80
rbp            0x7fffffffca90      0x7fffffffca90

0x7fffffffca80:	0x0000000000000000	0x0000000000000000
0x7fffffffca90:	0x0000000000000000	0x0000000000401030
```

Los tres `stepi` ejecutaron el prólogo completo: `pushq %rbp`, `movq %rsp,%rbp`,
`subq $16,%rsp`.

**Cómo se lee `x/4gx $rsp`:** examinar (`x`) 4 elementos de 8 bytes (`g`, *giant word*)
en hexadecimal (`x`) desde `%rsp`. GDB imprime 2 por línea.

El mapa del frame, de abajo hacia arriba:

| Dirección | Offset desde `%rsp` | Equivale a | Qué hay |
|---|---|---|---|
| `...ca80` | +0  | `-16(%rbp)` | local `b`, todavía vacía |
| `...ca88` | +8  | `-8(%rbp)`  | local `a`, todavía vacía |
| `...ca90` | +16 | `0(%rbp)`   | el `%rbp` viejo (vale 0, el de `_start`) |
| `...ca98` | +24 | `8(%rbp)`   | **la dirección de retorno, `0x401030`** |

**Qué decir:** el frame está armado pero vacío. `%rsp` bajó 16 bytes más por el
`subq $16,%rsp` — ese es el espacio de las dos variables locales. Y `%rbp` quedó
anclado en `...ca90`, que es la frontera: para arriba lo que puso el llamador, para
abajo lo de esta función.

---

### 📸 CAPTURA 7 — Los datos entran al stack

```
stepi
stepi
x/4gx $rsp
```

**Lo que tenés que ver:**

```
0x7fffffffca80:	0x0000000000000014	0x000000000000000a
0x7fffffffca90:	0x0000000000000000	0x0000000000401030
```

**Qué decir:** aparecieron `0x14` (20) y `0xa` (10) en las dos primeras posiciones. Los
argumentos que venían por registro acaban de copiarse a las variables locales del frame.
Es literalmente ver el dato pasar del registro a la memoria.

---

### 📸 CAPTURA 8 — El cuerpo, resultado en `%rax`

```
stepi
stepi
info registers rax
```

**Lo que tenés que ver:**

```
rax            0x1e                30
```

**Qué decir:** `0x1e` = 30. La función leyó las dos locales del stack, las sumó, y dejó
el resultado en `%rax`, que es donde la convención manda devolver.

---

### 📸 CAPTURA 9 — El epílogo destruye el frame

```
stepi
stepi
info registers rsp rbp rax
```

**Lo que tenés que ver:**

```
rsp            0x7fffffffca98      0x7fffffffca98
rbp            0x0                 0x0
rax            0x1e                30
```

**Qué decir:** `movq %rbp,%rsp` tiró las locales y `popq %rbp` restauró el base pointer
del llamador (vuelve a 0). `%rsp` quedó otra vez en `...ca98`, apuntando a la dirección
de retorno — justo como estaba en la Captura 5. El frame se desarmó en orden inverso al
que se armó.

---

### 📸 CAPTURA 10 — El `ret` y la simetría completa

```
stepi
info registers rsp rbp rax rip
```

**Lo que tenés que ver:**

```
rsp            0x7fffffffcaa0      0x7fffffffcaa0
rbp            0x0                 0x0
rax            0x1e                30
rip            0x401030            0x401030 <_start+19>
```

**Esta es la captura de cierre y la que mejor resume todo.** Dos cosas:

1. `%rip` vale `0x401030` = `_start+19`. El `ret` sacó esa dirección del stack y saltó
   ahí. Es exactamente el número que vimos en la Captura 5.
2. `%rsp` volvió a `...caa0`, **idéntico a la Captura 3**, antes de que se llamara a nada.

El recorrido completo de `%rsp`:

```
caa0  →  ca98  →  ca80  →  ca98  →  caa0
inicio   call    prólogo  epílogo   ret
```

Baja y sube en perfecta simetría. Si esa simetría se rompe, el `ret` salta a una
dirección basura y el programa se cae. **Ese es el punto de toda la Parte A.**

Salir con `quit`.

---

## Parte B — Ejemplo 1 del repo: argumentos por registros

Ahora lo mismo pero con C llamando a una función en ASM, que es el caso real del TP.

### B.0 Compilar **con símbolos de debug**

```bash
cd ..    # volver a la raíz del repo stackframe
as --64 -g -o suma.o suma.s
gcc -g3 -O0 -c main.c -o main.o
gcc -o programa main.o suma.o
./programa
```

**Lo que tenés que ver:**

```
suma(10, 25) = 35
```

Al linkear va a aparecer este warning:

```
/usr/bin/ld: warning: suma.o: missing .note.GNU-stack section implies executable stack
```

Es esperable y no rompe nada — está explicado en el Anexo A de `CONSIGNA.md`. Se saca
agregando `.section .note.GNU-stack,"",@progbits` al final del `.s`.

> Importante: el README del profe usa `as --64 -o suma.o suma.s` y `gcc -c main.c` **sin
> `-g`**. Si compilás así, GDB no te muestra el código fuente y esta parte se vuelve
> mucho más difícil. Los flags de arriba son los correctos.

---

### 📸 CAPTURA 11 — Verificar que el símbolo se exportó

```bash
nm suma.o | grep suma
```

**Lo que tenés que ver:**

```
0000000000000000 T suma
```

**Qué decir:** la `T` significa que `suma` está en la sección `.text` (código) y es un
símbolo **global**, o sea que el linker lo puede encontrar desde `main.o`. Si apareciera
una `U` (undefined), faltaría el `.globl` en el `.s`.

---

### 📸 CAPTURA 12 — Cómo GCC prepara los argumentos

```bash
gdb ./programa
```

```
break main.c:14
run
disassemble main
```

**Lo que tenés que ver** (recortá la parte relevante):

```
   0x0000555555555145 <+12>:	movq   $0xa,-0x18(%rbp)
   0x000055555555514d <+20>:	movq   $0x19,-0x10(%rbp)
=> 0x0000555555555155 <+28>:	mov    -0x10(%rbp),%rdx
   0x0000555555555159 <+32>:	mov    -0x18(%rbp),%rax
   0x000055555555515d <+36>:	mov    %rdx,%rsi
   0x0000555555555160 <+39>:	mov    %rax,%rdi
   0x0000555555555163 <+42>:	call   0x555555555196 <suma>
   0x0000555555555168 <+47>:	mov    %rax,-0x8(%rbp)
```

**Ésta es una captura con mucho para decir.** Se ve el ciclo completo de una llamada:

- `main+12` y `+20`: las variables `a`=10 (`0xa`) y `b`=25 (`0x19`) se guardan en el
  stack, en offsets negativos desde `%rbp`.
- `main+28` a `+39`: GCC las saca del stack y las acomoda en `%rsi` y `%rdi`. Fijate que
  usa `%rdx` y `%rax` como intermediarios — son registros de scratch.
- `main+42`: el `call`.
- `main+47`: apenas vuelve, guarda `%rax` (el valor de retorno) en `resultado`.

**Nadie escribió esto**: es el compilador cumpliendo la convención System V AMD64 solo.

---

### 📸 CAPTURA 13 — Las variables locales antes de la llamada

```
info locals
info registers rsp rbp
```

**Lo que tenés que ver:**

```
a = 10
b = 25
resultado = 140737488341720

rsp            0x7fffffffc990      0x7fffffffc990
rbp            0x7fffffffc9b0      0x7fffffffc9b0
```

**Qué decir:** `a` y `b` ya tienen sus valores. `resultado` tiene un número enorme sin
sentido: es **basura de memoria**, porque la variable está declarada pero todavía no se
le asignó nada. Ese valor es lo que había antes en esa posición del stack.

---

### 📸 CAPTURA 14 — Parados justo en el `call`

```
stepi
stepi
stepi
stepi
info registers rip rdi rsi
```

Son **4** `stepi` desde el breakpoint (las cuatro instrucciones `main+28`, `+32`, `+36`,
`+39`).

**Lo que tenés que ver:**

```
rip            0x555555555163      0x555555555163 <main+42>
rdi            0xa                 10
rsi            0x19                25
```

**Qué decir:** estamos parados exactamente en la instrucción `call`, y los argumentos ya
están en su lugar: `%rdi` = 10 (1er argumento), `%rsi` = 25 (2do argumento). Tal cual lo
que manda la ABI.

---

### 📸 CAPTURA 15 — Adentro de `suma`, la dirección de retorno

```
stepi
info registers rip rsp
x/1gx $rsp
disassemble suma
```

**Lo que tenés que ver:**

```
suma () at suma.s:13
13	    movq    %rdi, %rax

rip            0x555555555196      0x555555555196 <suma>
rsp            0x7fffffffc988      0x7fffffffc988

0x7fffffffc988:	0x0000555555555168

Dump of assembler code for function suma:
   0x0000555555555196 <+0>:	mov    %rdi,%rax
   0x0000555555555199 <+3>:	add    %rsi,%rax
   0x000055555555519c <+6>:	ret
End of assembler dump.
```

**La captura clave de la Parte B.** Tres observaciones:

1. `%rsp` pasó de `...c990` a `...c988`: bajó 8 bytes, igual que en la Parte A.
2. En la cima hay `0x555555555168`, que es **`main+47`** — la instrucción justo después
   del `call`, la que vimos en la Captura 12.
3. `suma` **no tiene prólogo**: son tres instrucciones y listo. Es una *leaf function*
   que no necesita frame propio porque no llama a nadie ni usa variables locales. Buen
   contraste con `calc_sum` de la Parte A, que sí armaba frame.

---

### 📸 CAPTURA 16 — El resultado y la vuelta

```
stepi
stepi
info registers rax
stepi
info registers rip rsp rax
```

**Lo que tenés que ver:**

```
rax            0x23                35

rip            0x555555555168      0x555555555168 <main+47>
rsp            0x7fffffffc990      0x7fffffffc990
rax            0x23                35
```

**Qué decir:** `0x23` = 35 = 10 + 25. Después del `ret`, `%rip` volvió a `main+47` y
`%rsp` a `...c990`, exactamente donde estaba en la Captura 14. El valor de retorno viaja
en `%rax`, y la próxima instrucción de `main` lo guarda en `resultado`.

Salir con `quit`.

---

## Resumen de capturas

| # | Qué muestra | Dónde |
|---|---|---|
| 1 | Compila y devuelve 30 | terminal |
| 2 | Breakpoints puestos, parado en `_start` | gdb |
| 3 | `%rbp` = 0, estado inicial | gdb |
| 4 | Argumentos en `%rdi`/`%rsi`, cima ≠ dirección de retorno | gdb |
| 5 | **La dirección de retorno = `_start+19`** | gdb |
| 6 | Frame armado y vacío, mapa de 4 posiciones | gdb |
| 7 | Los datos entran al stack (`0x14`, `0xa`) | gdb |
| 8 | Resultado 30 en `%rax` | gdb |
| 9 | Epílogo: `%rsp`/`%rbp` restaurados | gdb |
| 10 | **`ret` y la simetría completa de `%rsp`** | gdb |
| 11 | Símbolo exportado (`T suma`) | terminal |
| 12 | **GCC cumpliendo la ABI solo** | gdb |
| 13 | Locales cargadas, `resultado` con basura | gdb |
| 14 | Parados en el `call`, `%rdi`=10 `%rsi`=25 | gdb |
| 15 | **Dirección de retorno = `main+47`; `suma` sin prólogo** | gdb |
| 16 | `%rax` = 35 y vuelta a `main` | gdb |

Las cuatro en negrita son las que valen para la defensa. Si el tiempo no da para las
dieciséis, saquen al menos esas.

Guardarlas en `gdb/parte1/` numeradas: `01-compilacion.png`, `02-breakpoints.png`, etc.
Con una línea de texto al lado de cada una diciendo qué se está mirando — una captura
sin explicación no demuestra que se entendió.

---

## Lo que sigue

**Parte 2**: el Ejemplo 2 del repo (`main2.c` + `suma_por_pila.s`), donde los argumentos
7 y 8 ya no entran en los registros y el compilador los tiene que empujar al stack. Ahí
se leen con `16(%rbp)` y `24(%rbp)`, y es el mecanismo que va a usar el TP para cumplir
el requisito R6.
