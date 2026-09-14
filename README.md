# Discipline Flow

Arnés de **Desarrollo Guiado por Especificaciones (SDD)** y control de ejecución determinista para agentes de código (Claude Code, Antigravity, Cursor, OpenCode).

Cero dependencias. Cero herramientas en segundo plano. Cero bases de datos de estado. Todo el control se ejerce mediante contratos de prosa estructurada, anclaje en Git, hooks deterministas y verificación automatizada en tests.

---

## 1. El Problema que Resuelve

Cuando un agente de IA programa sin restricciones formales, suele presentar tres fallas críticas:
1. **Deriva de alcance (*Scope Creep*):** Empieza arreglando un bug y termina refactorizando módulos ajenos sin autorización.
2. **Sesgo de complacencia:** Tilda tareas como completadas porque "asume" que el código funciona, sin haber probado los casos de borde.
3. **Amnesia y saturación de contexto:** Tras pausar una sesión o alcanzar el límite de tokens, la siguiente sesión arranca a ciegas, adivinando el estado del repositorio o duplicando trabajo.

**Discipline Flow** impone una estructura de trabajo rigurosa donde:
* **El plan es la especificación:** El trabajo se divide en fases atómicas con alcance cerrado.
* **Bloqueo físico durante el diseño:** El hook `pre-commit` impide commitear código fuente mientras el plan no esté aprobado.
* **Los criterios se demuestran con código (`CRIT-XX`):** Ninguna tarea se da por cumplida sin un test en verde que lleve su etiqueta.
* **Trazabilidad por fases:** Los commits exigen referenciar la fase activa (`F1`, `F2`).
* **La memoria entre sesiones es persistente (`SESSION.md`):** Se retoma el trabajo en segundos sin releer historiales muertos de chat.
* **El humano audita el diff:** Cada fase termina con un freno obligatorio antes de tocar la rama principal.

---

## 2. Modo de operación

El sistema desacopla responsabilidades en tres capas complementarias:

| Archivo | Capa | Rol | Mutabilidad |
| :--- | :--- | :--- | :--- |
| **`AGENTS.md`** | Constitución | Define cómo debe comportarse el agente, comandos permitidos, reglas de detención obligatoria y uso de `sdd.sh`. | Estático |
| **`PLAN-N.md`** | Especificación | Define qué se construye, qué queda explícitamente fuera de alcance y los criterios de aceptación (`CRIT-XX`). | Estable por ciclo |
| **`SESSION.md`** | Memoria y Estado | Guarda la máquina de estados SDD (`plan`, `execute`, `verify`), la fase activa (`active_task: F1`), el commit base y la siguiente acción. | Altamente dinámico |

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

**Regla de oro:** El agente tiene **estrictamente prohibido** marcar `- [x]` en un criterio automatizado si no existe una prueba unitaria, de integración o e2e cuyo nombre incluya el identificador exacto (`test('CRIT-01: ...')`) y haya pasado exitosamente en la sesión actual mediante `./scripts/sdd.sh verify F<N>`.

### B. Barreras Deterministas en Git (Hooks por Defecto)
1. **`pre-commit`**: Si `sdd_state` es `plan`, bloquea commits que contengan archivos de código fuente. Obliga a que la especificación esté cerrada antes de tocar código.
2. **`commit-msg`**: Exige Conventional Commits y verifica que, en estado `execute`, el commit mencione explícitamente la fase activa (ej. `feat(F1): ...` o `test: check crit-01 (F1)`).
Ambos hooks se instalan automáticamente en el bootstrap del repositorio.

### C. Fachada Unificada y Cero Fricción (`sdd.sh`)
Para evitar recordar múltiples scripts o lidiar con micro-tareas, el arnés opera a nivel de **Fase** (`F1`, `F2`, etc.) a través de un único CLI:
* `./scripts/sdd.sh plan "Título"` → Inicia plan y bloquea commits de código.
* `./scripts/sdd.sh start F1` → Desbloquea código para la fase F1.
* `./scripts/sdd.sh verify F1` → Corre suite de pruebas y verifica criterios `CRIT-XX`.
* `./scripts/sdd.sh status` → Consulta el estado SDD actual.

> **Sin fricción:** El desarrollador puede pedirle al agente en el chat *"Arrancá la fase F1"* o usar slash commands (ej. `/execute F1`). El agente tiene la instrucción constitucional de invocar `./scripts/sdd.sh start F1` por detrás automáticamente.

---

## 4. Integración y Descubrimiento (Project-Local y Agnóstica de Modelo)

Discipline Flow es una skill **local al proyecto** (*project-local*) y **completamente agnóstica del modelo**:

### A. Naturaleza Project-Local
* **Antigravity / Gemini:** `.agents/skills/discipline-flow/` o `.gemini/config/skills/discipline-flow/`
* **Claude Code:** `.claude/skills/discipline-flow/`
* **Agnóstico / Submódulo Git:** `skills/discipline-flow/`
* **Zero Runtime Overhead:** Opera mediante scripts Bash livianos estándar y archivos Markdown.

### B. Descubrimiento Semántico y Constitucional
* **Semántico (`SKILL.md`):** Indexado por agentes compatibles para activar la skill ante solicitudes de planificación o desarrollo disciplinado.
* **Constitucional (`AGENTS.md` / `CLAUDE.md`):** Anclaje directo en el repositorio. `CLAUDE.md` apunta a `@AGENTS.md` sin duplicar contratos.

### C. Flujo de Trabajo en Tiempo de Ejecución

```text
                  ┌──────────────────────┐
                  │ Inicio de la sesión  │
                  └──────────┬───────────┘
                             │
                  ¿Existe SESSION.md?
                  ┌──────────┴───────────┐
               SÍ │                      │ NO
                  ▼                      ▼
     git merge-base OK?          Lee SKILL.md y rutea:
     ┌────────────┴──────────┐   ├── A: Bootstrap (init.sh)
  SÍ │                    NO │   ├── B: Plan Cycle (sdd.sh plan)
     ▼                       ▼   └── C: Phase Close (sdd.sh verify)
Reanuda desde          ALTO OBLIGATORIO
"Next action"       (divergencia detectada)
     │                       ▲
     ▼                       │
Ejecuta fase:                │
  1. sdd.sh start F1         │
  2. Test CRIT-XX (RED)      │
  3. Código (GREEN)          │
  4. Commit feat(F1): ...    │
  5. sdd.sh verify F1 ───────┘
  6. ALTO: Reporte para auditoría humana de diff
```

---

## 5. Coexistencia con `AGENTS.md`

Para garantizar compatibilidad total sin alterar las reglas preexistentes del usuario, Discipline Flow utiliza **bloques administrados delimitados** (*Managed Delimited Blocks*):

```markdown
<!-- BEGIN DISCIPLINE-FLOW -->
# MiProyecto — Contributor & Executor Contract (Discipline Flow)

## Always
...
## Plan mode
...
<!-- END DISCIPLINE-FLOW -->
```

* **Si `AGENTS.md` no existe:** Se crea conteniendo el bloque delimitado.
* **Si ya existe:** Se realiza un **append no destructivo**.
* **Idempotente:** Reejecutar `init.sh` actualiza **únicamente** la sección entre los marcadores.
* **`CLAUDE.md`:** Se añade `@AGENTS.md` al final si no está presente.
* **Sobrescritura total:** Solo disponible mediante el flag explícito `--force`.

---

## 6. Estructura del Repositorio de la Skill

```text
discipline-flow/
├── SKILL.md                      # Definición formal de la skill, triggers y entry points
├── README.md                     # Este documento
├── PROJECT_FOUNDATION.md         # Principios fundacionales y arquitectura del arnés SDD
├── assets/
│   ├── AGENTS.md.template        # Plantilla del contrato operativo con delimitadores
│   ├── PLAN.md.template          # Plantilla de especificación SDD con CRIT-XX
│   └── SESSION.md.template       # Plantilla del checkpoint de sesión con frontmatter SDD
├── references/
│   ├── bootstrap.md              # Guía de inicialización de repositorios y coexistence
│   ├── plan-cycle.md             # Guía del ciclo de planificación y ejecución por fases
│   └── phase-close.md            # Protocolo de cierre de fase y auditoría de diff
└── scripts/
    ├── init.sh                   # Script de instalación inicial (scripts + hooks por defecto)
    ├── sdd.sh                    # Fachada CLI unificada SDD (start, plan, verify, status)
    ├── verify-crit.sh            # Gate determinista de trazabilidad CRIT-XX y test runner
    ├── new-plan.sh               # Generador de nuevos planes numerados
    ├── pre-commit-hook.sh        # Hook Git: Bloquea commits de código en modo plan (.git/hooks/pre-commit)
    └── commit-msg-hook.sh        # Hook Git: Valida Conventional Commits y fase activa (.git/hooks/commit-msg)
```

---

## 7. El Ciclo de Trabajo en 4 Pasos

### Paso 1: Bootstrap (Inicialización)

Activa la disciplina en un proyecto nuevo o existente. Instala scripts y hooks de Git por defecto:

```bash
./scripts/init.sh -t "npm test"
```

Esto genera `AGENTS.md`, vincula `CLAUDE.md`, copia `scripts/{sdd.sh, verify-crit.sh, new-plan.sh}` e instala los hooks `.git/hooks/{pre-commit, commit-msg}`. *(Opcionalmente `--no-hooks` si se desean omitir).*

### Paso 2: Planificación (Spec First)

Antes de escribir código, genera la especificación formal del ciclo:

```bash
./scripts/sdd.sh plan "Autenticación JWT y Rotación de Tokens"
```

El proyecto entra en `sdd_state: plan`. En este estado, el hook `pre-commit` impide commitear código. El agente y el desarrollador definen el objetivo, las fases (`F1`, `F2`) y los criterios `CRIT-01`, `CRIT-02`. **El agente se detiene aquí:** el plan debe ser aprobado por el humano.

### Paso 3: Ejecución de Fase (Código Desbloqueado)

Para comenzar a programar la primera fase:

```bash
./scripts/sdd.sh start F1
```

*(O en el chat con el agente: "Arrancá la fase F1", y el agente corre este comando).*
1. El estado pasa a `execute` y la fase activa se fija en `F1` (código desbloqueado).
2. Se escribe el test automatizado que referencia explícitamente a `CRIT-XX`.
3. Se escribe el código mínimo de producción para ponerlo en verde (RED → GREEN).
4. Cada commit incluye la fase: `git commit -m "feat(F1): implementar rotación de tokens"`.
5. Se actualiza atómicamente `SESSION.md`.

### Paso 4: Cierre de Fase y Auditoría Humana

Al completar los criterios de la fase:

```bash
./scripts/sdd.sh verify F1
```

1. El gate verifica la correspondencia 1:1 entre cada `CRIT-XX` y los tests en el código (`--untracked` incluido).
2. Corre la suite completa de pruebas del proyecto.
3. Si pasa todo en verde, el estado avanza a `verify`.
4. El agente genera el reporte de cierre con la tabla de evidencia.
5. **Se detiene obligatoriamente.** No avanza a la siguiente fase hasta que el humano audite y apruebe el diff en Git.

---

## 8. Alcance Honesto y Garantías

* **Es un arnés basado en contratos y gates deterministas:** Funciona instruyendo al agente con reglas operativas inequívocas y protegiendo el repositorio con hooks estándar de Git.
* **Sin bloqueos de software pesados:** No introduce demonios en segundo plano, locks distribuidos ni parsers de AST. La rigidez la aportan Git, Bash y los tests del propio proyecto.
* **Resiliencia ante fallos:** No promete transaccionalidad matemática ACID, pero reduce drásticamente el retrabajo y la pérdida de rumbo habitual en agentes autónomos.
