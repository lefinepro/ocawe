# Examples

Examples live under `shards/cogni/shards/examples` and cover:
- agents
- skills
- workflow composition
- voice DSL
- rag DSL

Examples are not loaded by default runtime discovery (`src/workflows`).
Use explicit workflow root override when you want to run examples in isolation.

Example:

```bash
./build/cognicore --port 4111 --workflows-root ./shards/examples --fallback-workflows-root ./shards/examples
```
