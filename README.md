# try-clone

Clona y sincroniza repositorios de GitHub en un workspace de [`try`](https://github.com/tobi/try).

Destino por defecto: `$HOME/Work/tries` (configurable mediante `TRY_PATH`).

## Características

- **Prefijos canónicos**: asigna automáticamente prefijos `rf-` a repositorios propios y `fo-` a forks.
- **Agrupación en proyectos `pj-*`**: los repositorios se agrupan en sus subdirectorios correspondientes según la configuración declarativa en `~/.config/try-clone/projects.conf` (o ruta indicada por `TRY_CLONE_CONFIG`), con respaldo al `projects.conf` del repositorio.
- **Previsualización en árbol**: renderiza en la terminal la estructura jerárquica de proyectos y repositorios antes de iniciar cualquier operación.
- **Sincronización e idempotencia**:
  - Configura `remote.upstream.skipFetchAll true` si existe remoto `upstream`.
  - Actualiza referencias remotas mediante `git fetch --all --prune`.
  - En árboles limpios, alinea automáticamente con la rama base (`main`/`master`).
  - En árboles sucios (con cambios sin commitear), preserva la rama actual y emite una advertencia para proteger el trabajo local.

## Requisitos

- `bash` (5+)
- [`gh`](https://cli.github.com/) autenticado
- `try` en `PATH`
- `git`

## Uso

```bash
chmod +x try-clone
./try-clone
```

## Configuración de proyectos (`projects.conf`)

Formato: `<proyecto_pj>=<repo1>,<repo2>,...`

Ejemplo:
```ini
pj-fleet=skills,antigravity-fleet,assets,ceo,fleet,robert-flo,sura
pj-funeraria-website=funeraria-monte-tabor,funeraria-monte-tabor-redesign,funeraria-monte-tabor-rediseno
pj-omarchy=omarchy,omarchy-pkgs,omarchy-personal-repo,fork-docs,scratchpad,omarchy-personal-archive-2026-09
pj-paolino=paolino-lab,solco-lab
```
