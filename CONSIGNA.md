# TP2 — Calculadora de índices GINI

Hoja de ruta por etapas. Sistemas de Computación (UNC) — Ing. Javier Jorge.

Este documento no es la consigna oficial: es la consigna del PDF traducida a pasos
ejecutables, ordenada de forma que se pueda arrancar hoy con lo poco que se vio en
clase y que cada etapa nueva dependa solo de la anterior.

**Integrantes:** Nicolás Borsotti Bosco · Santiago Valentín Ciacci · Ignacio Ariel Leguizamón

---

## Qué pide el TP, en una frase

Armar una aplicación de **tres capas** que muestre el índice GINI: **Python** baja los
datos del Banco Mundial por API REST, se los pasa a **C**, y C llama a rutinas en
**ensamblador x86-64** que hacen los cálculos — pasando los parámetros **por el stack**,
no por registros. Y después demostrar con **GDB** que el stack realmente se usa así.

Lo que se entrega no es solo el programa: es el programa **más la evidencia de que se
entiende cómo viaja un parámetro de una capa a la otra**. Esa evidencia es la sesión de
GDB de la Etapa 6.

### Requisitos textuales del PDF

| # | Requisito | Dónde se cumple |
|---|---|---|
| R1 | Capa superior en Python que consuma la API REST del Banco Mundial | Etapa 4 |
| R2 | Capa intermedia en C que reciba esos datos | Etapa 5 |
| R3 | Capa inferior en ASM: conversión float → entero | Etapa 7 |
| R4 | Devolver el índice de un país sumándole uno (+1) | Etapa 7 |
| R5 | Mostrar los datos obtenidos desde C o Python | Etapa 5 |
| R6 | **Usar el stack para enviar parámetros y devolver resultados** | Etapa 7 |
| R7 | Iteración 1: todo en C + Python, **sin** ensamblador | Etapas 4–5 |
| R8 | Iteración 2: agregar ensamblador | Etapa 7 |
| R9 | **Mostrar los resultados con GDB**: stack antes, durante y después de la función | Etapa 6 y 8 |
| R10 | Repo privado en GitHub, un responsable con mail institucional, forks y PRs | Etapa 3 |
| R11 | Un commit comentado por cada funcionalidad implementada y validada | todas |
| R12 | Defensa **grupal** | Etapa 10 |

Opcionales que el PDF marca como "bienvenidos" / "un plus": casos de prueba, diagramas
de bloques, diagrama de secuencia, comparación de performance C vs Python, y profiling
de la app de C. Están en la Etapa 9.

---

## Mapa de etapas

```
HOY, sin depender de la clase:
  Etapa 0  Ambiente de trabajo
  Etapa 1  Dominar el hello world del profe          ← lo único que ya vieron
  Etapa 2  Anatomía del stack frame
  Etapa 3  Repo y flujo de trabajo grupal

ITERACIÓN 1 (sin ensamblador):
  Etapa 4  Python: bajar el GINI de la API
  Etapa 5  C: recibir los datos y calcular
  Etapa 6  Punto de control: GDB sobre C puro

ITERACIÓN 2 (con ensamblador):
  Etapa 7  ASM: float → int, +1, todo por el stack
  Etapa 8  La demo de GDB (antes / durante / después)

CIERRE:
  Etapa 9  Plus opcionales
  Etapa 10 Informe y defensa
```

La Etapa 6 es un punto de control intencional: cierra la iteración 1 dejando andando la
sesión de GDB sobre un programa en C que ya funciona. Cuando en la Etapa 8 haya que
debuggear el ensamblador, el procedimiento ya va a estar aprendido y el único elemento
nuevo va a ser el código ASM.

---

## Etapa 0 — Ambiente de trabajo

**Se puede hacer hoy.** No depende de ningún tema de clase.

Hace falta Linux x86-64. Probado por la cátedra con Ubuntu 22.04; en 24.04 anda igual.
Si alguien está en Windows, WSL2 con Ubuntu alcanza y sobra para todo el TP.

```bash
sudo apt update
sudo apt install build-essential nasm gdb python3 python3-pip
```

`build-essential` ya trae `gcc`, `as` (GNU assembler) y `ld` (linker).

Verificar que quedó todo:

```bash
uname -m          # tiene que decir x86_64
gcc --version
as --version
gdb --version
python3 --version
```

> **Sobre `gcc-multilib g++-multilib`:** el PDF los pide, pero son las librerías de
> **32 bits**. Todo el resto del PDF y todo el repo del profe son de **64 bits**
> (System V AMD64 ABI). Son un arrastre de la versión vieja del TP, cuando se hacía en
> 32 bits. **No instalarlos**: en Ubuntu 24.04 suelen romper dependencias y no hacen
> falta para nada de lo que pide este TP. Está anotado en el Anexo B para preguntarle
> al profe y que quede por escrito.

### Listo cuando

Los cinco comandos de verificación responden sin error y `uname -m` dice `x86_64`.

---

## Etapa 1 — Dominar el hello world del profe

**Se puede hacer hoy.** Es exactamente lo único que vieron hasta ahora.

Material: <https://gitlab.com/nicoborsottib/stackframe> — carpeta `asm hello world`.

Este ejemplo **no es el TP**. Es el laboratorio donde se aprende la mecánica que
después se aplica al TP: cómo se escribe una función en ASM, cómo se arma y se
destruye su stack frame, y cómo se lo mira con GDB. Todo lo de la Etapa 8 es este
ejemplo con otro cuerpo de función.

> El README de esa carpeta tiene pasos que faltan y un par de contradicciones. Están
> todas listadas y resueltas en el **Anexo A**. Conviene leer el Anexo A antes de
> empezar, para no perder tiempo con errores que ya están identificados.

### 1.1 Clonar y compilar

```bash
git clone https://gitlab.com/nicoborsottib/stackframe.git
cd stackframe/"asm hello world"      # ← este cd el README no lo dice

as -g --gdwarf-2 -o program.o program.s
ld -o program program.o
./program; echo $?
```

Tiene que imprimir **30**. No imprime nada más: el programa no usa `printf`, termina
con la syscall `exit` y el resultado de la suma es el código de salida. Por eso el
`echo $?`.

Verificado: con `as` 2.42 / `ld` 2.42 en Ubuntu 24.04 esto compila y da 30 sin tocar nada.

### 1.2 Entender qué hace `program.s`

Son 30 líneas y vale la pena leerlas enteras, porque son el molde de todo lo que sigue.

```asm
calc_sum:
    pushq %rbp              # PRÓLOGO: guarda el frame del que llamó
    movq  %rsp, %rbp        #          arma el frame propio
    subq  $16, %rsp         #          reserva 16 bytes para 2 variables locales

    movq %rdi, -8(%rbp)     # guarda el 1er argumento como variable local
    movq %rsi, -16(%rbp)    # guarda el 2do argumento como variable local

    movq -8(%rbp), %rax     # CUERPO: rax = a
    addq -16(%rbp), %rax    #         rax = a + b

    movq %rbp, %rsp         # EPÍLOGO: tira las locales
    popq %rbp               #          restaura el frame del llamador
    ret                     #          vuelve
```

Tres cosas para retener:

- **El prólogo y el epílogo son simétricos.** Lo que el prólogo apila, el epílogo lo
  desapila, en orden inverso. Si se rompe esa simetría, el `ret` salta a cualquier lado
  y el programa se cae.
- **Las variables locales viven en offsets negativos** desde `%rbp` (`-8`, `-16`).
- **`ret` no es magia:** saca de la pila la dirección que `call` había puesto ahí, y
  salta a esa dirección. Si algo pisó esa posición del stack, `ret` salta al vacío.

### 1.3 Correrlo en GDB

Esta es la parte que más conviene practicar, porque es literalmente lo que hay que
mostrar en la defensa.

```bash
gdb ./program
```

Y adentro:

```
break _start
break calc_sum
run

info registers rsp rbp rip     # estado inicial

stepi                          # movq $10, %rdi
stepi                          # movq $20, %rsi
x/1gx $rsp                     # la cima del stack, TODAVÍA sin la dirección de retorno

stepi                          # call calc_sum  → acá entra a la función
x/1gx $rsp                     # AHORA sí: esto es la dirección de retorno
disassemble _start             # comparar: tiene que coincidir con la línea de _start+19

stepi                          # pushq %rbp
stepi                          # movq %rsp, %rbp
stepi                          # subq $16, %rsp
x/4gx $rsp                     # el frame ya armado, vacío
info registers rsp rbp

stepi                          # movq %rdi, -8(%rbp)
stepi                          # movq %rsi, -16(%rbp)
x/4gx $rsp                     # el frame con los datos adentro

quit
```

**Cómo se lee `x/4gx $rsp`:** examinar (`x`) 4 elementos de 8 bytes (`g`, de *giant
word*) en hexadecimal (`x`), arrancando desde donde apunta `%rsp`.

Después del prólogo, esas 4 posiciones son, de abajo hacia arriba:

| Posición | Equivale a | Qué hay |
|---|---|---|
| `$rsp + 0`  | `-16(%rbp)` | variable local `b` |
| `$rsp + 8`  | `-8(%rbp)`  | variable local `a` |
| `$rsp + 16` | `0(%rbp)`   | el `%rbp` viejo, el de `_start` |
| `$rsp + 24` | `8(%rbp)`   | la dirección de retorno |

Verificado corriendo la sesión completa: después de los dos `stepi` finales aparecen
`0x14` (20) y `0xa` (10) en las dos primeras posiciones, y la dirección de retorno
coincide exactamente con `_start+19` del `disassemble`. La secuencia del README es
correcta en este punto.

### 1.4 gdb-dashboard (opcional pero muy recomendable)

Es un `.gdbinit` que muestra registros, stack y desensamblado en simultáneo mientras se
debuggea, en vez de tener que pedir cada cosa a mano. Para el TP no es obligatorio,
pero las capturas quedan mucho más claras y el profe lo pide en mayúsculas en el PDF
("USAR GDB DASHBOARD !").

**Instalarlo en el home** — es el método que funciona sin pasos extra:

```bash
wget -P ~ https://github.com/cyrus-and/gdb-dashboard/raw/master/.gdbinit
```

> El repo trae un `setup.sh` que lo copia en la carpeta del proyecto en lugar del home.
> **Ese método no funciona tal cual está**: GDB se niega a auto-cargar un `.gdbinit`
> que esté en el directorio actual, por seguridad. El detalle y el arreglo están en el
> Anexo A, punto A2.

Si aparece un aviso sobre Pygments, es solo el coloreado de sintaxis: `pip install pygments`.

### Listo cuando

- `./program; echo $?` devuelve 30.
- Se puede correr la sesión de GDB entera **sin mirar el README**, explicando en voz
  alta qué pasa en cada `stepi`.
- Se sabe señalar, en la salida de `x/4gx $rsp`, cuál de los cuatro valores es la
  dirección de retorno y por qué.

Este último punto es el que hay que poder hacer en la defensa. Vale la pena que los
tres lo practiquen por separado.

---

## Etapa 2 — Anatomía del stack frame

**Se puede hacer hoy.** Es teoría, pero es la que hace falta para entender el R6, que es
el requisito central del TP.

### Lo mínimo indispensable

El stack es una región de RAM que funciona como una pila: LIFO. Cada vez que se llama a
una función, se crea ahí un bloque nuevo, el **stack frame**, que contiene las variables
locales de la función, la dirección de retorno y el estado previo de los registros.

**En x86-64 el stack crece hacia direcciones más bajas.** Cada `push` le resta 8 a
`%rsp`; cada `pop` le suma 8. Es contraintuitivo al principio: "crecer" significa que el
número de la dirección se hace más chico.

Los dos registros que importan:

- **`%rsp`** — *stack pointer*. Apunta siempre a la cima actual de la pila. Se mueve todo el tiempo.
- **`%rbp`** — *base pointer*. Es el ancla fija del frame actual. Como `%rsp` se mueve,
  usarlo de referencia sería un infierno; por eso todo se direcciona respecto de `%rbp`.

### El mapa que hay que saber de memoria

```
    direcciones ALTAS
    ┌─────────────────────────┐
24(%rbp) │  8vo argumento          │  ← lo empujó el que llamó
16(%rbp) │  7mo argumento          │  ← lo empujó el que llamó
 8(%rbp) │  dirección de retorno   │  ← la puso la instrucción call
 0(%rbp) │  %rbp anterior          │  ← lo guardó el push %rbp del prólogo
-8(%rbp) │  variable local 1       │  ← reservada con sub $N,%rsp
-16(%rbp)│  variable local 2       │
    └─────────────────────────┘
    direcciones BAJAS   ← acá apunta %rsp
```

**La regla:** offsets **positivos** desde `%rbp` son cosas que puso el llamador (los
argumentos que no entraron en registros). Offsets **negativos** son cosas de la función
actual (sus variables locales). La frontera es el `%rbp` guardado.

### La convención de llamadas System V AMD64

Es el contrato que Linux x86-64 obliga a respetar para que dos funciones compiladas por
separado puedan hablarse. Lo que hay que saber:

| Registro | Rol |
|---|---|
| `%rdi` | 1er argumento |
| `%rsi` | 2do argumento |
| `%rdx` | 3er argumento |
| `%rcx` | 4to argumento |
| `%r8`  | 5to argumento |
| `%r9`  | 6to argumento |
| `%rax` | **valor de retorno** |
| `%xmm0`–`%xmm7` | argumentos de punto flotante |

**Regla de oro:** los primeros 6 argumentos enteros o punteros van por registros, en ese
orden exacto. **Del séptimo en adelante van por el stack**, empujados por el llamador
antes del `call`. El valor de retorno siempre vuelve en `%rax`.

### Por qué esto es el corazón del TP

El R6 dice: *"Se debe utilizar el stack para enviar parámetros y devolver resultados"*.

Es decir: el TP pide deliberadamente **no** usar el camino cómodo de los registros. Hay
dos formas de forzar el paso por stack, y las dos están ejemplificadas en el repo del profe:

- **`suma_por_pila.s`** — declarar la función con 8 parámetros. Los 6 primeros se pasan
  en cero y se ignoran; el 7mo y el 8vo, por la ABI, el compilador los tiene que empujar
  al stack solo. La función los lee en `16(%rbp)` y `24(%rbp)`. Es el camino honesto: se
  respeta la ABI y el stack se usa porque la ABI así lo manda.
- **`suma2.s` + el asm inline de `main2.c`** — empujar los argumentos a mano con `pushq`
  desde C, emulando la vieja convención `cdecl` de 32 bits. Es más explícito
  visualmente, pero el asm inline de `main2.c` tiene una fragilidad (Anexo A, punto A7).

**Recomendación:** usar el enfoque de `suma_por_pila.s`. Es el que no depende de trucos,
el que se explica solo en la defensa, y el que el PDF ilustra en sus páginas 14 a 18.
La decisión definitiva se toma en la Etapa 7, cuando ya se haya visto ensamblador en clase.

### Para leer

- Capítulos 1 a 4 de `pcasm-book-spanish.pdf` (Paul A. Carter) — el PDF los marca como
  **lectura obligatoria**. Los ejemplos del Cap. 4 son los que hay que compilar y debuggear.
- <https://eli.thegreenplace.net/2011/09/06/stack-frame-layout-on-x86-64> — el link que
  da el propio PDF. Es corto y tiene los diagramas.
- El README raíz del repo `stackframe`, sección "Anatomía de un frame típico".

### Listo cuando

Se puede dibujar el mapa del frame en un papel, de memoria, y explicar por qué el 7mo
argumento está en `16(%rbp)` y no en `8(%rbp)`.

---

## Etapa 3 — Repo y flujo de trabajo grupal

**Se puede hacer hoy.** El PDF es muy específico con esto (R10, R11) y es de lo más fácil
de perder puntos por no hacerlo desde el principio.

### Lo que pide el PDF

- Repositorio en GitHub, **cuenta privada**.
- Un **responsable** designado, con **email institucional**.
- Cada uno de los otros integrantes tiene un **fork** del repo del responsable.
- Todos los repositorios sincronizados.
- Los que no son el responsable **entregan por pull request**.
- **Un commit brevemente comentado por cada funcionalidad implementada y validada.**

Ojo con ese último: "implementada **y validada**". Un commit por cosa que anda, no un
commit gigante al final. Es la evidencia de proceso y el profe la va a mirar.

> En el TP1 ya usaron exactamente este esquema (forks personales integrados al repo
> principal por PR). Es el mismo flujo, no hay nada nuevo que aprender.

### Pasos

1. **Definir el responsable** y que cree el repo privado con su mail institucional.
   Este repo, `practico-2`, puede ser ese, o el espejo personal si el responsable es otro.
2. Los otros dos hacen **fork** y agregan el upstream:
   ```bash
   git clone https://github.com/<responsable>/practico-2.git
   cd practico-2
   git remote add upstream https://github.com/<responsable>/practico-2.git
   ```
3. Antes de empezar cualquier cosa, sincronizar:
   ```bash
   git fetch upstream && git merge upstream/main
   ```
4. Trabajar en rama, nunca directo sobre `main`:
   ```bash
   git checkout -b feature/<lo-que-sea>
   ```
5. Push al fork propio y abrir el PR contra el repo del responsable.

### Estructura de carpetas propuesta

```
practico-2/
├── CONSIGNA.md              ← este documento
├── README.md                ← el informe del TP
├── iteracion1/
│   ├── python/              ← cliente de la API REST
│   └── c/                   ← capa intermedia, sin ASM
├── iteracion2/
│   ├── python/
│   ├── c/
│   └── asm/                 ← las rutinas .s
├── gdb/                     ← capturas y logs de las sesiones
│   ├── iteracion1/
│   └── iteracion2/
├── docs/
│   ├── diagramas/
│   └── casos-de-prueba/
└── Makefile
```

Separar `iteracion1/` de `iteracion2/` en vez de pisar la primera: el PDF pide las dos
iteraciones, y tenerlas lado a lado deja mostrar la evolución en la defensa y habilita
gratis la comparación de performance de la Etapa 9.

### Listo cuando

El repo existe, es privado, los tres tienen acceso, los dos no-responsables tienen su
fork con el upstream configurado, y hay al menos un PR de prueba abierto y mergeado para
confirmar que el circuito funciona. Mejor descubrir ahora que el circuito está roto que
la noche antes de entregar.

---

## Etapa 4 — Python: bajar el GINI de la API

**Necesita:** nada de ensamblador. Solo Python y la noción de JSON que ya vieron.
Arranca la **iteración 1**.

### Qué es una API REST, en tres líneas

Una API REST es una URL a la que se le hace una consulta por HTTP y responde con datos
estructurados, normalmente en JSON. Es un contrato: el que consume manda ciertos
parámetros, y el que provee devuelve una respuesta con una forma conocida y estable.
Nada más que eso.

### La URL del PDF

```
https://api.worldbank.org/v2/en/country/all/indicator/SI.POV.GINI?format=json&date=2011:2020&per_page=32500&page=1&country=%22Argentina%22
```

Desarmada:

| Parte | Qué hace |
|---|---|
| `/v2/en/` | versión 2 de la API, respuestas en inglés |
| `/country/all/` | **todos** los países |
| `/indicator/SI.POV.GINI` | el indicador: índice de Gini |
| `format=json` | respuesta en JSON |
| `date=2011:2020` | rango de años |
| `per_page=32500` | traer todo en una sola página |

> **Verificar esto antes de construir encima.** El parámetro `&country="Argentina"` del
> final es sospechoso: en la API del Banco Mundial el país va **en el path**, no como
> query param, y el path acá dice `/country/all/`. Lo más probable es que ese parámetro
> se ignore y la respuesta traiga **todos los países**, no solo Argentina — en cuyo caso
> hay que filtrar Argentina del lado de Python, o cambiar el path a `/country/ARG/`.
>
> **No pude confirmarlo**: el entorno donde armé este documento tiene bloqueada la
> salida a `api.worldbank.org`. Es el primer paso de la etapa, y es de dos minutos.

### 4.1 Probar la URL a mano, antes de escribir código

```bash
curl 'https://api.worldbank.org/v2/en/country/all/indicator/SI.POV.GINI?format=json&date=2011:2020&per_page=32500&page=1' | head -c 2000
```

Y comparar con la variante con el país en el path:

```bash
curl 'https://api.worldbank.org/v2/en/country/ARG/indicator/SI.POV.GINI?format=json&date=2011:2020&per_page=100'
```

Si la segunda trae solo Argentina y es mucho más chica, esa es la buena. Anotar cuál se
usó y por qué: es material para el informe.

### 4.2 Entender la forma de la respuesta

La API del Banco Mundial devuelve un **array de dos elementos**:

- `[0]` → metadatos: paginación, cantidad total de resultados.
- `[1]` → el array de datos, un objeto por país y año.

Cada objeto de datos tiene, entre otros campos:

```json
{
  "indicator": { "id": "SI.POV.GINI", "value": "Gini index" },
  "country":   { "id": "AR", "value": "Argentina" },
  "date": "2020",
  "value": 42.3
}
```

**Lo importante para las etapas que siguen:** `value` es un **float**, y **puede venir
`null`** para los años sin dato. Ese `null` es la trampa clásica de este TP — si no se
filtra, revienta la capa de C con un dato basura. Hay que decidir ya qué se hace con los
años sin dato: descartarlos, o mandarlos como un centinela acordado.

### 4.3 El script

```bash
pip install requests
```

Lo que tiene que hacer, en orden:

1. Hacer el GET a la URL.
2. Verificar el status code (que sea 200) antes de tocar el body.
3. Parsear el JSON y quedarse con el elemento `[1]`.
4. Filtrar Argentina si la respuesta trae todos los países.
5. Descartar los registros con `value` en `null`.
6. Dejar una lista de pares `(año, valor_float)` ordenada por año.
7. Imprimirla, para poder verificar a ojo que los datos tienen sentido.

Un índice de Gini es un número entre 0 y 100. Si sale algo fuera de ese rango, está mal
el parseo.

### Listo cuando

El script imprime la serie de valores GINI de Argentina, año por año, sin `null` y sin
crashear. Commit: `feat(python): cliente REST para índice GINI del Banco Mundial`.

---

## Etapa 5 — C: recibir los datos y calcular

**Necesita:** la Etapa 4 andando. Sigue la **iteración 1**: acá **no va ensamblador**.

El PDF es explícito: *"En una primera iteración resolverán todo el trabajo práctico
usando c con python sin ensamblador."*

Por eso esta etapa hace en C, con funciones normales, exactamente lo que en la Etapa 7
va a hacer el ensamblador. Cuando llegue la iteración 2, esas funciones de C se
reemplazan una por una por su versión en ASM, y como el comportamiento correcto ya está
establecido, cualquier diferencia de resultado señala un bug en el ASM. Es una red de
seguridad, no trabajo duplicado.

### 5.1 Decidir cómo se comunican Python y C

**Esta decisión se puede postergar.** Depende de temas que todavía no vieron, y ninguna
de las opciones bloquea el avance: se puede escribir toda la lógica de C primero,
probarla con datos hardcodeados, y recién después conectarla con Python.

Las tres opciones, para cuando toque decidir:

| Opción | Cómo funciona | A favor | En contra |
|---|---|---|---|
| **ctypes + `.so`** | C se compila como librería compartida y Python la llama directo | Es el método que muestra el PDF (páginas 4–5); la integración entre capas es real | Hay que declarar `argtypes` y `restype` bien, sobre todo con floats |
| **subprocess** | Python le pasa los datos al ejecutable de C por stdin o argv y lee stdout | Lo más simple; el binario de C corre solo, ideal para GDB | La integración es más pobre, se pasa todo como texto |
| **libcurl en C** | C consume la API directo, sin Python | Menos capas | Se pierde el plus de Python y la comparativa de performance |

**Recomendación tentativa:** `ctypes`, porque es el que el PDF desarrolla y el que mejor
muestra la convención de llamadas — que es de lo que trata la materia. Y aparte, un
`main.c` standalone con datos fijos para la demo de GDB; el PDF lo sugiere textualmente:
*"para ello pueden usar un programa de C puro"*. Con ctypes, GDB tiene que arrancar el
intérprete de Python y eso complica la sesión al pedo.

Confirmar cuando vean ctypes o linkeo en clase.

### 5.2 Qué tiene que hacer la capa de C

Las funciones que en la Etapa 7 pasan a ser ensamblador:

1. **Conversión float → entero.** Recibe el valor GINI (ej. `42.3`) y devuelve un
   entero. **Definir el criterio y escribirlo**: ¿truncar (42) o redondear (42)? ¿Se
   multiplica por 10 o por 100 antes, para no perder los decimales? El PDF no lo aclara.
   Sea cual sea la decisión, hay que documentarla — en la defensa la van a preguntar.
2. **Sumar uno (+1).** El R4: *"devuelva el índice de un país como Argentina u otro
   sumando uno (+1)"*. Es literalmente sumar 1 al resultado. La redacción del PDF es
   ambigua (¿+1 al índice, o al año, o al valor convertido?). Está en el Anexo B para
   preguntar; mientras tanto, asumir +1 al valor convertido, que es la lectura directa.
3. **Mostrar los datos** (R5).

### 5.3 Escribirlas pensando en el paso a ASM

Si la firma de estas funciones se diseña ahora como va a ser en ASM, después el cambio
es solo reemplazar el `.c` por el `.s` y relinkear. Concretamente: tipos simples
(`long`, `double`), sin structs, sin punteros a struct, un solo valor de retorno.

### 5.4 Compilar SIEMPRE con símbolos de debug

```bash
gcc -g3 -O0 -c -o main.o main.c
```

- **`-g3`** — máxima información de depuración. El PDF lo pide explícitamente:
  *"en gcc, compilar con -g o preferentemente -g3"*.
- **`-O0`** — sin optimizaciones. **Esto no es opcional.** Con optimizaciones, el
  compilador reordena instrucciones, mete variables en registros y directamente puede
  borrar el prólogo del stack frame. La sesión de GDB no coincidiría con el código
  fuente y no se podría mostrar nada.

Conviene armar el `Makefile` ya en esta etapa, con estos flags fijos, para que nadie se
olvide después.

### Listo cuando

El programa en C toma los datos GINI, los convierte, les suma 1 y los muestra. Sin ASM
todavía. Commit: `feat(c): capa intermedia con cálculo de índice - iteración 1`.

---

## Etapa 6 — Punto de control: GDB sobre C puro

**Necesita:** la Etapa 5 andando.

Cierre de la iteración 1. Todavía no hay ensamblador, y justamente por eso esta etapa
sirve: se aprende a debuggear con GDB sobre código que ya funciona y que se entiende.
Cuando en la Etapa 8 haya que hacerlo sobre ASM, lo único nuevo va a ser el ASM.

### Qué mirar

Poner un breakpoint en la llamada a la función de conversión y recorrer:

```
break main.c:<línea de la llamada>
run
disassemble main          # ver cómo GCC prepara los argumentos: %rdi, %rsi, %xmm0...
info registers rdi rsi rax
x/8gx $rsp
stepi                     # hasta entrar a la función
bt                        # backtrace: la cadena de frames
info frame                # resumen del frame actual
```

El ejercicio útil acá es **comparar lo que hace GCC con lo que dice la teoría de la
Etapa 2**: ver con los propios ojos que el primer argumento efectivamente aparece en
`%rdi`, que el retorno vuelve en `%rax`, que el prólogo es `push %rbp; mov %rsp,%rbp`.

Si se pasa un `double`, aparece en `%xmm0`, no en `%rdi` — los floats van por los
registros vectoriales. Es una diferencia importante y es muy probable que la pregunten
en la defensa, porque este TP justamente convierte floats.

### Comandos de GDB para tener a mano

| Comando | Qué hace |
|---|---|
| `info registers` | todos los registros de propósito general |
| `info registers rdi rsi rax` | solo esos |
| `print $rax` | el valor de un registro |
| `x/1gx $rsp` | 1 quadword (8 bytes) en hex desde la cima del stack |
| `x/4gx $rsp` | 4 quadwords — el frame completo |
| `x/20xw $rsp` | 20 words de 4 bytes |
| `disassemble <func>` | el assembly de una función |
| `stepi` (`si`) | avanza **una instrucción** de assembly |
| `nexti` (`ni`) | ídem, pero sin entrar a las funciones |
| `backtrace` (`bt`) | la cadena de llamadas |
| `info frame` | resumen del frame actual |
| `layout regs` / `layout asm` | modo TUI: registros / assembly en vivo |

La diferencia entre `step` y `stepi` es clave: `step` avanza una **línea de C**, `stepi`
avanza **una instrucción de máquina**. Para ver cómo se arma un stack frame hace falta
`stepi`, porque el prólogo entero es una sola línea de C.

### Listo cuando

Se puede recorrer el programa de C instrucción por instrucción, mostrar dónde están los
argumentos y explicar el prólogo. Guardar capturas en `gdb/iteracion1/`.

Commit: `docs(gdb): sesión de depuración sobre la iteración 1`.

**Acá termina la iteración 1.** Buen momento para un tag: `git tag iteracion-1`.

---

## Etapa 7 — ASM: float → int, +1, todo por el stack

**Necesita:** haber visto ensamblador en clase, la Etapa 2 entendida y la Etapa 5 andando.
Arranca la **iteración 2**.

Esta es la etapa central del TP. Todo lo anterior es andamiaje.

### 7.1 Confirmar la estrategia de paso por stack

Volver a la Etapa 2, sección "Por qué esto es el corazón del TP", y decidir entre
`suma_por_pila` (declarar 8 parámetros y dejar que la ABI empuje el 7mo y el 8vo) o el
`pushq` manual con asm inline. La recomendación sigue siendo la primera.

### 7.2 Escribir las rutinas

Molde, tomado de `suma_por_pila.s` del repo del profe:

```asm
    .section .text
    .globl  mi_funcion
    .type   mi_funcion, @function

mi_funcion:
    pushq   %rbp             # PRÓLOGO
    movq    %rsp, %rbp

    # Mapa de la pila visto desde %rbp:
    #   24(%rbp) -> 8vo parámetro
    #   16(%rbp) -> 7mo parámetro
    #    8(%rbp) -> dirección de retorno (la puso call)
    #    0(%rbp) -> %rbp original (lo puso el pushq de arriba)

    movq    16(%rbp), %rax   # CUERPO: leer del stack, no de los registros
    # ... el cálculo ...

    popq    %rbp             # EPÍLOGO
    ret                      # el resultado ya está en %rax

    .size   mi_funcion, .-mi_funcion
    .section .note.GNU-stack,"",@progbits    # ← evita el warning de stack ejecutable
```

Esa última línea no está en los archivos del profe y por eso el linker tira
`missing .note.GNU-stack section implies executable stack` (Anexo A, punto A6).
Es una línea y saca el warning.

### 7.3 El punto difícil: convertir float a entero en ASM

Es lo más complejo del TP y conviene encararlo aparte, con un programa mínimo, antes de
meterlo en la app.

Lo que hay que saber:

- Los `double` **no viven en los registros de propósito general**. Viven en los registros
  `%xmm0`–`%xmm15`, que son otra cosa.
- La instrucción que convierte es **`cvttsd2si`** (*convert with truncation scalar
  double to signed integer*): toma un `double` de un `%xmm` y deja el entero truncado en
  un registro normal. La doble `t` es de *truncation* — trunca, no redondea.
  Si se quiere redondeo, es `cvtsd2si`.
- Si el valor viene por el **stack** en vez de por `%xmm0`, hay que cargarlo primero con
  `movsd 16(%rbp), %xmm0` y después convertir.

Táctica recomendada: escribir un `main.c` de diez líneas que llame a una función ASM que
solo convierta un `double` fijo a entero y lo devuelva. Cuando eso ande, recién ahí
integrarlo.

### 7.4 Compilar y linkear

```bash
as --64 -g -o rutina.o rutina.s        # --64: modo 64 bits | -g: símbolos de debug
gcc -g3 -O0 -c -o main.o main.c
gcc -o programa main.o rutina.o        # gcc como frontend del linker (resuelve libc)
```

Verificar que el símbolo se exportó:

```bash
nm rutina.o | grep mi_funcion          # tiene que aparecer con "T" = código en .text
```

Si aparece con `U` en vez de `T`, el símbolo está *undefined*: falta el `.globl`.

> El README del profe omite el `-g` en el `as` y el `-g3 -O0` en el `gcc`. Sin eso, GDB
> no muestra el fuente y el ejercicio se vuelve mucho más difícil. Anexo A, punto A5.

### 7.5 Validar contra la iteración 1

La red de seguridad de la Etapa 5: correr los dos programas con los mismos datos de
entrada y comparar salidas. Si difieren, el ASM tiene un bug. Si coinciden en toda la
serie, el ASM está bien.

### Listo cuando

La app corre con las rutinas en ASM y da exactamente los mismos números que la iteración 1.

Commits separados, uno por rutina: `feat(asm): conversión float a entero por stack`,
`feat(asm): suma de 1 al índice`.

---

## Etapa 8 — La demo de GDB

**Necesita:** la Etapa 7 andando.

Este es el R9 y es el requisito que más pesa. El PDF:

> *"IMPORTANTE: en esta segunda iteración deberán mostrar los resultados con gdb...
> Cuando depuren muestran el estado del área de memoria que contiene el stack **antes,
> durante y después** de la función."*

No alcanza con que el programa ande. Hay que **mostrar el stack en tres momentos**.

### El guion de los tres momentos

Es la sesión de la Etapa 1.3, con la función del TP en lugar de `calc_sum`.

**ANTES — parado en `main`, justo antes del `call`:**

```
break <archivo.c>:<línea de la llamada>
run
info registers rsp rbp
x/8gx $rsp
disassemble main
```

Qué mostrar: dónde está `%rsp`, cómo el llamador empuja los argumentos que van por
stack (`pushq`), y que la dirección de retorno **todavía no está**.

**DURANTE — adentro de la función, después del prólogo:**

```
stepi          # hasta pasar el call
x/1gx $rsp     # la dirección de retorno recién puesta por call
stepi          # pushq %rbp
stepi          # movq %rsp, %rbp
x/4gx $rsp
info registers rsp rbp
```

Qué mostrar: que `%rsp` bajó 8 bytes por el `call`, que en la cima está la dirección de
retorno, que el prólogo guardó el `%rbp` de `main`, y **que los argumentos se leen en
`16(%rbp)` y `24(%rbp)`** — que es exactamente la prueba de que se están pasando por el
stack. Este es *el* momento del TP.

**DESPUÉS — vuelta en `main`:**

```
stepi          # popq %rbp
stepi          # ret
info registers rsp rbp rax
x/8gx $rsp
```

Qué mostrar: que `%rsp` y `%rbp` volvieron exactamente a los valores de "antes", que el
frame se destruyó, y que el resultado está en `%rax`.

### Cómo documentarlo

Dos formas, y conviene hacer las dos:

1. **Capturas de pantalla** de cada momento, en `gdb/iteracion2/`, numeradas.
   Con gdb-dashboard quedan mucho más claras.
2. **Log de texto**, que se puede citar en el informe:
   ```bash
   gdb -batch -x sesion.gdb ./programa > gdb/iteracion2/sesion.txt 2>&1
   ```
   donde `sesion.gdb` es un archivo con los comandos, uno por línea.

Para cada captura, una línea de texto explicando **qué se está mirando y por qué
importa**. Una captura sin explicación no prueba que se entendió.

### Listo cuando

Existen los tres momentos documentados, y cualquiera de los tres puede pararse frente al
profe, señalar una dirección de memoria en la captura y decir qué hay ahí y quién la puso.

Commit: `docs(gdb): stack antes, durante y después de la rutina ASM`.

---

## Etapa 9 — Plus opcionales

Todo esto el PDF lo marca como "bienvenido" o "un plus". Ordenado por relación
esfuerzo/beneficio, considerando lo que ya hicieron en el TP1:

| Plus | Esfuerzo | Por qué conviene |
|---|---|---|
| **Diagrama de bloques** de las 3 capas | bajo | Explica el TP en una imagen. Casi obligatorio para la defensa |
| **Diagrama de secuencia** de una llamada | bajo | Muestra el viaje del dato Python → C → ASM → C → Python |
| **Casos de prueba** | medio | Cubrir: años sin dato (`null`), valores límite, la conversión float→int. Es donde están los bugs reales |
| **Performance C vs Python** | medio | Sale casi gratis teniendo las dos iteraciones separadas. Y ya tienen experiencia del TP1 |
| **Profiling de la app de C** | medio | El PDF lo llama "un plus" explícitamente. Ya dominan `gprof` y `perf` del TP1 — es reutilización directa |

El profiling es el de mejor relación esfuerzo/beneficio de la lista: es exactamente el
punto 4 del TP1 (`-pg`, `gprof`, `analysis.txt`, `gprof2dot`, y `perf` como contraste),
aplicado a otro binario.

---

## Etapa 10 — Informe y defensa

### El informe

Mismo formato que el TP1, que funcionó bien. Estructura sugerida:

1. Introducción y objetivos
2. Arquitectura de la solución (acá va el diagrama de bloques)
3. Iteración 1: Python + C
4. Iteración 2: incorporación de ensamblador
5. Convención de llamadas y paso por stack — **el núcleo técnico**
6. Depuración con GDB: antes, durante y después (las capturas de la Etapa 8)
7. Casos de prueba
8. Plus: performance y profiling
9. Conclusiones
10. Link al repositorio

### La defensa es grupal

El PDF lo dice y en el TP1 ya lo vivieron. Implica que **cualquiera puede tener que
explicar cualquier parte**. Lo que conviene repartir no es el trabajo, es el
entendimiento.

Preguntas probables, que salen de lo que el propio PDF enfatiza:

- ¿Por qué el 7mo argumento está en `16(%rbp)` y no en `8(%rbp)`?
- ¿Qué pasa si no se hace el `popq %rbp` en el epílogo?
- ¿Por qué el stack crece hacia direcciones más bajas?
- ¿Dónde está la dirección de retorno y quién la puso ahí?
- ¿Por qué un `double` no viaja en `%rdi`?
- ¿Por qué compilar con `-O0`? ¿Qué pasaría con `-O2`?
- ¿Qué diferencia hay entre `stepi` y `step`?

Ninguna de esas se contesta leyendo el informe. Se contestan habiendo hecho la Etapa 1
en serio.

---

## Anexo A — Problemas del material del profe

Todo esto está verificado ejecutándolo en Ubuntu 24.04 x86-64, con `gcc` 13.3,
`as`/`ld` 2.42 y `gdb` 15.1.

**Lo primero, y es la buena noticia: el código del repo funciona.** Los tres ejemplos
compilan y dan el resultado correcto (30, 35 y 35). Los problemas son del README, no del
código. Pero son los que hacen perder la tarde.

### A1 — Falta el `cd` a la carpeta

El README de `asm hello world` arranca directamente con `as -g --gdwarf-2 -o program.o
program.s`, sin decir desde dónde. Hay que estar **adentro** de `asm hello world`. El
nombre de la carpeta tiene espacios, así que van comillas:

```bash
cd "asm hello world"
```

### A2 — `setup.sh` no funciona como está (el más molesto)

El README raíz dice: *"Ejecutar el instalador setup.sh para instalar gdbdashboard de
manera local en esta carpeta"*. `setup.sh` copia el `.gdbinit` al directorio del
proyecto. **GDB se niega a cargarlo**, por seguridad:

```
warning: File ".../.gdbinit" auto-loading has been declined by your
`auto-load safe-path' set to "$debugdir:$datadir/auto-load".
```

O sea: se ejecuta el setup, parece que salió bien, se abre GDB y no aparece el
dashboard. Sin saber esto se puede perder un buen rato.

**Dos arreglos.** El simple, que es el que conviene:

```bash
wget -P ~ https://github.com/cyrus-and/gdb-dashboard/raw/master/.gdbinit
```

En el home siempre se carga, sin permisos especiales. El otro, si se lo quiere local:

```bash
echo "add-auto-load-safe-path $(pwd)" >> ~/.config/gdb/gdbinit
```

### A3 — Dos métodos contradictorios para lo mismo

El README raíz recomienda `setup.sh` (local). El README de `asm hello world` recomienda
`wget -P ~` (home). Nunca dice que son alternativas, ni cuál usar. Y la que recomienda
primero es justamente la que no anda sola. **Usar la del home.**

### A4 — Se contradice sobre qué es un "half word"

En el mismo archivo:

> *"**Half Word** (Media Palabra): **8 bits** (1 byte)"*

y unas líneas más abajo:

> *"GDB usa `b` para bytes, `h` para half-words de **2 bytes**"*

Las dos afirmaciones no pueden ser ciertas a la vez. **La que importa para el TP es la
segunda**: en GDB, `h` = 2 bytes. Los tamaños de GDB son `b`=1, `h`=2, `w`=4, `g`=8 bytes.
Lo que se usa todo el tiempo en este TP es `g`, de *giant word*, 8 bytes — el tamaño de
un slot del stack en 64 bits.

(La primera afirmación viene de la terminología de Intel, donde *word* son 16 bits por
compatibilidad con el 8086, y ahí media palabra sí son 8 bits. Pero GDB no usa esa
convención, y mezclarlas lleva a leer mal la memoria.)

### A5 — Los comandos de compilación no llevan símbolos de debug

El README raíz:

```bash
as --64 -o suma.o suma.s
gcc -c main.c -o main.o
```

Ninguno de los dos tiene `-g`. Y el propio PDF de la cátedra dice *"compilar con -g o
preferentemente -g3"*. Sin eso, GDB no muestra el código fuente, solo desensamblado.
Dado que **todo el TP es debuggear**, esto hay que corregirlo siempre:

```bash
as --64 -g -o suma.o suma.s
gcc -g3 -O0 -c main.c -o main.o
```

El `-O0` tampoco está y es igual de importante: con optimizaciones el compilador puede
eliminar el prólogo del stack frame, y entonces no hay nada que mostrar.

### A6 — Warning de stack ejecutable en todos los `.s`

Al linkear cualquiera de los ejemplos con C:

```
/usr/bin/ld: warning: suma.o: missing .note.GNU-stack section implies executable stack
/usr/bin/ld: NOTE: This behaviour is deprecated and will be removed in a future version
```

No rompe nada hoy, pero el linker avisa que lo va a sacar. Se arregla agregando esta
línea al final de cada `.s`:

```asm
    .section .note.GNU-stack,"",@progbits
```

Conviene ponerla en las rutinas del TP desde el principio: una línea, y el build queda limpio.

### A7 — El asm inline de `main2.c` es frágil

El bloque `__asm__` de `main2.c` hace `pushq` de los argumentos y un `call`, pero en la
lista de *clobbers* solo declara `"memory"`. Un `call` pisa todos los registros
*caller-saved* (`%rax`, `%rcx`, `%rdx`, `%rsi`, `%rdi`, `%r8`–`%r11`), y GCC no está
siendo avisado de eso.

**Lo probé con `-O0`, `-O1`, `-O2` y `-O3`: anda en los cuatro.** Funciona porque GCC no
tiene nada vivo en esos registros justo en ese punto — pero es suerte, no garantía. Un
cambio menor en el código de alrededor puede romperlo, y el síntoma sería un resultado
incorrecto sin ningún error de compilación.

Es otra razón para preferir el enfoque de `suma_por_pila.s`, que no depende de asm inline.

### A8 — El README menciona un archivo que no existe

El README raíz dice:

> *"`stack_frames_presentation.pptx` — presentación de apoyo con la teoría de stack
> frames usada como base para estos ejemplos."*

Ese archivo **no está en el repo**. Verificado listando el árbol completo por la API de
GitLab. Si esa presentación existe, hay que pedírsela al profe (Anexo B).

### A9 — Detalles menores

- La numeración de secciones del README de `asm hello world` salta de **1** a **3**. No
  falta contenido, es solo el número.
- El README raíz tiene una frase de borrador sin limpiar: *"si querés, lo incorporo como
  sección 'Referencia rápida ABI' dentro del README..."*. No es una instrucción, es texto
  que quedó colgado.
- Hay dos archivos `.gdb_history` commiteados. Son historial de sesiones de GDB de otra
  persona, no aportan nada.

### Lo que SÍ está bien y conviene usar tal cual

- La secuencia de GDB del README de `asm hello world` es **correcta**. La corrí entera y
  cada `stepi` cae donde el README dice.
- El mapa de `x/4gx $rsp` después del prólogo es exacto: `[rsp+0]`=b, `[rsp+8]`=a,
  `[rsp+16]`=`%rbp` viejo, `[rsp+24]`=dirección de retorno. Verificado: aparecen `0x14`
  y `0xa`, y la dirección de retorno coincide con `_start+19` del `disassemble`.
- Los comentarios de `suma_por_pila.s` y `suma2.s` son la mejor documentación del repo, y
  son el molde directo para las rutinas del TP.

---

## Anexo B — Para preguntarle al profe

Conviene llevarlas juntas a la próxima clase. Son ambigüedades reales del enunciado, no
dudas de comprensión.

1. **El PDF dice "TP#1" pero es el TP2.** *"Para aprobar el TP#1 se debe diseñar e
   implementar una interfaz que muestre el índice GINI"* — el TP1 fue "Rendimiento".
   Confirmar que es solo el título arrastrado del documento viejo.

2. **32 vs 64 bits.** El PDF pide instalar `gcc-multilib g++-multilib` (librerías de 32
   bits), pero después dice *"Trabajaremos sobre una arquitectura X86_64"* y todo el
   material del repo es de 64 bits. ¿El TP se hace en 64 bits y lo del multilib es
   arrastre de la versión vieja?

3. **Qué significa exactamente el "+1".** *"devuelva el índice de un país como Argentina
   u otro sumando uno (+1)"*. ¿Se le suma 1 al valor GINI ya convertido a entero? ¿Al
   año? ¿Al índice del array? La lectura directa es la primera, pero conviene confirmarlo
   antes de construir encima.

4. **Criterio de conversión float → entero.** ¿Truncar o redondear? ¿Se multiplica por
   10 o 100 antes, para conservar decimales? El PDF solo dice *"cálculos de conversión de
   float a enteros"*.

5. **La URL de la API.** El path dice `/country/all/` y al final trae `&country="Argentina"`.
   ¿Es intencional que traiga todos los países y haya que filtrar Argentina en Python, o
   la URL debería ser `/country/ARG/`?

6. **Años sin dato.** El GINI de Argentina no está disponible para todos los años del
   rango 2011–2020; la API devuelve `null`. ¿Se descartan, o se espera algún manejo
   específico?

7. **`stack_frames_presentation.pptx`.** El README del repo la menciona pero no está
   subida. ¿Se puede conseguir?

---

## Checklist final

Antes de entregar, verificar contra los requisitos textuales del PDF:

- [ ] R1 · Python consume la API REST del Banco Mundial
- [ ] R2 · C recibe los datos de Python
- [ ] R3 · ASM hace la conversión float → entero
- [ ] R4 · Se devuelve el índice sumando uno (+1)
- [ ] R5 · Los datos se muestran desde C o Python
- [ ] R6 · **Los parámetros y el retorno pasan por el stack**
- [ ] R7 · La iteración 1 (sin ASM) está en el repo y anda
- [ ] R8 · La iteración 2 (con ASM) está en el repo y anda
- [ ] R9 · **Está documentado el stack antes, durante y después de la función en GDB**
- [ ] R10 · Repo privado, responsable con mail institucional, forks, PRs
- [ ] R11 · Un commit comentado por funcionalidad implementada y validada
- [ ] R12 · Los tres pueden explicar cualquier parte del TP

Opcionales:

- [ ] Casos de prueba
- [ ] Diagrama de bloques
- [ ] Diagrama de secuencia
- [ ] Comparación de performance C vs Python
- [ ] Profiling de la app de C

---

## Fuentes

- `TP_calculadora_de_indices_GINI.pdf` — enunciado de la cátedra (Solinas / Jorge)
- <https://gitlab.com/nicoborsottib/stackframe> — material práctico de stack frames
- <https://gitlab.com/sistemas-de-computacion-unc/stackframe> — repo original de la cátedra
- `pcasm-book-spanish.pdf` — Paul A. Carter, *Lenguaje Ensamblador para PC* (lectura obligatoria)
- <http://pacman128.github.io/pcasm/> — códigos fuente del libro
- <https://eli.thegreenplace.net/2011/09/06/stack-frame-layout-on-x86-64> — stack frame layout
- <https://github.com/cyrus-and/gdb-dashboard> — gdb-dashboard
