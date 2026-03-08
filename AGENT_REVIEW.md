# Agent Review

A log of AI/agent mistakes made during development. Use this to identify patterns and avoid repeating errors.

| Date | Mistake | Impact | Correct Approach |
|------|---------|--------|------------------|
| 2026-03-08 | Concepts generated had visual artifacts, ignored racetrack ring design prompt | Code still generated correct output, but wasted iteration time | Ensure concept/code match; trust validated Swift implementations |
| 2026-03-08 | Clock racetrack ring drawn centered on shape path | Ring extends beyond padding bounds | Draw ring inset from bounds, not centered on path |
| 2026-03-08 | Duplicate status text in UI — subtitle in menu + hero clock view | Visual redundancy, confusing UX | Display status in one location only |
| 2026-03-08 | Asked to draw pill-shaped active menubar clock, kept text instead | Clock design incomplete | Replace text with actual pill-shaped visual in active state |
| 2026-03-08 | Failed to add extra padding to menubar clock | Icon too cramped | Add padding property and apply to clock layout |
| 2026-03-08 | Used tuple for timer values instead of struct; helper functions redeclared tuple without connection to values | Poor encapsulation, harder to maintain and extend | Define a struct to group related timer values and attach methods directly to it |
| 2026-03-08 | Embedded strings with no localization | Hardcoded English text limits international use | Extract strings to localization files from the start |
| 2026-03-08 | Generated all single-line strings; had to explicitly request multi-line strings | Incomplete text implementation | Ask for or anticipate multi-line string support in first pass |
