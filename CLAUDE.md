# HAF Block Explorer

Blockchain API for querying Hive transactions, operations, accounts, and witnesses. Built on PostgreSQL/PostgREST with HAF (Hive Application Framework).

## Tech Stack
- **Database**: PostgreSQL 14, PL/pgSQL
- **API**: PostgREST (REST from SQL)
- **Testing**: Tavern (API), pytest, JMeter
- **CI/CD**: GitLab CI, Docker

## Documentation Routing

| Task | Read |
|------|------|
| Architecture/general | `scripts/claude/main.md` |
| Processing/sync | `scripts/claude/processing.md` |
| API endpoints | `scripts/claude/endpoints.md` |
| Tests | `scripts/claude/tests.md` |
| Debugging/CI failures | `scripts/claude/tools.md` |

## External Dependencies

**HAF (Hive Application Framework)**: HAF is installed separately (not a submodule). If you need HAF internals, ASK THE USER where HAF is cloned, then read `<haf_path>/scripts/claude/*.md`.

**Submodules**: For submodule details, read their docs:
- btracker: `submodules/btracker/scripts/claude/`
- reptracker: `submodules/reptracker/scripts/claude/`
- hafah: `submodules/hafah/CLAUDE.md` (basic docs only)

## Expansion Rules

When modifying this project, update the appropriate documentation:
- Processing functions → `scripts/claude/processing.md`
- API endpoints → `scripts/claude/endpoints.md`
- Tests → `scripts/claude/tests.md`
- Utility scripts → `scripts/claude/tools.md`
- Architecture changes → `scripts/claude/main.md`

Always reference new `.md` files from their parent index.
