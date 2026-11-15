# Rule: Never Touch Working Functionality Without Explicit Instruction

## Core Principle
If any feature, screen, navigation route, network mode, or function is currently working, **IT IS LOCKED**. You must **NEVER** touch, modify, refactor, reorganize, optimize, or "clean up" that code or any shared logic that could impact it unless the user explicitly, specifically, and exclusively instructs you to change that exact feature.

## Strict Rules
1. **Zero Unsolicited Modifications**:
   - Working features (Receive Mode, Send Mode, File Selection, Web Client, Chat Rooms, Internet Tunnels, QR Codes, Transfers) are strictly protected against any unsolicited changes.
   - Do NOT touch surrounding code, shared utilities, or unrelated files when fixing a bug or adding a new feature.
2. **Strict Blast Radius Isolation**:
   - When asked to add or fix a feature in one area (e.g., Chat Room or Background execution), changes MUST be strictly isolated to that specific area's files.
   - You must NEVER modify shared core files (such as `app.js`, `server_engine.dart`, `server_provider.dart`, `file_handler.dart`) in a way that introduces side-effects, new timing loops, locks, or altered behavior to unrelated working modes (e.g., local Wi-Fi Receive Mode or Send Mode).
3. **No Speculative Refactors**:
   - Do not "clean up", reformat, rename variables, or alter state management patterns in working modules without explicit instruction.
4. **Mandatory Regression Prevention**:
   - Always run unit tests (`flutter test`) and static analysis (`flutter analyze`) before declaring work complete.
