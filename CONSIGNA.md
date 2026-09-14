# TP #2 — Sistemas de Computación

## Consigna (texto del profesor)

> Para aprobar el TP#2 se debe diseñar e implementar cálculos en ensamblador. La capa
> superior recuperará información de una API REST. Se recomienda el uso de API Rest y
> Python. Los datos de consulta realizados deben ser entregados a un programa en C que
> convocará rutinas en ensamblador para que hagan los cálculos de conversión y devuelvan
> los resultados a las capas superiores. Luego el programa en C o Python mostrará los
> cálculos obtenidos.
>
> Se debe utilizar el stack para convocar, enviar parámetros y devolver resultados. O sea
> utilizar las convenciones de llamadas de lenguajes de alto nivel a bajo nivel.
>
> Las presentaciones de los trabajos se realizarán utilizando GitHub (una cuenta privada).
> Cada grupo debe asignar un responsable (con email institucional) como usuario de la
> cuenta de GitHub. Se debe realizar un commit brevemente comentado con cada funcionalidad
> implementada y validada.

## Material de apoyo

- Repo del profesor (GitLab): <https://gitlab.com/nicoborsottib/stackframe>
  - En particular la carpeta `asm hello world/`
  - Copia local ya clonada: `~/Escritorio/SdeComp/Gitlab/stackframe`
- Google Classroom: <https://classroom.google.com/c/ODcxNDAxMTY0NjQ3/a/ODcxNDAxMTY0Njcz/details>

> Ojo con no confundirte: **el material del profe está en GitLab, pero la entrega va en
> GitHub.** Son dos plataformas distintas y no tienen nada que ver entre sí.

## Qué pide en concreto (la consigna traducida a requisitos)

| # | Requisito | Cómo se cumple |
|---|---|---|
| R1 | Tres capas: Python → C → Assembler | Python consulta la API, se la pasa al binario de C, el C llama a la rutina `.s` |
| R2 | La capa superior consume una **API REST** | `requests` en Python contra una API pública |
| R3 | Los **cálculos de conversión** se hacen en ensamblador | La aritmética real vive en el `.s`, no en C ni en Python |
| R4 | El resultado vuelve **hacia arriba** | ASM → `%rax` → C → stdout → Python lo captura y lo muestra |
| R5 | Pasar parámetros **por el stack** | Al menos una rutina que lea sus argumentos desde `16(%rbp)`, `24(%rbp)`, … |
| R6 | Respetar las **convenciones de llamada** | Prólogo / cuerpo / epílogo, `%rax` como retorno, registros callee-saved intactos |
| R7 | Entrega en **GitHub, repo privado** | Responsable del grupo con email institucional |
| R8 | **Un commit por funcionalidad**, comentado | Nada de un único commit "todo el TP" al final |

### Detalles de R5 que son fáciles de pasar por alto

El punto que el profe subraya ("se debe utilizar el stack para convocar, enviar parámetros
y devolver resultados") es el corazón del TP. Si escribís una rutina que solo lee `%rdi` y
`%rsi` y hace `ret`, **técnicamente funciona pero no cumple la consigna**: nunca tocaste la
pila. Tenés que tener al menos una rutina que:

1. Arme su propio stack frame (`pushq %rbp` / `movq %rsp, %rbp`).
2. Lea sus parámetros desde offsets positivos de `%rbp` (o sea, desde la pila).
3. Desarme el frame en el epílogo (`popq %rbp` / `ret`).

El archivo `suma_por_pila.s` del repo del profe es exactamente el molde a copiar.

### Checklist de entrega

- [ ] Repo de GitHub creado y puesto en **privado**
- [ ] Responsable del grupo agregado con **email institucional**
- [ ] Profesor agregado como colaborador (confirmalo en Classroom)
- [ ] Un commit por funcionalidad, con mensaje breve que diga qué se implementó y validó
- [ ] README con instrucciones de compilación y ejecución
- [ ] Capa Python funcionando contra la API real
- [ ] Capa C compilando y enlazando con el `.o` de assembler
- [ ] Rutina ASM que recibe parámetros **por la pila**
- [ ] Evidencia de depuración con GDB (capturas o log de la sesión)

> ⚠️ El repo `practico-2` en GitHub hoy está **público**. Antes de entregar hay que pasarlo
> a privado (Settings → General → Danger Zone → Change repository visibility).

Ver [GUIA.md](GUIA.md) para la explicación paso a paso del material y el plan de trabajo.
