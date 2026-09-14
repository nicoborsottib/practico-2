# Guía paso a paso — TP #2

Esta guía reordena el material del profesor (que viene todo junto y sin secuencia) y lo
explica desde cero. Está pensada para leerse en orden.

---

## Parte 0 — Qué estamos haciendo, en criollo

### El problema de fondo

Cuando escribís `suma(10, 25)` en C, el procesador no tiene ni idea de qué es una
"función". Lo único que sabe hacer es mover números entre registros y memoria, y saltar a
direcciones. Entonces: **¿cómo hace el C para pasarle dos números a otra porción de código,
y recibir una respuesta de vuelta?**

La respuesta es un **acuerdo**: una convención de llamadas. Es un contrato que dice "el
primer argumento te lo dejo en el registro `%rdi`, el segundo en `%rsi`, y vos me devolvés
el resultado en `%rax`". Si las dos partes respetan el contrato, se entienden. En Linux
x86-64 ese contrato se llama **System V AMD64 ABI**.

### Por qué existe el stack

Los registros son pocos (16) y los comparte todo el programa. Si `main` llama a `suma`, y
`suma` usa `%rax` para su cuenta, `main` pierde lo que tenía ahí. Además: ¿dónde guarda
`suma` sus variables locales? ¿Y cómo sabe a qué dirección volver cuando termina?

Para eso está **la pila (stack)**: una zona de memoria donde cada función se arma su
propio "escritorio" temporal — su **stack frame** — mete ahí lo que necesita, y al terminar
lo desarma y deja todo como estaba.

Dato clave: **la pila crece hacia direcciones más bajas.** Cada `push` le resta a `%rsp`,
cada `pop` le suma. Es al revés de lo intuitivo.

### Los dos registros que importan

| Registro | Qué es | Analogía |
|---|---|---|
| `%rsp` | *Stack pointer*. Siempre apunta al tope actual de la pila. | El borde de la pila de platos: se mueve todo el tiempo |
| `%rbp` | *Base pointer*. Apunta a un punto **fijo** dentro de tu frame. | La marca en la pared desde donde medís: no se mueve mientras estés en la función |

¿Por qué hacen falta los dos? Porque `%rsp` se mueve constantemente (cada `push`, cada
`call`). Si quisieras ubicar tus variables relativas a `%rsp`, el offset cambiaría a cada
instrucción. Con `%rbp` clavado al inicio de la función, `-8(%rbp)` significa lo mismo
siempre.

### Anatomía de un stack frame

```
          dirección ALTA
        ┌───────────────────────────┐
24(%rbp)│  8vo argumento (b)        │  ← lo empujó el que llama (caller)
16(%rbp)│  7mo argumento (a)        │  ← lo empujó el caller
 8(%rbp)│  dirección de retorno     │  ← la puso automáticamente 'call'
 0(%rbp)│  %rbp anterior            │  ← lo guardó tu 'pushq %rbp'
-8(%rbp)│  variable local 1         │  ← reservada con 'subq $16, %rsp'
-16(%rbp)│ variable local 2         │
        └───────────────────────────┘  ← %rsp apunta acá
          dirección BAJA
```

Leelo así: **positivos = cosas que me dio el que me llamó. Negativos = cosas mías.**
Y en el medio, en `8(%rbp)`, la dirección a la que tengo que volver.

### El prólogo y el epílogo

Toda función que use frame propio arranca y termina igual:

```asm
mi_funcion:
    pushq %rbp          # PRÓLOGO: guardo el %rbp del que me llamó
    movq  %rsp, %rbp    #          mi frame arranca acá
    subq  $16, %rsp     #          reservo 16 bytes para mis locales (si necesito)

    ...cuerpo...

    movq  %rbp, %rsp    # EPÍLOGO: tiro abajo mis locales
    popq  %rbp          #          devuelvo el %rbp original
    ret                 #          saco la dirección de retorno y salto ahí
```

`leave` es un atajo que hace exactamente `movq %rbp,%rsp ; popq %rbp`.

### Vocabulario que vas a necesitar (de la teoría del profe)

En x86, por razones históricas del 8086, los tamaños tienen nombres fijos:

| Nombre | Tamaño | Sufijo AT&T | Letra en GDB |
|---|---|---|---|
| Byte | 8 bits (1 byte) | `b` | `b` |
| Word | 16 bits (2 bytes) | `w` | `h` (*half word*) |
| Double word | 32 bits (4 bytes) | `l` | `w` |
| **Quadword** | **64 bits (8 bytes)** | `q` | `g` (*giant word*) |

> 📌 **Erratum del README del profe:** ahí dice *"Half Word (Media Palabra): 8 bits (1
> byte)"*. Eso es incorrecto y además se contradice con su propia sección de GDB más
> abajo, donde dice —correctamente— que `h` es *half-word de 2 bytes*. Media palabra de una
> word de 16 bits es **1 byte**, pero el nombre "half word" en la nomenclatura de GDB se
> usa para **2 bytes**. Quedate con la tabla de arriba.

Lo importante para nosotros: en x86-64 **cada ranura de la pila ocupa un quadword (8
bytes)**. Por eso los offsets van siempre de a 8: `-8`, `-16`, `16`, `24`. Y por eso
`subq $16, %rsp` reserva exactamente dos variables locales.

### El comando `x/1gx $rsp` desarmado

Lo vas a usar todo el tiempo en GDB:

- `x` → *examine*, "mostrame memoria"
- `/` → empiezan los parámetros de formato
- `1` → cuántos elementos mostrar
- `g` → *giant word*, de a 8 bytes (quadword)
- `x` → formato hexadecimal
- `$rsp` → desde qué dirección leer

O sea: *"mostrame 1 quadword en hexa, empezando en la cima de la pila"*. Si lo ejecutás
justo al entrar a una función (antes del prólogo), lo que ves es **la dirección de retorno**
que dejó el `call`.

---

## Parte 1 — Preparar el entorno

### 1.1 Instalar las herramientas

```bash
sudo apt update
sudo apt install build-essential gdb python3 python3-pip git
```

- `build-essential` trae `gcc` (compilador C), `as` (ensamblador) y `ld` (enlazador).
- `gdb` es el depurador.

Verificá:

```bash
gcc --version && as --version && ld --version && gdb --version
```

### 1.2 Traer el material del profe

Ya lo tenés clonado en `~/Escritorio/SdeComp/Gitlab/stackframe`. Si necesitaras clonarlo
de nuevo:

```bash
git clone https://gitlab.com/nicoborsottib/stackframe.git
cd stackframe
```

> **Sobre GitLab:** no necesitás cuenta ni entender nada de GitLab. Es igual que GitHub:
> un repo público que clonás con `git clone` y listo. La entrega del TP va en GitHub aparte.

### 1.3 Instalar gdb-dashboard

Esto es **opcional pero muy recomendado**: hace que GDB muestre registros, pila y
desensamblado todos juntos en pantalla en vez de tener que pedirlos de a uno.

```bash
cd ~/Escritorio/SdeComp/Gitlab/stackframe
./setup.sh
```

El `setup.sh` inicializa el submódulo y copia el `.gdbinit` a esa carpeta (o sea, funciona
solo cuando arrancás GDB **desde ahí**).

Si lo querés para todo el sistema:

```bash
wget -P ~ https://github.com/cyrus-and/gdb-dashboard/raw/master/.gdbinit
pip install pygments   # opcional, agrega colores
```

> El README del profe menciona este `wget` en el medio de la teoría, como al pasar. En
> realidad es parte de la preparación del entorno y va acá, **antes** de empezar a debuggear.

---

## Parte 2 — Ejemplo standalone: `asm hello world`

Este es el ejemplo más puro: **assembler solo, sin C**. Un programa que suma 10 + 20 y
devuelve 30 como código de salida.

### 2.1 Qué hace el código

`program.s` tiene dos partes:

- **`_start`** — el punto de entrada real del programa (el equivalente a `main`, pero sin
  la librería estándar de C de por medio). Carga 10 en `%rdi` y 20 en `%rsi`, llama a
  `calc_sum`, y termina el proceso con la syscall `exit` usando el resultado como código de
  salida.
- **`calc_sum`** — arma su stack frame, copia los dos argumentos de los registros a
  variables locales en la pila, las suma, y devuelve en `%rax`.

Fijate que `calc_sum` **no necesitaría** guardar los argumentos en la pila (podría sumar
`%rdi + %rsi` directo). Lo hace a propósito, para que vos puedas *ver* las variables
locales en memoria con GDB. Es un ejercicio didáctico.

### 2.2 Compilar y ejecutar — en este orden

```bash
cd ~/Escritorio/SdeComp/Gitlab/stackframe/"asm hello world"

# 1. Ensamblar, generando símbolos de depuración (-g --gdwarf-2 es lo que
#    después le permite a GDB mostrarte el código fuente mientras avanzás)
as -g --gdwarf-2 -o program.o program.s

# 2. Enlazar. Usamos 'ld' directo (no gcc) porque este programa no usa
#    la librería estándar de C: entra por _start, no por main.
ld -o program program.o

# 3. Ejecutar y ver el código de retorno
./program
echo $?          # tiene que imprimir 30
```

> Las comillas en `"asm hello world"` son necesarias: el nombre de la carpeta tiene
> espacios.

Si `echo $?` imprime 30, ya funcionó. El programa no imprime nada por pantalla — su única
salida es el *exit code*.

### 2.3 Sesión de GDB, ordenada

Acá es donde realmente se aprende: vas a ver la pila armarse y desarmarse en vivo.

**Arrancar:**

```bash
gdb ./program
```

**Dentro de GDB, en este orden:**

```gdb
# --- Preparar ---
break *calc_sum        # breakpoint en la PRIMERA instrucción de calc_sum
break _start           # breakpoint en el punto de entrada
run                    # arranca; se detiene en _start
```

> 💡 Usamos `break *calc_sum` (con asterisco) en vez de `break calc_sum`. Sin el asterisco,
> GDB a veces salta el prólogo automáticamente, y justo el prólogo es lo que queremos ver.

```gdb
# --- Estado inicial ---
info registers rsp rbp rip     # anotá estos valores, los vas a comparar después

# --- Cargar los argumentos ---
stepi                  # ejecuta: movq $10, %rdi
stepi                  # ejecuta: movq $20, %rsi
info registers rdi rsi # verificá: 0xa y 0x14

# --- Entrar a la función ---
stepi                  # ejecuta: call calc_sum
```

Ahora estás **dentro de `calc_sum`, antes del prólogo**. Este es el momento clave:

```gdb
x/1gx $rsp             # la cima de la pila = dirección de retorno
disassemble _start     # compará: tiene que ser la dirección de la instrucción
                       # siguiente al 'call'
```

Eso te demuestra físicamente que `call` empujó la dirección de retorno a la pila.

```gdb
# --- Ver armarse el frame ---
stepi                  # pushq %rbp       (guarda el base pointer del caller)
stepi                  # movq %rsp, %rbp  (establece el nuevo base pointer)
stepi                  # subq $16, %rsp   (reserva las dos variables locales)

x/4gx $rsp             # mirá los 4 quadwords desde la cima
```

El mapa de lo que estás viendo:

| Dirección | Equivale a | Qué contiene |
|---|---|---|
| `$rsp + 0` | `-16(%rbp)` | espacio de la variable `b` (todavía basura) |
| `$rsp + 8` | `-8(%rbp)` | espacio de la variable `a` (todavía basura) |
| `$rsp + 16` | `0(%rbp)` | el `%rbp` viejo que se salvó |
| `$rsp + 24` | `8(%rbp)` | la dirección de retorno |

```gdb
# --- Ver escribirse las variables locales ---
stepi                  # movq %rdi, -8(%rbp)    → copia 10 (0xa)
stepi                  # movq %rsi, -16(%rbp)   → copia 20 (0x14)

x/4gx $rsp             # ahora SÍ ves 0xa y 0x14 en los dos primeros slots
```

```gdb
# --- El cuerpo ---
stepi                  # movq -8(%rbp), %rax    → %rax = 10
stepi                  # addq -16(%rbp), %rax   → %rax = 30 (0x1e)
info registers rax     # confirmá: 0x1e

# --- Ver desarmarse el frame ---
stepi                  # movq %rbp, %rsp   (libera las locales)
stepi                  # popq %rbp         (restaura el base pointer del caller)
info registers rsp rbp # %rsp volvió a apuntar a la dirección de retorno,
                       # %rbp es el mismo valor que tenías al principio

stepi                  # ret  (saca la dirección de retorno y salta a _start)

quit
```

Cuando termines esta sesión y hayas *visto* cada paso, entendiste stack frames. Todo lo
demás del TP es aplicar esto.

---

## Parte 3 — Ejemplo 1: C llamando a ASM (argumentos por registros)

Archivos: `main.c` + `suma.s`

Esta es la forma **normal y correcta** según la ABI: los primeros 6 argumentos enteros
viajan por registros, en este orden estricto:

```
%rdi , %rsi , %rdx , %rcx , %r8 , %r9
```

y el retorno vuelve en `%rax`.

`suma.s` es mínimo — ni siquiera arma frame, porque no lo necesita:

```asm
suma:
    movq %rdi, %rax   # rax = a
    addq %rsi, %rax   # rax = a + b
    ret
```

En `main.c` alcanza con declarar `extern long suma(long a, long b);` y llamarla como
cualquier función de C. El compilador se encarga de poner `a` en `%rdi` y `b` en `%rsi`.

### Compilar

```bash
cd ~/Escritorio/SdeComp/Gitlab/stackframe

as --64 -o suma.o suma.s        # ensamblar el .s
gcc -c main.c -o main.o         # compilar el .c (sin enlazar)
gcc main.o suma.o -o programa   # enlazar los dos objetos
./programa
```

Salida esperada: `suma(10, 25) = 35`

> Acá enlazamos con `gcc` y no con `ld`, porque `main.c` usa `printf` y entra por `main`:
> necesitamos que se enganche la librería estándar de C.

---

## Parte 4 — Ejemplo 2: argumentos **por la pila** ← este es el que importa para el TP

Archivos: `main2.c` + `suma2.s` + `suma_por_pila.s`

Acá hay **dos técnicas distintas** mezcladas en el mismo `main2.c`. Conviene separarlas
mentalmente.

### 4.1 Técnica A — empujar los argumentos a mano (`suma_stack`)

Emula la vieja convención **cdecl** (la clásica de C en 32 bits). En `main2.c` se hace con
assembler en línea:

```c
__asm__ (
    "pushq %[b]\n\t"        // 1. empujo el 2do argumento
    "pushq %[a]\n\t"        // 2. empujo el 1er argumento
    "call suma_stack\n\t"   // 3. llamo
    "addq $16, %%rsp\n\t"   // 4. limpio la pila (2 args x 8 bytes)
    : "=a" (resultado)
    : [a] "r" (a), [b] "r" (b)
    : "memory"
);
```

Del lado del assembler, `suma2.s`:

```asm
suma_stack:
    pushq   %rbp
    movq    %rsp, %rbp
    movq    16(%rbp), %rax   # a
    addq    24(%rbp), %rax   # b
    popq    %rbp
    ret
```

**¿Por qué 16 y 24?** Seguí la cuenta desde `%rbp`:

```
0(%rbp)  → el %rbp viejo      (lo puso 'pushq %rbp')
8(%rbp)  → dirección retorno  (lo puso 'call')
16(%rbp) → 'a'                (fue el ÚLTIMO push, entonces quedó más abajo)
24(%rbp) → 'b'                (fue el PRIMER push, quedó más arriba)
```

Por eso se empuja **en orden inverso**: primero `b`, después `a`. El último que entra es el
primero que aparece.

Y el `addq $16, %rsp` después del `call` es obligatorio: en cdecl **el que llama es el
responsable de limpiar** los argumentos que empujó. Si te lo olvidás, la pila queda
desbalanceada y el programa revienta más adelante.

> ⚠️ Esta técnica con `__asm__` inline es frágil: le estás moviendo la pila por debajo al
> compilador, que no se entera. Sirve para aprender y para el TP está perfecta, pero en
> código real no se hace así.

### 4.2 Técnica B — dejar que la ABI use la pila sola (`suma_por_pila`)

Esta es más elegante y **es la que recomiendo para el TP**. La idea: la ABI dice que
los primeros 6 argumentos van por registros. ¿Y el séptimo? **A la pila.** Entonces si
declarás una función con 8 argumentos, el compilador empuja los dos últimos a la pila
*por vos*, respetando la ABI al pie de la letra.

```c
extern long suma_por_pila(long r1, long r2, long r3, long r4, long r5, long r6,
                          long a, long b);
long res = suma_por_pila(0, 0, 0, 0, 0, 0, 10, 25);
```

Los seis ceros van a `%rdi, %rsi, %rdx, %rcx, %r8, %r9` y se ignoran. Los que nos importan,
`a` y `b`, terminan en la pila — y el assembler los lee exactamente igual que antes:

```asm
suma_por_pila:
    pushq   %rbp
    movq    %rsp, %rbp
    movq    16(%rbp), %rax   # 7mo argumento = a
    addq    24(%rbp), %rax   # 8vo argumento = b
    popq    %rbp
    ret
```

Ventaja: no hay assembler inline, no hay que limpiar la pila a mano, y es ABI-correcto.
Cumple el requisito R5 de la consigna sin trucos.

### 4.3 Compilar

```bash
cd ~/Escritorio/SdeComp/Gitlab/stackframe

as --64 -o suma2.o suma2.s
as --64 -o suma_por_pila.o suma_por_pila.s
gcc -c main2.c -o main2.o
gcc main2.o suma2.o suma_por_pila.o -o programa2
./programa2
```

Salida esperada:

```
suma(10, 25) = 35
suma_por_pila(10, 25) = 35
```

### 4.4 Verlo en GDB

```bash
gdb ./programa2
```

```gdb
break *suma_por_pila
run
x/4gx $rsp          # antes del prólogo: [rsp]=ret addr, [rsp+8]=a, [rsp+16]=b
stepi               # pushq %rbp
stepi               # movq %rsp, %rbp
x/4gx $rbp          # ahora: [rbp]=rbp viejo, [rbp+8]=ret, [rbp+16]=a, [rbp+24]=b
p $rbp              # imprimir el valor de rbp
x/1gx $rbp+16       # tiene que dar 0xa  (10)
x/1gx $rbp+24       # tiene que dar 0x19 (25)
continue
quit
```

Esas dos últimas líneas son **la evidencia** de que los parámetros viajaron por la pila.
Sacale una captura: sirve para defender el TP.

---

## Parte 5 — Detalles de la ABI que te pueden morder

Tres cosas que no se ven en los ejemplos pero son parte del contrato:

**1. Alineación de 16 bytes.** Justo *antes* de ejecutar un `call`, `%rsp` tiene que ser
múltiplo de 16. Como `call` empuja 8 bytes, al entrar a la función queda en `múltiplo+8`.
Por eso el `pushq %rbp` del prólogo la vuelve a alinear. Si tu rutina en assembler llama a
`printf` y se te cae con *segmentation fault* sin razón aparente, **casi seguro es esto**:
metele un `subq $8, %rsp` antes del `call` y un `addq $8, %rsp` después.

**2. Callee-saved vs caller-saved.**

| Tipo | Registros | Regla |
|---|---|---|
| **Callee-saved** | `%rbx`, `%rbp`, `%r12`–`%r15` | Si tu función los usa, **tenés que guardarlos y restaurarlos** |
| **Caller-saved** | `%rax`, `%rcx`, `%rdx`, `%rsi`, `%rdi`, `%r8`–`%r11` | Los podés pisar libremente |

Si tu rutina ASM usa `%rbx` y no lo restaurás, el C que te llamó se va a romper de una
forma rarísima y difícil de encontrar.

**3. Red zone.** Los 128 bytes *debajo* de `%rsp` son zona segura que una función *leaf*
(que no llama a nadie) puede usar sin mover `%rsp`. No lo vas a necesitar, pero si ves
offsets negativos sin `sub`, es esto.

---

## Parte 6 — El TP en sí: arquitectura propuesta

### 6.1 Las tres capas

```
┌─────────────────────────────────────────────┐
│  PYTHON            cliente.py               │
│  · consulta la API REST con requests        │
│  · parsea el JSON                           │
│  · invoca al binario de C con los datos     │
│  · muestra el resultado final               │
└──────────────────┬──────────────────────────┘
                   │  argumentos por línea de comandos
                   ▼
┌─────────────────────────────────────────────┐
│  C                 main.c                   │
│  · recibe los datos crudos (argv)           │
│  · llama a las rutinas de assembler         │
│  · imprime el resultado por stdout          │
└──────────────────┬──────────────────────────┘
                   │  convención de llamadas — POR LA PILA
                   ▼
┌─────────────────────────────────────────────┐
│  ASSEMBLER         conversiones.s           │
│  · arma su stack frame                      │
│  · lee los parámetros de 16(%rbp), 24(%rbp) │
│  · HACE EL CÁLCULO                          │
│  · devuelve en %rax                         │
└─────────────────────────────────────────────┘
```

El resultado vuelve para arriba: `%rax` → C lo imprime → Python lo captura y lo muestra.

### 6.2 Qué API y qué conversión elegir

**Mi recomendación: temperaturas.** API [Open-Meteo](https://open-meteo.com/) (gratis, sin
API key, sin registro) y conversión Celsius → Fahrenheit + Celsius → Kelvin en assembler.

```
GET https://api.open-meteo.com/v1/forecast?latitude=-33.12&longitude=-64.35&current=temperature_2m
```

(esas coordenadas son Río Cuarto)

¿Por qué esta y no otra? Porque la fórmula `F = C × 9/5 + 32` usa multiplicación **y**
división, que en assembler son instrucciones distintas y no triviales (`imulq`, `idivq` con
`cqto`). Queda un TP más sustancioso que una simple suma.

**El truco de los decimales:** la API te devuelve algo como `18.3`. Hacer punto flotante en
assembler es un dolor de cabeza (hay que meterse con SSE y `%xmm0`). La solución es
**aritmética de punto fijo**: en Python multiplicás por 10 y mandás `183` como entero. El
assembler trabaja con enteros, y al final dividís por 10 para mostrar. Todo el mundo
contento.

Alternativas si preferís otra cosa:

| API | Conversión en ASM |
|---|---|
| [dolarapi.com](https://dolarapi.com) | ARS ↔ USD (trabajá en centavos para evitar floats) |
| [Open-Meteo](https://open-meteo.com) | m/s ↔ km/h, hPa ↔ mmHg |
| [REST Countries](https://restcountries.com) | km² ↔ millas², densidad de población |

### 6.3 Plan de trabajo por commits

La consigna pide **un commit por funcionalidad implementada y validada**. Este es un
desglose que cumple eso:

| # | Commit | Qué incluye |
|---|---|---|
| 1 | `Agrega consigna y guía del TP` | ✅ ya hecho |
| 2 | `Implementa rutina ASM de conversión C a F por stack` | `conversiones.s` + prueba manual |
| 3 | `Agrega programa en C que invoca la rutina ASM` | `main.c` + `Makefile`, validado a mano |
| 4 | `Agrega cliente Python que consume la API de Open-Meteo` | `cliente.py`, imprime el JSON crudo |
| 5 | `Integra las tres capas: Python entrega datos al binario C` | el flujo completo andando |
| 6 | `Agrega conversión a Kelvin en ASM` | segunda rutina |
| 7 | `Agrega manejo de errores y validación de entrada` | qué pasa si la API falla |
| 8 | `Documenta compilación, uso y evidencia de GDB` | README + capturas |

> Cada mensaje de commit en español (como pide la cátedra implícitamente) y que diga **qué
> se implementó y que quedó validado**.

### 6.4 Estructura de archivos sugerida

```
practico2/
├── README.md              # cómo compilar y correr
├── CONSIGNA.md            # la consigna y los requisitos
├── GUIA.md                # este archivo
├── Makefile               # para no tipear los as/gcc a mano
├── asm/
│   └── conversiones.s     # las rutinas de cálculo
├── c/
│   └── main.c             # capa intermedia
├── python/
│   └── cliente.py         # capa superior
└── docs/
    └── gdb/               # capturas de las sesiones de depuración
```

---

## Parte 7 — Por dónde empezar mañana

1. **Hacé la Parte 2 completa** (la sesión de GDB del `asm hello world`). No la saltees:
   es una hora de trabajo y es la que hace que todo lo demás tenga sentido.
2. Compilá y corré las Partes 3 y 4. Confirmá que ves los `35`.
3. Hacé la sesión de GDB de 4.4 y sacá la captura de `x/1gx $rbp+16`.
4. Recién ahí arrancá con el código propio del TP, commit por commit según 6.3.

Cuando llegues al punto 4, avisame y armamos el esqueleto (`Makefile`, `conversiones.s`,
`main.c`, `cliente.py`) juntos.

---

## Referencia rápida de comandos GDB

| Comando | Qué hace |
|---|---|
| `break *funcion` | Breakpoint en la primera instrucción (sin saltar el prólogo) |
| `run` | Arranca el programa |
| `stepi` / `si` | Ejecuta **una** instrucción de máquina |
| `nexti` / `ni` | Igual, pero sin entrar a los `call` |
| `continue` / `c` | Sigue hasta el próximo breakpoint |
| `info registers rsp rbp rip` | Muestra esos registros |
| `x/4gx $rsp` | 4 quadwords en hexa desde la cima de la pila |
| `x/1gx $rbp+16` | El quadword en `rbp+16` (el 7mo argumento) |
| `disassemble funcion` | Desensambla la función |
| `p $rax` | Imprime el valor de un registro |
| `backtrace` / `bt` | Cadena de llamadas (usa los `%rbp` encadenados) |
| `quit` | Salir |
