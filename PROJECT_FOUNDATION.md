## Project Foundation: Discipline-Flow

**Propósito Principal:**
`discipline-flow` es un arnés de contención determinista diseñado para forzar la adopción estricta de Specification-Driven Development (SDD) en entornos de trabajo asistidos por IA. Su objetivo es eliminar el "desvío de especificación" (specification drift) y el sesgo a la acción de los Modelos de Lenguaje Grande (LLMs) sustituyendo las instrucciones textuales blandas por barreras físicas inquebrantables a nivel de sistema operativo y control de versiones.

### 1. Filosofía de Diseño (Core Tenets)

* **Restricciones Duras sobre Prompts Blandos:** Los LLMs ignoran las instrucciones sistémicas cuando la ventana de contexto crece. Este sistema asume que el modelo intentará romper las reglas y delega la aplicación del flujo SDD a Git Hooks y scripts POSIX.
* **Cero Dependencias (Zero-Dependency):** Construido íntegramente en Bash puro y utilidades coreutils (`sed`, `awk`, `grep`). No requiere demonios en segundo plano, entornos de Python, ni servidores MCP que consuman tokens innecesariamente.
* **Estado Inmutable:** El estado del proyecto no reside en la memoria volátil del LLM, sino en un bloque YAML físico y estructurado que actúa como fuente de verdad.

### 2. Arquitectura de Componentes

El sistema se compone de un controlador central, una fuente de verdad y un muro de contención físico:

* **Fuente de Verdad (`assets/SESSION.md.template`):**
Contiene un bloque Frontmatter YAML estricto al inicio del archivo que define la fase actual (`sdd_state`), la tarea en curso (`active_task`) y el hash de la especificación (`plan_hash`). Es la única base de datos del flujo.
* **El Controlador (`scripts/sdd.sh`):**
El motor de transición de estado. Es el *único* ciudadano autorizado para mutar el bloque YAML en `SESSION.md` mediante comandos como `advance` o `start`.
* **El Muro de Contención (`scripts/pre-commit-hook.sh` & `scripts/commit-msg-hook.sh`):**
Interceptan las transacciones de código base. El `pre-commit` lee el estado YAML; si el estado es `plan`, rechaza cualquier modificación a archivos de código fuente (exit code 1). El `commit-msg-hook.sh` exige trazabilidad vinculando los commits a la `active_task` durante la fase `execute`.
* **Validador Objetivo (`scripts/verify-crit.sh`):**
Evalúa sintácticamente el cumplimiento de la especificación sin depender de la interpretación subjetiva del agente IA.

### 3. Modelo de Interacción para Agentes IA

Cualquier agente que opere en este repositorio (Gemini, Antigravity, OpenCode, Claude Code) debe adherirse a este contrato de interacción:

1. **Mutación Prohibida:** El agente tiene estrictamente prohibido editar manualmente el bloque YAML de `SESSION.md`.
2. **Interacción vía CLI:** Todo cambio de fase o inicio de tarea debe canalizarse ejecutando `./scripts/sdd.sh` en la terminal (ej. mapeado a través de Slash Commands como `/plan` o `/execute <tarea>`).
3. **Conciencia de Barrera:** Si la terminal devuelve un error (exit code 1) tras un intento de commit, el agente debe detener la generación de código inmediatamente, leer el volcado de error de Git, e invocar el comando CLI correcto para alinear el estado del sistema con su intención de desarrollo.

### 4. Directivas para Futuras Mejoras (Agent Guidelines)

Si un agente es invocado para expandir, refactorizar o agregar características a `discipline-flow`, debe cumplir obligatoriamente las siguientes restricciones:

* **No introducir dependencias externas:** Queda prohibido el uso de `jq`, `yq`, Python, Node.js o servidores MCP. Toda lógica de parseo debe resolverse con `awk`, `sed` y `grep` nativos.
* **Mantener la Portabilidad:** Los scripts deben ejecutar sin modificaciones en shells bash/zsh bajo entornos Linux (Fedora, Debian, contenedores LXC).
* **Priorizar el Bloqueo:** Cualquier nueva funcionalidad de validación (ej. chequeo de cobertura de tests) debe implementarse como un bloqueo duro (hard fail) que aborte el proceso si no se cumplen los criterios, nunca como una advertencia (warning) pasiva.
