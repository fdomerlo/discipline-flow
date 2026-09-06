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

## 4. Integración y Descubrimiento (Project-Local y Agnóstica de Modelo)

Discipline Flow está diseñado como una skill **local al proyecto** (*project-local*) y **completamente agnóstica del modelo**, lo que significa que no asume ningún proveedor de IA específico, ni requiere extensiones propietarias o servidores en background.

### A. Naturaleza Project-Local
La skill reside en el propio repositorio objetivo, lo que garantiza portabilidad entre desarrolladores y entornos de CI sin instalar dependencias globales:

* **Estructura recomendada en el proyecto:**
  * **Antigravity / Gemini:** `.agents/skills/discipline-flow/` o `.gemini/config/skills/discipline-flow/`
  * **Claude Code:** `.claude/skills/discipline-flow/`
  * **Agnóstico / Submódulo Git:** `skills/discipline-flow/`
* **Zero Runtime Overhead:** No requiere Node.js, Python runtime en ejecución, demonios ni bases de datos. Todo opera mediante scripts Bash livianos estándar y archivos Markdown.

### B. Agnóstica del Modelo
El arnés opera eficazmente con cualquier modelo de razonamiento moderno (min.: Claude 3.7 Sonnet, Gemini 2.0/2.5 Pro & Flash, GPT-4o, DeepSeek R1/V3, o modelos locales vía Ollama). 

No depende de herramientas propietarias de function-calling o configuraciones específicas de proveedor. La inteligencia de control se rige por:
1. **Contratos en prosa estructurada** (`AGENTS.md`).
2. **Especificaciones de fases con identificadores** (`PLAN-N.md` con `CRIT-XX`).
3. **Anclaje en Git** (`git rev-parse HEAD`, `git merge-base`).
4. **Test runners nativos** del proyecto (`npm test`, `pytest`, `cargo test`, `go test`, `mvn test`).

### C. Cómo Descubre la Skill el Agente
El descubrimiento se produce en dos niveles complementarios:

1. **Descubrimiento Semántico por Plataforma (`SKILL.md`):**
   Los entornos compatibles con el estándar de Agent Skills (Antigravity, Claude Code, etc.) indexan el frontmatter YAML de [SKILL.md](file:///home/fdomerlo/Proyectos/github.com/fdomerlo/discipline-flow/SKILL.md):
   ```yaml
   ---
   name: discipline-flow
   description: Bootstraps repositories with an AI executor contract (AGENTS.md, conventional commits hook) or scaffolds structured, phased PLAN-N.md cycles with human audit between phases. Trigger when starting a new project, setting up commit conventions, breaking multi-session work into phases, or closing an execution phase.
   ---
   ```
   Cuando el usuario solicita iniciar un proyecto, trabajar en fases, planificar una tarea compleja o reanudar una sesión interrumpida, el arnés activa automáticamente la skill e inyecta sus instrucciones en el contexto de trabajo.

2. **Descubrimiento Constitucional en Repositorio (`AGENTS.md` / `CLAUDE.md`):**
   Para clientes que no implementan un catálogo dinámico de skills (como Cursor, OpenCode o sesiones directas de terminal), el arnés se ancla permanentemente en el repositorio:
   * `AGENTS.md` en la raíz es leído de forma estándar y nativa por Antigravity, OpenCode, Codex y Cursor.
   * `CLAUDE.md` en la raíz contiene la directiva `@AGENTS.md`, el mecanismo documentado de Anthropic para importar reglas de repositorio sin duplicar archivos ni requerir symlinks de administrador en Windows.

### D. Cómo Utiliza la Skill el Agente en Tiempo de Ejecución
El flujo de trabajo del agente sigue una máquina de estados determinista:

```
                  ┌──────────────────────┐
                  │ Inicio de la sesión  │
                  └──────────┬───────────┘
                             │
                  ¿Existe SESSION.md?
                  ┌──────────┴──────────┐
               SÍ │                     │ NO
                  ▼                     ▼
     git merge-base OK?          Lee SKILL.md y rutea:
     ┌────────────┴──────────┐   ├── A: Bootstrap (init.sh)
  SÍ │                    NO │   ├── B: Plan Cycle (new-plan.sh)
     ▼                       ▼   └── C: Phase Close
Reanuda desde          ALTO OBLIGATORIO
"Next action"       (divergencia detectada)
     │                       ▲
     ▼                       │
Ejecuta fase:                │
  1. Test con CRIT-XX (RED)  │
  2. Implementa código (GREEN)
  3. Suite completa en verde  │
  4. Actualiza SESSION.md ───┘
  5. ALTO: Entrega reporte para auditoría humana de diff
```

---

## 5. Coexistencia con `AGENTS.md`

Para garantizar compatibilidad total sin alterar las reglas del usuario, Discipline Flow utiliza **bloques administrados delimitados** (*Managed Delimited Blocks*):

```markdown
<!-- BEGIN DISCIPLINE-FLOW -->
# MiProyecto — Contributor & Executor Contract (Discipline Flow)

## Always
...
## Plan mode
...
<!-- END DISCIPLINE-FLOW -->
```

### Comportamiento Inteligente de Integración:
* **Si `AGENTS.md` no existe:** Se crea desde cero conteniendo el bloque delimitado del contrato.
* **Si `AGENTS.md` ya existe (sin el bloque):** Se realiza un **append no destructivo** al final del archivo. Las directrices originales del equipo quedan 100% intactas al comienzo, y el contrato de Discipline Flow se anexa a continuación.
* **Si `AGENTS.md` ya contiene el bloque:** Al reejecutar `scripts/init.sh` (por ejemplo, para actualizar comandos de test o types de commit), se actualiza **únicamente** la sección entre los marcadores `<!-- BEGIN DISCIPLINE-FLOW -->` y `<!-- END DISCIPLINE-FLOW -->`. Es totalmente idempotente y nunca duplica contenido.
* **Preservación de `CLAUDE.md`:** Si `CLAUDE.md` ya existía con reglas propias, se añade `@AGENTS.md` al final si no está presente, garantizando que Claude Code lea ambas fuentes sin destruir configuraciones previas.
* **Flag de excepción `--force`:** Solo si el desarrollador solicita explícitamente un reemplazo total (`--force`), los archivos son sobrescritos por completo.

---

## 6. Estructura del Repositorio de la Skill

```text
discipline-flow/
├── SKILL.md                      # Definición formal de la skill, triggers y entry points
├── README.md                     # Este documento
├── assets/
│   ├── AGENTS.md.template        # Plantilla del contrato operativo con delimitadores
│   ├── PLAN.md.template          # Plantilla de especificación SDD con CRIT-XX
│   └── SESSION.md.template       # Plantilla del checkpoint de sesión
├── references/
│   ├── bootstrap.md              # Guía de inicialización de repositorios y coexistence
│   ├── plan-cycle.md             # Guía del ciclo de planificación y ejecución
│   └── phase-close.md            # Protocolo de cierre de fase y auditoría de diff
└── scripts/
    ├── init.sh                   # Script de instalación inicial (append idempotente)
    ├── new-plan.sh               # Generador de nuevos planes numerados
    └── commit-msg-hook.sh        # Hook opcional de commits convencionales
```

---

## 7. El Ciclo de Trabajo del Agente en 4 Pasos

### Paso 1: Bootstrap (Inicialización)

Activa la disciplina en un proyecto nuevo o existente sin destruir directrices previas:

```bash
./scripts/init.sh -t "npm test" --with-hook
```

Esto inyecta `AGENTS.md` respetando archivos preexistentes, configura `CLAUDE.md` con `@AGENTS.md` e instala opcionalmente el hook de Conventional Commits.

### Paso 2: Planificación (Spec First)

Antes de escribir código, genera la especificación formal del ciclo:

```bash
./scripts/new-plan.sh "Autenticación JWT y Rotación de Tokens"
```

El agente y el desarrollador definen el objetivo, declaran qué queda fuera de alcance (*Out of Scope*) y redactan los criterios `CRIT-01`, `CRIT-02`. **El agente se detiene aquí:** el plan debe ser aprobado por el humano antes de tocar código.

### Paso 3: Ejecución y Checkpoint

Implementa fase por fase:

1. Escribe el test automatizado que referencia explícitamente a `CRIT-XX`.
2. Escribe el código mínimo de producción para ponerlo en verde (RED → GREEN).
3. Actualiza atómicamente `SESSION.md` (`.tmp` -> rename) al completar hitos significativos.
4. Si se corta el contexto o la sesión, la siguiente reanuda directamente desde `Next action`.

### Paso 4: Cierre de Fase y Auditoría Humana

Al completar los criterios de la fase:

1. Ejecuta la suite completa de pruebas del proyecto.
2. Genera una tabla de correspondencia demostrando qué test valida cada `CRIT-XX`.
3. Deja los criterios manuales (`CRIT-XX: (manual)`) sin marcar para revisión humana.
4. **Se detiene obligatoriamente.** No avanza a la siguiente fase hasta que el humano audite y apruebe el diff en Git.

---

## 8. Alcance Honesto y Garantías

* **Es un arnés basado en contratos:** Funciona instruyendo al agente con reglas operativas inequívocas y validaciones humanas.
* **Sin bloqueos de software pesados:** No introduce demonios en segundo plano, locks distribuidos ni parsers de AST. La rigidez la aportan Git y los tests del propio proyecto.
* **Resiliencia ante fallos:** No promete transaccionalidad matemática ACID, pero reduce en más de un 90% el retrabajo y la pérdida de rumbo habitual en agentes autónomos.
