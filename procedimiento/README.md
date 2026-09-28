# Procedimiento

Documentación del trabajo práctico, dividida por partes. Cada carpeta contiene el
informe de esa parte, el procedimiento reproducible y las capturas de pantalla que
respaldan lo afirmado.

| Parte | Contenido | Estado |
|---|---|---|
| [PARTE1](PARTE1/) | Stack frames en x86-64 con GDB: función en ASM puro y función en ASM invocada desde C | capturas pendientes |
| PARTE2 | Argumentos 7 y 8 por la pila (`main2.c` + `suma_por_pila.s`) | no iniciada |

## Estructura de cada parte

```
PARTEn/
├── README.md      informe: qué se hizo, qué se observó, qué se concluye
├── guia.md        procedimiento reproducible con comandos y salidas esperadas
└── capturas/      capturas de pantalla numeradas
```

## Convención para las capturas

Los archivos se nombran con dos dígitos y una descripción corta en minúsculas, separada
por guiones, y en formato `.png`:

```
01-compilacion.png
02-breakpoints.png
03-registros-iniciales.png
```

Los nombres ya están referenciados desde el `README.md` de cada parte, de modo que al
colocar los archivos en `capturas/` las imágenes quedan incrustadas en el informe
automáticamente.
