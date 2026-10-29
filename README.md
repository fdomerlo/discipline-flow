# Discipline Flow (v2.0 — Programmatic Workflow Edition)

Arnés de **Desarrollo Guiado por Especificaciones (SDD)** y orquestación determinista para agentes de código (Antigravity, Claude Code, Cursor, OpenCode).

En lugar de inflar la ventana de contexto con más de 100 KB de manuales en prosa que el LLM puede olvidar o racionalizar, **Discipline Flow v2.0** combina **workflows programáticos (`run_workflow` en Python con JSON Schemas estrictos)** y **barreras físicas a nivel de sistema operativo (Git hooks + Bash POSIX)**, reduciendo el consumo de contexto pasivo en un **94,4%** (~1.500 tokens totales).

---

## 1. El Problema que Resuelve

Cuando un agente de IA programa guiado solo por instrucciones de texto (prosa), sufre tres fallas estructurales:
1. **Degradación de atención (*Context Rot*):** Cuanto más largo es el manual de la skill, más probable es que el modelo ignore reglas al crecer la conversación.
2. **Sesgo de confirmación (Juez y Parte):** Si el mismo contexto que redacta un plan o escribe un test también implementa el código y lo audita, tiende a escribir tests débiles o tildar casillas (`- [x]`) sin verificarlas.
3. **Deriva de alcance (*Scope Creep*):** Empieza arreglando un bug y termina refactorizando módulos ajenos o commiteando sin trazabilidad.

**Discipline Flow** reemplaza las "instrucciones blandas" por dos capas de ejecución determinista:
* **Capa 1 — Orquestación Cognitiva (`workflows/sdd_*.py` vía `run_workflow`):** Scripts de Python que aíslan contextos entre agentes (Arquitecto vs. Auditores paralelos; Agente TDD RED vs. Agente TDD GREEN; Revisor Adversarial sin acceso al `CLAIM`), imponen contratos de salida con JSON Schema y ejecutan las transiciones de estado sin depender de la voluntad del LLM.
* **Capa 2 — Muro de Contención Físico (`scripts/` + Git Hooks):**
  * **`pre-commit`**: Bloquea archivos de secretos (`.env*`, `*.pem`, `*.key`, llaves privadas) en todo momento, y bloquea cualquier cambio a archivos de código fuente mientras `sdd_state` sea `plan`.
  * **`commit-msg`**: Exige Conventional Commits y obliga a referenciar la fase activa (ej. `feat(F1): ...`) durante `execute`.
  * **`verify-crit.sh`**: Verifica sintácticamente que cada criterio `CRIT-XX` tenga un test real en el repositorio, audita que no existan commits evasores (`--no-verify`) desde el inicio de la fase y corre la suite de pruebas completa. Si todo está en verde, **tilda automáticamente** (vía `tick-plan.sh`) los `CRIT-XX` automatizados de la fase y los criterios de ciclo derivables; los `(manual)` quedan para el humano.

---

## 2. Arquitectura de 4 Workflows Programáticos (`workflows/`)

| Workflow (`ScriptPath`) | Qué reemplaza | Garantías deterministas en Python (0 tokens de prosa) |
| :--- | :--- | :--- |
| **[`workflows/sdd_doubt.py`](file:///home/fdomerlo/Proyectos/fdomerlo/discipline-flow/workflows/sdd_doubt.py)** | *Doubt-Driven Development* | Pasa al revisor adversarial **únicamente** `ARTIFACT + CONTRACT` (nunca el `CLAIM`). Fuerza clasificación por precedencia (`contract_misread`, `actionable`, `trade_off`, `noise`), limita a máx. 3 ciclos y aborta si detecta **Doubt Theater** (2 ciclos con hallazgos sustantivos y 0 accionables). |
| **[`workflows/sdd_plan.py`](file:///home/fdomerlo/Proyectos/fdomerlo/discipline-flow/workflows/sdd_plan.py)** | *Plan Cycle + Task Breakdown + SDD* | Impide sobreescribir un plan con `- [ ] CRIT-XX` abiertos. Valida que el *Capability Map* (`decompose=True`) sea un **DAG sin ciclos**. Exige por JSON Schema 2–7 criterios y ≤ 5 archivos por fase. Lanza **4 auditores independientes en `parallel()`**, renderiza `plans/PLAN-N.md` y congela `plan_hash` vía `sdd.sh`. |
| **[`workflows/sdd_execute.py`](file:///home/fdomerlo/Proyectos/fdomerlo/discipline-flow/workflows/sdd_execute.py)** | *TDD + Multi-Agent + Security + DoD + Phase Close (C1)* | Verifica ausencia de conflictos y ancestro Git en `SESSION.md`. Recorta **solo la fase `F<N>`** del plan. Separa **Agente RED** (solo tests con `CRIT-XX`, comprobado con `git grep`) de **Agente GREEN** (implementación). Dispara auditor de Seguridad/DoD **solo si** el diff toca superficies sensibles. Corre `sdd.sh verify F<N>` y **Python** tilda los `- [x]` en `PLAN-N.md`. |
| **[`workflows/sdd_close.py`](file:///home/fdomerlo/Proyectos/fdomerlo/discipline-flow/workflows/sdd_close.py)** | *Cycle Close (C2)* | Parsea por regex criterios `- [ ]` vs `- [x]` y `Out of scope`, y ejecuta en `parallel()` la auditoría de *Realidad vs. Plan* y *Scope Leaks* sobre el historial Git del ciclo. |

---

## 3. Estructura del Repositorio

```text
discipline-flow/
├── SKILL.md                      # Contrato compacto para el agente (~45 líneas)
├── README.md                     # Este documento
├── PROJECT_FOUNDATION.md         # Principios fundacionales y arquitectura del arnés SDD
├── assets/
│   ├── AGENTS.md.template        # Plantilla ultracompacta del contrato (< 30 líneas)
│   ├── PLAN.md.template          # Plantilla de especificación SDD con CRIT-XX
│   └── SESSION.md.template       # Plantilla del checkpoint de sesión con frontmatter SDD
├── workflows/
│   ├── sdd_doubt.py              # Revisión adversarial con aislamiento de contexto y Doubt Theater check
│   ├── sdd_plan.py               # Diseño de plan por JSON Schema, DAG check y 4 auditores en paralelo
│   ├── sdd_execute.py            # Ciclo TDD Red/Green aislado, auditoría condicional y cierre C1
│   └── sdd_close.py              # Auditoría paralela de cierre de ciclo (C2)
├── scripts/
│   ├── init.sh                   # Bootstrap del proyecto (AGENTS.md + hooks in-place)
│   ├── reset.sh                  # Limpieza segura del arnés preservando reglas/hooks ajenos
│   ├── package.sh                # Generador del distribuible zip versionado (release)
│   ├── sdd.sh                    # Fachada CLI unificada SDD (start, plan, verify, advance, status)
│   ├── verify-crit.sh            # Gate determinista de trazabilidad CRIT-XX, bypass audit y test runner
│   ├── tick-plan.sh              # Único escritor de `- [x]` en PLAN-N.md (fase, ciclo, scope-clean)
│   ├── new-plan.sh               # Generador de nuevos planes numerados (plans/PLAN-N.md)
│   ├── lib/
│   │   └── sdd-common.sh         # Helpers compartidos SESSION/PLAN (POSIX sh)
│   ├── pre-commit-hook.sh        # Hook Git: Bloquea secretos siempre y código en modo plan
│   └── commit-msg-hook.sh        # Hook Git: Valida Conventional Commits y token de fase activa
└── tests/
    ├── run.sh                    # Runner de pruebas herméticas
    └── test-*.sh                 # 10 suites de pruebas (incluyendo test-workflows.sh end-to-end)
```

---

## 4. El Ciclo de Trabajo

### Paso 1: Bootstrap
```bash
<skill-path>/scripts/init.sh -t "npm test"
```
Instala el bloque administrado en `AGENTS.md` y los hooks `.git/hooks/{pre-commit, commit-msg}` referenciando la skill en su lugar (sin copiar scripts al proyecto).

### Paso 2: Planificación (`sdd_plan.py` / `sdd.sh plan`)
* **Con `run_workflow`:** El agente ejecuta `workflows/sdd_plan.py`, que diseña el plan con JSON Schema, lo audita en 4 ejes paralelos, escribe `plans/PLAN-N.md` y bloquea el estado en `plan`.
* **Por CLI directo:** `./scripts/sdd.sh plan "Título"`.

### Paso 3: Ejecución y Verificación de Fase (`sdd_execute.py` / `sdd.sh start & verify`)
* **Con `run_workflow`:** Al indicar *"Inicia F1"*, el agente invoca `workflows/sdd_execute.py` con `Args={"phase": "F1"}` (o `{"phases": ["F1", "F2"]}` para ejecución multi-agente en paralelo con `workspace="share"`). El script ejecuta `sdd.sh start F1`, coordina los sub-agentes **RED** y **GREEN**, corre `sdd.sh verify F1`, tilda los `- [x]` verificados en `PLAN-N.md` y se detiene para la auditoría humana del diff.
* **Por CLI directo:** `./scripts/sdd.sh start F1` → tests `CRIT-XX` (RED) → código (GREEN) → `./scripts/sdd.sh verify F1`.

### Paso 4: Cierre de Ciclo (`sdd_close.py`)
Al finalizar todas las fases del plan, `workflows/sdd_close.py` audita en paralelo el diff acumulado del ciclo contra el plan original y la sección `Out of scope`.

---

## 5. Distribución e Instalación

Cada release empaqueta vía `scripts/package.sh` únicamente los artefactos de runtime:
* **Incluye:** `SKILL.md`, `workflows/`, `scripts/`, `assets/`, `VERSION`.
* **Excluye:** `.git/`, `tests/`, `README.md`, `PROJECT_FOUNDATION.md`.
