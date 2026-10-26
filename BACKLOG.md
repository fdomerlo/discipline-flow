# Backlog — Discipline Flow v2.x (Programmatic Workflows)

Mejoras identificadas con retorno medible para próximas iteraciones tras validar la arquitectura base de `workflows/sdd_*.py`:

- [ ] **BKL-01: Pre-inyección de Archivos Objetivo en Python (*Zero-Discovery Overhead* en `sdd_execute.py`)**
  - Leer en Python el contenido de los archivos existentes declarados en `**Archivos objetivo (máx 5):**` de la fase `F<N>` e inyectarlos directamente en el prompt inicial de los agentes **TDD RED** y **TDD GREEN**.
  - **Beneficio esperado:** -3 a -6 llamadas a herramientas (`view_file`) por fase y reducción del ~35-40% en latencia/tokens.

- [ ] **BKL-02: Gate Físico de "True RED" y Anti-Tautología en `sdd_execute.py`**
  - Escanear por regex los archivos creados en el paso RED para bloquear aserciones tautológicas (`assert True`, `expect(true).toBe(true)`).
  - Ejecutar el comando de test tras el paso RED y exigir que falle (`returncode != 0`) antes de iniciar el paso GREEN (salvo flag explícito para tests de caracterización).
  - **Beneficio esperado:** 0% de falsos positivos por tests decorativos a costo de 0 tokens.

- [ ] **BKL-03: Barrera Matemática contra *Scope Creep* Intra-Fase (`files_touched` Diff Guard)**
  - Contrastar en `sdd_execute.py` / `verify-crit.sh` la salida de `git diff --name-only <phase-start>..HEAD` contra los `Archivos objetivo` declarados en `F<N>`. Fallar el gate si se modifican más de 5 archivos o se tocan archivos fuera de lista sin justificación en `deviations`.
  - **Beneficio esperado:** Control 100% determinista del *blast radius* de cada fase a 0 tokens.

- [ ] **BKL-04: Enrutamiento por Tier de Modelo (`model="flash"`) en Auditorías Paralelas**
  - Parametrizar `model=args.get("audit_model", "flash")` en los pasos `parallel()` de `sdd_plan.py` (4 auditores de plan) y `sdd_close.py` (2 auditores de cierre C2), manteniendo `model="inherit"` en el Arquitecto y agentes RED/GREEN.
  - **Beneficio esperado:** Reducción del ~60-70% en latencia y costo de tokens durante las auditorías paralelas.

- [ ] **BKL-05: Minería de Errores Previos con `trajectory()` en `sdd_plan.py`**
  - Consultar `await trajectory(tools=["run_command"], last=10)` en `sdd_plan.py` para extraer automáticamente la salida del último comando con `status == "ERROR"` e inyectarla como evidencia en `Diagnosis / evidence` sin re-ejecutar comandos fallidos.
  - **Beneficio esperado:** 0 re-ejecuciones redundantes al planificar correcciones de bugs.
