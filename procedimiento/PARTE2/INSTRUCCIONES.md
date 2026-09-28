# Parte 2 — Instrucciones para quien la desarrolle

Este documento es el encargo de la Parte 2. Está escrito para que quien la tome —o el
asistente que lo acompañe— tenga todo el contexto sin necesidad de leer el historial del
grupo. La Parte 1 ya está hecha y documentada; **no hay que rehacerla**.

---

## Contexto del trabajo práctico

Materia: **Sistemas de Computación**, FCEFyN, UNC. Profesor: Ing. Javier Jorge.
Integrantes: Nicolás Borsotti Bosco, Santiago Valentín Ciacci, Ignacio Ariel Leguizamón.

El TP2 pide construir una aplicación de tres capas que muestre el índice de Gini del
Banco Mundial: **Python** consume la API REST, **C** recibe los datos e invoca rutinas en
**ensamblador x86-64** que convierten los valores de punto flotante a enteros y devuelven
el índice sumando uno.

La condición central del práctico es que **el pasaje de parámetros y la devolución de
resultados entre C y ensamblador se haga a través del stack**, no por registros. Antes de
poder cumplir eso hay que entender el mecanismo, y para eso está esta serie de partes
prácticas sobre el material de cátedra.

La hoja de ruta completa del TP, con sus diez etapas, está en `CONSIGNA.md` en la raíz
del repositorio. Conviene leerla para ubicar dónde encaja la Parte 2.

## Qué cubrió la Parte 1

Sobre el repositorio de cátedra
[`stackframe`](https://gitlab.com/nicoborsottib/stackframe):

- **`asm hello world/program.s`** — una función en ensamblador puro (`calc_sum`) que
  construye su propio marco de pila. Se verificó el prólogo, el epílogo, la ubicación de
  la dirección de retorno y la simetría de `%rsp` durante toda la llamada.
- **`main.c` + `suma.s`** — una función en ensamblador invocada desde C, con los
  argumentos viajando por **registros** (`%rdi`, `%rsi`) según la System V AMD64 ABI.

Conclusión principal: se comprobó que los primeros seis argumentos enteros van por
registros en orden fijo, que el valor de retorno vuelve en `%rax`, y que la dirección de
retorno es un dato concreto en memoria que deposita `call` y extrae `ret`.

El informe está en `procedimiento/PARTE1/README.md` y el procedimiento reproducible en
`procedimiento/PARTE1/guia.md`. **Vale la pena leer ambos antes de arrancar**: la Parte 2
es la continuación directa y conviene que el tono, la estructura y el nivel de detalle
sean consistentes.

## Qué tiene que cubrir la Parte 2

El caso en que los argumentos **no entran en los seis registros** que la ABI reserva para
ellos, y el compilador debe transferirlos **por la pila**. Es exactamente el mecanismo que
el TP necesita para cumplir su requisito central.

El material a analizar, en el mismo repositorio de cátedra:

- **`main2.c` + `suma_por_pila.s`** — una función declarada con **ocho** parámetros. Los
  seis primeros se pasan en cero y se ignoran; el séptimo y el octavo, por la ABI, el
  compilador los tiene que empujar a la pila. La función los lee en `16(%rbp)` y
  `24(%rbp)`.
- **`main2.c` + `suma2.s`** — la variante donde los argumentos se empujan **a mano** con
  ensamblador en línea desde C, emulando la vieja convención `cdecl` de 32 bits.

Preguntas que el informe debería poder responder, verificadas en GDB:

- ¿Cómo prepara el compilador una llamada con más de seis argumentos? ¿En qué orden
  coloca las cosas?
- ¿Por qué el séptimo argumento queda en `16(%rbp)` y no en `8(%rbp)`?
- ¿Quién limpia de la pila los argumentos una vez que la función retornó?
- ¿En qué se diferencia el marco de `suma_por_pila` del de `calc_sum` de la Parte 1?

Punto de atención: el ensamblador en línea de `main2.c` no declara en su lista de
*clobbers* los registros caller-saved que pisa el `call`. Funciona en la práctica, pero
es frágil por contrato — vale la pena mencionarlo si se opta por documentar esa variante.

## Convenciones del repositorio

Estructura a respetar:

```
practico-2/
├── README.md                     portada del informe (ya está hecha)
├── CONSIGNA.md                   hoja de ruta del TP
└── procedimiento/
    ├── PARTE1/
    │   ├── README.md             informe de la parte
    │   ├── guia.md               procedimiento reproducible
    │   ├── sesion-parteA.gdb     scripts de GDB
    │   ├── sesion-parteB.gdb
    │   └── capturas/             imágenes
    └── PARTE2/
        ├── README.md             ← a crear
        ├── guia.md               ← opcional, si sirve
        └── capturas/             ← a crear
```

Sobre las **capturas**: no hace falta capturar todo. Solo los puntos donde el resultado
se verifica y donde se prueba que el trabajo se hizo. Lo que es código o explicación
conceptual va en texto. En la Parte 1 quedaron ocho capturas sobre una sesión de
dieciséis pasos, y alcanza.

Nombres de archivo: dos dígitos, guiones, minúsculas, `.png`. Por ejemplo
`01-compilacion.png`, `02-argumentos-en-pila.png`. Referenciarlas desde el README con
`![Descripción](capturas/01-compilacion.png)` para que queden incrustadas.

Sobre el **tono**: el informe se redacta en tercera persona, formal, explicando qué se
observó y por qué importa — no solo qué comando se tipeó. Las conclusiones van al final
de la parte, numeradas.

## Tres cosas prácticas aprendidas en la Parte 1

Valen para no repetir tropiezos:

1. **Compilar siempre con símbolos de depuración.** `as --64 -g` y `gcc -g3 -O0`. El
   README del material de cátedra los omite; sin ellos GDB no muestra el código fuente y
   con optimizaciones el compilador puede directamente eliminar el prólogo del marco.

2. **En GDB, un comando por línea.** Pegar varias líneas de una vez hace que GDB tome el
   bloque entero como un solo argumento y falle con un error confuso. Para repetir una
   sesión completa conviene un script y correrlo con `gdb -x script.gdb ./binario`.

3. **El `setup.sh` de gdb-dashboard no funciona tal cual está.** Copia el `.gdbinit` a la
   carpeta del proyecto y GDB se niega a auto-cargarlo por seguridad. El método que sí
   anda es `wget -P ~ https://github.com/cyrus-and/gdb-dashboard/raw/master/.gdbinit`.

El `CONSIGNA.md` del repositorio tiene, en su Anexo A, la lista completa de problemas
detectados en el material de cátedra, todos verificados ejecutándolos.

## Sobre las direcciones de memoria

Al comparar resultados entre máquinas: las direcciones del **stack** (`0x7fffffffc...`)
dependen de las variables de entorno y de la ruta del binario, así que varían. Lo que se
mantiene son los **valores**, las direcciones de **código** de los binarios sin PIE, y las
**diferencias** entre direcciones — que son las que sostienen el análisis.
