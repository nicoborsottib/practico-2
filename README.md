# Trabajo Práctico N°2

## Calculadora de índices GINI

**Convenciones de llamada entre lenguajes de alto y bajo nivel en x86-64**

---

**Universidad Nacional de Córdoba**
Facultad de Ciencias Exactas, Físicas y Naturales
Cátedra de Sistemas de Computación

**Profesor:** Ing. Javier Jorge

**Integrantes:**

- Nicolás Borsotti Bosco
- Santiago Valentín Ciacci
- Ignacio Ariel Leguizamón

---

## De qué se trata

El trabajo consiste en construir una aplicación de **tres capas** que obtenga y procese
el índice de Gini publicado por el Banco Mundial:

| Capa | Lenguaje | Responsabilidad |
|---|---|---|
| Superior | Python | Consultar la API REST del Banco Mundial y recuperar los datos |
| Intermedia | C | Recibir esos datos e invocar las rutinas de bajo nivel |
| Inferior | Ensamblador x86-64 | Convertir los valores de punto flotante a enteros y devolver el índice sumando uno |

La condición central del práctico es que el pasaje de parámetros y la devolución de
resultados entre la capa de C y la de ensamblador se realice **a través del stack**, es
decir, respetando las convenciones de llamada que utilizan los lenguajes de alto nivel
para comunicarse con los de bajo nivel. Entender ese mecanismo es lo que permite razonar
sobre la frontera entre software y hardware, y es conocimiento directamente aplicable a
sistemas críticos y a seguridad informática.

El desarrollo se organiza en dos iteraciones, tal como pide la consigna: en la primera
se resuelve el problema completo con Python y C, sin ensamblador; en la segunda se
incorporan las rutinas en ensamblador y se verifica su funcionamiento con el depurador
GDB, mostrando el estado del stack antes, durante y después de cada llamada.

## Organización del repositorio

```
practico-2/
├── README.md                    este documento
├── CONSIGNA.md                  hoja de ruta: la consigna traducida a etapas
├── GUIA.md                      stack frames desde cero y material del profesor reordenado
└── procedimiento/
    ├── PARTE1/                  stack frames en x86-64 con GDB
    └── PARTE2/                  argumentos por pila (7mo y 8vo parámetro)
```

| Documento | Para qué sirve |
|---|---|
| [`CONSIGNA.md`](CONSIGNA.md) | Qué pide el TP y en qué orden abordarlo: los requisitos desglosados y las diez etapas de trabajo |
| [`GUIA.md`](GUIA.md) | Material de estudio: la teoría de stack frames explicada desde cero y los ejemplos del profesor reordenados en secuencia |

Cada parte documenta lo realizado en su propio `README.md`, con las capturas de pantalla
que verifican los resultados obtenidos.

| Parte | Tema | Estado |
|---|---|---|
| [Parte 1](procedimiento/PARTE1/) | Anatomía del stack frame: prólogo, epílogo, dirección de retorno y paso de argumentos por registros | en curso |
| [Parte 2](procedimiento/PARTE2/) | Paso de argumentos por la pila cuando se superan los seis registros de la ABI | pendiente |

## Conclusiones

*A completar una vez finalizadas todas las partes.*
