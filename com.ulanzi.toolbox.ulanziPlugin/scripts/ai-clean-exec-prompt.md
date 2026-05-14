# Disk Cleanup Executor

The user has confirmed they want to proceed with the cleanup. Execute the commands listed in the CLEANUP COMMANDS section of the report below.

## Execution Rules

1. Execute commands ONE BY ONE in the order listed.
2. Before each command, print what you are about to clean.
3. After each command, print [OK] or [FAIL] with the actual result.
4. If a command fails, continue with the next one — do not stop.
5. Track the total space freed (compare `du` before and after where practical, or use command output).

## Safety Check (redundant but critical)

Even though these commands were pre-validated, do a final safety check before each:

- If a command contains `rm -rf /` or targets system directories → SKIP
- If a command would delete user files (Documents, Desktop, etc.) → SKIP
- If a command targets credentials or SSH keys → SKIP
- Print [SKIPPED: safety violation] for any skipped command

## After All Commands

1. Run `diskutil info /` to get the new disk usage
2. Print a summary:

```
===========================================================
  Cleanup Complete!

  Space freed: XX.X GB
  Disk before: XX% used (XXX/YYY GB)
  Disk after:  XX% used (XXX/YYY GB)

  Commands: N executed, N failed, N skipped
===========================================================
```

## Report to Execute:

{REPORT_CONTENT}
