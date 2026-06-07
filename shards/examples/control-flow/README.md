# Control Flow Example

This example demonstrates the enhanced control flow constructs in the OcaweCore workflow DSL.

## Features Demonstrated

- **`unless`** - Inverted conditional execution (executes when condition is false)
- **`if/else`** - Standard conditional branching
- **`parallel do...end`** - Concurrent agent execution
- **`while condition do...end`** - Loop while condition is true
- **`until condition do...end`** - Loop until condition becomes true

## Workflow Structure

```
preprocessor (unless skip) -> analyzer -> translator/passthrough -> [validator | formatter] -> finalizer
```

## Usage

```bash
# Run the workflow
curl -X POST http://localhost:8080/v1/workflows/control-flow/runs \
  -H "Content-Type: application/json" \
  -d '{"input": {"skip_preprocessing": false, "needs_translation": true}}'
```

## Notes

- The `unless` block provides cleaner syntax for inverted conditions
- The `while` and `until` loops enable iterative processing with state-based termination
- All control flow constructs support nested agent definitions
