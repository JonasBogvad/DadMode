# Tests

Three scripts that run DadMode against a stand-in for the game, written in Lua inside each script. They check the addon's logic. They cannot tell how the real WoW Forever client behaves.

```
pip install lupa
python3 tests/dadtest.py Core.lua        # a fresh install
python3 tests/dadtest_lib.py Core.lua    # an existing install, with the minimap button library present
python3 tests/dadtest_opt.py Core.lua    # settings, permissions, whispers, travel, gear and the rest
```

Run them from the addon folder. Each prints `TESTS_PASSED` or `OPTIONS_TESTS_PASSED` at the end. The files are loaded in the order of `DadMode.toc`, the way the game does it.
