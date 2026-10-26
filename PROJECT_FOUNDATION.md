## Project Foundation: Discipline-Flow

**Propósito Principal:**
`discipline-flow` es un arnés de contención y orquestación determinista diseñado para forzar la adopción estricta de Specification-Driven Development (SDD) en entornos asistidos por IA. Su objetivo es eliminar el desvío de especificación (*specification drift*), el sesgo de confirmación y el consumo excesivo de tokens sustituyendo los manuales en prosa por **workflows programáticos (`run_workflow`)** y **barreras físicas a nivel de sistema operativo y Git**.

### 1. Filosofía de Diseño (Core Tenets)

* **Código sobre Prosa (Zero-Prose Overhead):** Los LLMs degradan su cumplimiento de reglas cuando se cargan decenas de kilobytes de instrucciones textuales en su contexto. Toda regla procedimental (bucles TDD, aislamiento de contexto en revisiones, conteo de criterios, tildado de casillas `[x]`, transiciones de estado) debe ejecutarse programáticamente en `workflows/*.py` o `scripts/*.sh`, no pedirse por favor en prosa.
* **Separación Física de Contextos:** El agente que propone una hipótesis (`CLAIM`) no puede ser el mismo que la audita; el agente que escribe el test de especificación (**RED**) no es el mismo que escribe el código de producción (**GREEN**). `workflows/sdd_doubt.py`, `workflows/sdd_plan.py` y `workflows/sdd_execute.py` fuerzan esta separación mediante instancias efímeras de `agent()` con esquemas JSON (`schema`) obligatorios.
* **Núcleo CLI Cero-Dependencias:** La capa baja de control (`scripts/sdd.sh`, `scripts/verify-crit.sh`, `scripts/pre-commit-hook.sh`, `scripts/commit-msg-hook.sh`) está construida íntegramente en Bash y utilidades POSIX (`awk`, `sed`, `grep`, `sha256sum`), garantizando que los Git hooks funcionen en cualquier entorno Linux sin demonios ni servidores externos.
* **Estado Inmutable:** El estado del proyecto reside en el bloque YAML frontmatter de `SESSION.md`, protegido por hashes SHA-256 del plan activo (`plan_hash`).

### 2. Arquitectura de Componentes

1. **Orquestadores Programáticos (`workflows/`):**
   * `sdd_doubt.py`: Ciclo adversarial acotado (máx. 3 iteraciones) con aislamiento físico del `CLAIM` y detección matemática de *Doubt Theater*.
   * `sdd_plan.py`: Generación de `plans/PLAN-N.md` guiada por JSON Schema (2–7 `CRIT-XX`, ≤ 5 archivos por fase), validación de DAG sin ciclos para mapas de capacidades y auto-auditoría paralela en 4 ejes.
   * `sdd_execute.py`: Verificación de integridad de `SESSION.md`, inyección quirúrgica del recorte de la fase `F<N>`, separación **TDD RED → TDD GREEN**, auditoría condicional de Seguridad/DoD sobre el `git diff`, ejecución de `verify-crit.sh` y tildado automático de `- [x]` en el plan.
   * `sdd_close.py`: Auditoría C2 paralela de cierre de ciclo (*Unticked boxes*, *Reality vs. Plan* y *Scope Leaks*).
2. **Controlador y Fuente de Verdad (`scripts/sdd.sh` + `SESSION.md`):**
   Único ciudadano autorizado para mutar el frontmatter YAML (`plan`, `execute`, `verify`, `active_task`, `active_agent`, `plan_hash`).
3. **Muro de Contención (`scripts/pre-commit-hook.sh` & `scripts/commit-msg-hook.sh`):**
   * `pre-commit`: Bloquea archivos de credenciales/llaves privadas (`.env*`, `*.pem`, `*.key`, `PRIVATE KEY`) en todo momento y bloquea modificaciones de código fuente cuando `sdd_state: plan`.
   * `commit-msg`: Exige Conventional Commits y el token de la fase activa (`F<N>`) en cada commit durante `execute`.
4. **Validador Objetivo (`scripts/verify-crit.sh`):**
   Verifica trazabilidad 1:1 de etiquetas `CRIT-XX` en tests reales, audita la historia Git contra commits evasores (`--no-verify`) y ejecuta el test runner del proyecto.

### 3. Directivas para Futuras Mejoras

* **Fuente única en templates:** `assets/AGENTS.md.template`, `assets/PLAN.md.template` y `assets/SESSION.md.template` son canónicos.
* **Workflows autocontenidos:** Según las reglas de `run_workflow`, los scripts en `workflows/*.py` no pueden importar módulos locales entre sí; deben usar únicamente la librería estándar de Python 3.8+ y las primitivas inyectadas (`agent`, `parallel`, `pipeline`, `phase`, `log`, `trajectory`).
* **Priorizar el Bloqueo Duro:** Toda nueva regla verificable debe implementarse como una validación en código (`raise RuntimeError` en `workflows/*.py` o `exit 1` en `scripts/*.sh`), nunca como un consejo en prosa.
