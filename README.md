# Discipline Flow

Arnés de **Desarrollo Guiado por Especificaciones (SDD)** y control de ejecución para agentes de código (Claude Code, Antigravity, Cursor, OpenCode).

Cero dependencias. Cero herramientas en segundo plano. Cero bases de datos de estado. Todo el control se ejerce mediante contratos de prosa estructurada, anclaje en Git y verificación automatizada en tests.

---

## 1. El Problema que Resuelve

Cuando un agente de IA programa sin restricciones formales, suele presentar tres fallas críticas:
1. **Deriva de alcance (*Scope Creep*):** Empieza arreglando un bug y termina refactorizando módulos ajenos sin autorización.
2. **Sesgo de complacencia:** Tilda tareas como completadas porque "asume" que el código funciona, sin haber probado los casos de borde.
3. **Amnesia y saturación de contexto:** Tras pausar una sesión o alcanzar el límite de tokens, la siguiente sesión arranca a ciegas, adivinando el estado del repositorio o duplicando trabajo.

**Discipline Flow** impone una estructura de trabajo rigurosa donde:
* **El plan es la especificación:** El trabajo se divide en fases atómicas con alcance cerrado.
* **Los criterios se demuestran con código (`CRIT-XX`):** Ninguna tarea se da por cumplida sin un test en verde que lleve su etiqueta.
* **La memoria entre sesiones es persistente (`SESSION.md`):** Se retoma el trabajo en segundos sin releer historiales muertos de chat.
* **El humano audita el diff:** Cada fase termina con un freno obligatorio antes de tocar la rama principal.

---

## 2. Modo de operación

El sistema desacopla responsabilidades en tres capas complementarias:

| Archivo | Capa | Rol | Mutabilidad |
| :--- | :--- | :--- | :--- |
| **`AGENTS.md`** | Constitución | Define cómo debe comportarse el agente, qué comandos puede correr y las reglas de detención obligatoria. | Estático |
| **`PLAN-N.md`** | Especificación | Define qué se construye, qué queda explícitamente fuera de alcance y los criterios de aceptación. | Estable por ciclo |
| **`SESSION.md`** | Memoria | Guarda el punto exacto de interrupción, el commit base y la siguiente acción inmediata. | Altamente dinámico |

---

## 3. Principios Fundamentales

### A. Trazabilidad Contractual (`CRIT-XX`)
Cada fase de un plan define entre 2 y 7 criterios de aceptación atómicos identificados secuencialmente:
```markdown
### Acceptance criteria
- [ ] CRIT-01: El token de refresco expira en 7 días y revoca el anterior.
- [ ] CRIT-02: Peticiones concurrentes con el mismo token devuelven HTTP 409.
- [ ] CRIT-03: (manual) Verificar legibilidad del log en consola de auditoría.

```

**Regla de oro:** El agente tiene **estrictamente prohibido** marcar `- [x]` en un criterio automatizado si no existe una prueba unitaria, de integración o e2e cuyo nombre incluya el identificador exacto (`test('CRIT-01: ...')`) y haya pasado exitosamente en la sesión actual.

### B. Memoria entre Sesiones sin Sobrecarga de Tokens

En proyectos multisesión, `SESSION.md` actúa como un cursor liviano (~250 tokens) que almacena:

* `Base commit`: El punto de partida de la fase actual.
* `Recorded HEAD`: El commit exacto al momento del último checkpoint.
* `Next action`: Una única instrucción atómica y ejecutable.
* `Open decisions`: Dudas de arquitectura que requieren intervención humana.

Al iniciar una nueva sesión, el agente ejecuta:

```bash
git merge-base --is-ancestor <base-commit> HEAD

```

Si la historia de Git divergió (rebase, reset, force-push), el agente se detiene inmediatamente en lugar de alucinar sobre un estado que ya no existe.

### C. Jerarquía Estricta de Autoridad

Ante cualquier discrepancia en el repositorio, rige este orden de precedencia:

```text
Git (código y working tree) > PLAN-N.md (especificación) > SESSION.md (memoria)

```

Si la memoria del agente contradice los archivos en disco, manda el disco. Si el código requiere violar el plan, el agente se detiene y pide una corrección formal.

---

## 4. Estructura del Repositorio de la Skill

```text
discipline-flow/
├── SKILL.md                      # Definición formal de la skill y entry points
├── README.md                     # Este documento
├── assets/
│   ├── AGENTS.md.template        # Plantilla del contrato operativo
│   ├── PLAN.md.template          # Plantilla de especificación SDD con CRIT-XX
│   └── SESSION.md.template       # Plantilla del checkpoint de sesión
├── references/
│   ├── bootstrap.md              # Guía de inicialización de repositorios
│   ├── plan-cycle.md             # Guía del ciclo de planificación y ejecución
│   └── phase-close.md            # Protocolo de cierre de fase y auditoría de diff
└── scripts/
    ├── init.sh                   # Script de instalación inicial
    ├── new-plan.sh               # Generador de nuevos planes numerados
    └── commit-msg-hook.sh        # Hook opcional de commits convencionales

```

---

## 5. Ciclo de Trabajo en 4 Pasos

### Paso 1: Bootstrap (Inicialización)

Para activar la disciplina en un proyecto nuevo o existente, el agente aplica la plantilla base:

```bash
./scripts/init.sh

```

Esto genera `AGENTS.md` adaptado a la pila tecnológica del proyecto (comandos de test, linter y build).

### Paso 2: Planificación (Spec First)

Antes de escribir código, se genera la especificación de la feature:

```bash
./scripts/new-plan.sh "Autenticación JWT y Rotación de Tokens"

```

El agente y el desarrollador definen el alcance, declaran qué queda fuera de alcance (*Out of Scope*) y redactan los criterios `CRIT-01`, `CRIT-02`. El plan debe ser validado por el humano antes de comenzar la implementación.

### Paso 3: Ejecución y Checkpoint

El agente implementa fase por fase:

1. Escribe el test que referencia a `CRIT-XX`.
2. Escribe el código mínimo de producción para ponerlo en verde.
3. Actualiza atómicamente `SESSION.md` (`.tmp` -> rename) al completar hitos significativos.
4. Si se corta el contexto o la sesión, la siguiente reanuda directamente desde `Next action`.

### Paso 4: Cierre de Fase y Auditoría Humana

Al completar los criterios de la fase:

1. El agente ejecuta la suite completa de pruebas.
2. Genera una tabla de correspondencia entre cada `CRIT-XX` y el test que lo demuestra.
3. Deja los criterios manuales sin marcar para revisión humana.
4. **Se detiene.** No avanza a la siguiente fase hasta que el humano revise y apruebe el diff en Git.

---

## 6. Alcance Honesto y Garantías

* **Es un arnés basado en contratos:** Funciona instruyendo al agente con reglas operativas inequívocas y validaciones humanas.
* **Sin bloqueos de software pesados:** No introduce demonios en segundo plano, locks distribuidos ni parsers de AST. La rigidez la aportan Git y los tests del propio proyecto.
* **Resiliencia ante fallos:** No promete transaccionalidad matemática ACID, pero reduce en más de un 90% el retrabajo y la pérdida de rumbo habitual en agentes autónomos.

```

```
