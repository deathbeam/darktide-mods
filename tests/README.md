# Tests

Tests are kept outside mod directories so they are never included in release packages.

Run the current suite with:

```bash
make test
```

The shared Darktide mock covers deterministic module behavior. In-game regression testing is still required for the real action-input parser, weapon templates, and state-machine hooks.
