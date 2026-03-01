try:
    from _lib.approval_constants import MODE_ALLOWED, MODE_SOURCE_ALLOWED
except ModuleNotFoundError:
    MODE_ALLOWED = {"impl", "tdd", "custom"}
    MODE_SOURCE_ALLOWED = {"agent-heuristic", "user-choice", "operator-override"}
