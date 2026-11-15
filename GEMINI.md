# Project Rules — CloudPocket

## CRITICAL MANDATORY GUARDRAIL: ZERO UNSOLICITED TOUCH POLICY
If any functionality, UI layout, screen, server route, network mode, or feature is currently working:
- **DO NOT TOUCH IT.**
- **DO NOT REFACTOR IT.**
- **DO NOT OPTIMIZE IT.**
- **DO NOT ALTER ITS BEHAVIOR.**
- **DO NOT TOUCH SHARED CODE THAT COULD IMPACT IT.**

Changes must strictly and exclusively be isolated to the exact lines or files requested by the user. If an issue is reported in Feature A (e.g., chat room or background screen-off), you must NEVER modify shared utilities in ways that introduce side effects into Feature B (e.g., local Wi-Fi Receive Mode or file transfers).
