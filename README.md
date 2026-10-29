# Discipline Flow (v2.0)

Arnés de **Desarrollo Guiado por Especificaciones (SDD)** y control de ejecución determinista para agentes de código (Antigravity, Claude Code, Cursor, OpenCode).

Sustituye la prosa metodológica extensa por **contratos formales (`JSON Schema`)**, **barreras a nivel de sistema operativo (`Git Hooks` + `Bash CLI` cero-dependencias)** y **orquestación programática (`run-workflow` en Python)**.

---

## 1. Arquitectura de Componentes

| Componente | Ruta | Función |
| :--- | :--- | :--- |
| **Contrato Operativo** | `SKILL.md` | Fuente única de verdad operativa (comandos, esquemas, invocación de workflows). |
| **Shim del Proyecto** | `assets/AGENTS.md.template` | Bloque ligero inyectado en el `AGENTS.md` del proyecto consumidor que apunta in-place a `SKILL.md` y `sdd.sh`. |
| **Contratos JSON Schema** | `assets/schemas/*.json` | Validación determinista de planes (`spec_verification.json`), tareas (`task_breakdown.json`), auditoría ciega (`audit_verdict.json`) y sesión (`session_state.json`). |
| **Orquestador Agentic** | `workflows/sdd_cycle.py` | Pipeline `run-workflow` en 4 fases: `Audit Spec`, `Atomic Implementation` (`parallel` con `workspace="branch"`), `Mechanical Gate` y `Doubt-Driven Audit`. |
| **Controlador CLI** | `scripts/sdd.sh` | Único mutador autorizado del estado YAML en `SESSION.md` (`plan`, `start`, `verify`, `verify --json`, `orchestrate`, `advance`, `status`). |
| **Gate Mecánico** | `scripts/verify-crit.sh` | Verifica trazabilidad `CRIT-XX` en código/tests (excluyendo `*.md`), ausencia de `## DECISIÓN ABIERTA`, auditoría de bypass (`--no-verify`) y ejecución del test runner (salida Markdown o `--json`). |
| **Git Hooks** | `scripts/{pre-commit,commit-msg}-hook.sh` | Bloquean commits de código en estado `plan` y exigen Conventional Commits + token de fase (`F<N>`) en estado `execute`. |
| **Referencias Concisas** | `references/*.md` | Solo 2 archivos de consulta bajo demanda: `protocol-invariants.md` y `security-checklist.md`. |

---

## 2. Estructura del Repositorio

```text
discipline-flow/
├── SKILL.md                          # Especificación operativa central (v2.0)
├── README.md                         # Documentación de arquitectura y uso
├── assets/
│   ├── AGENTS.md.template            # Shim delimitado para AGENTS.md del proyecto destino
│   ├── PLAN.md.template              # Plantilla base para plans/PLAN-N.md
│   └── schemas/
│       ├── spec_verification.json    # Contrato de validación de especificación/plan
│       ├── task_breakdown.json       # Contrato de tareas atómicas (<= 5 archivos, DAG)
│       ├── audit_verdict.json        # Contrato booleano del auditor ciego (Doubt-Driven)
│       └── session_state.json        # Contrato formal del estado en SESSION.md
├── workflows/
│   ├── sdd_cycle.py                  # Orquestador Python para run_workflow de Antigravity
│   └── workflow.json                 # Esquema de argumentos de entrada (Args) del workflow
├── references/
│   ├── protocol-invariants.md        # Reglas conversacionales, TDD doubles y cierre C1/C2
│   └── security-checklist.md         # Invariantes de seguridad (Auth, Path, SSRF, Lockfiles, LLM)
├── scripts/
│   ├── init.sh                       # Bootstrap en el repositorio destino (AGENTS.md + Git hooks)
│   ├── reset.sh                      # Desinstalador limpio de estado, planes y hooks propios
│   ├── sdd.sh                        # CLI SDD (plan, start, verify, orchestrate, advance, status)
│   ├── verify-crit.sh                # Validador determinista CRIT-XX y test runner (MD / --json)
│   ├── package.sh                    # Empaquetador del distribuible zip versionado
│   ├── pre-commit-hook.sh            # Hook Git: bloquea código en sdd_state: plan
│   ├── commit-msg-hook.sh            # Hook Git: exige Conventional Commits + fase activa
│   └── lib/
│       └── sdd-common.sh             # Librería POSIX compartida (cero dependencias externas)
└── tests/
    └── run.sh                        # Suite de pruebas automatizadas en Bash + Python AST/JSON
```

---

## 3. Ciclo de Uso

### A. Bootstrap del Repositorio
```bash
<skill-path>/scripts/init.sh -t "pytest -q" -d /ruta/al/proyecto
```
Instala el bloque delimitado en `AGENTS.md` y los hooks `.git/hooks/{pre-commit,commit-msg}` referenciando la skill *in-place* (nunca copia scripts ni esquemas al proyecto).

### B. Planificación (`sdd_state: plan`)
```bash
<skill-path>/scripts/sdd.sh plan "Autenticación JWT y Rotación de Tokens"
```
Genera `plans/PLAN-N.md`, registra su `plan_hash` SHA-256 en `SESSION.md` y bloquea commits de código fuente hasta que el humano apruebe el plan.

### C. Ejecución Manual o Orquestada (`sdd_state: execute`)
* **Vía Orquestador `run-workflow` (Antigravity):**
  ```bash
  <skill-path>/scripts/sdd.sh orchestrate F1
  ```
  Genera el descriptor JSON (`ScriptPath`, `Cwd`, `Args`) para despachar `workflows/sdd_cycle.py`, que ejecuta secuencialmente `Audit Spec` → `Atomic Implementation` (en paralelo con `workspace="branch"`) → `Mechanical Gate` → `Doubt-Driven Audit`.
* **Vía CLI paso a paso:**
  ```bash
  <skill-path>/scripts/sdd.sh start F1 alice
  ```

### D. Verificación Mecánica y Cierre (`sdd_state: verify`)
```bash
<skill-path>/scripts/sdd.sh verify F1
# O en formato JSON para herramientas/workflows:
<skill-path>/scripts/sdd.sh verify --json F1
```
Valida trazabilidad 1:1 de `CRIT-XX` en tests, ausencia de `## DECISIÓN ABIERTA`, ausencia de commits evasores (`--no-verify` sin token `F1`) y ejecuta el test runner del proyecto. Si retorna `0`, avanza a `verify` y detiene la ejecución para auditoría humana del diff.

---

## 4. Distribución y Empaquetado

```bash
./scripts/package.sh
```
Genera `dist/discipline-flow-<version>.zip` + `sha256sums.txt` vía `git archive HEAD` incluyendo únicamente `SKILL.md`, `assets/`, `workflows/`, `scripts/`, `references/` y `VERSION` (excluyendo `tests/`, `.github/`, `README.md` y `skills/`).
