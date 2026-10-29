# Haystack Co.

Android needle-in-a-haystack dig-then-automate idle game, real 3D in Godot 4.7.2 (Mobile renderer, GDScript; pin and build commands in README.md). Design: [docs/designs/haystack-co.md](docs/designs/haystack-co.md).

- `.idea-to-pr-state.md` is local workflow state. Never commit it (this repo is public).
- Never commit secrets: keystores, `local.properties`, `google-services.json`, catalog private keys.

## Skill routing

When the user's request matches an available skill, invoke it via the Skill tool. Route only to skills in the session's available-skills list; answer directly for quick questions or small scoped edits.

Key routing rules:
- Product ideas/brainstorming → invoke /office-hours
- Strategy/scope → invoke /plan-ceo-review
- Architecture → invoke /plan-eng-review
- Design system/plan review → invoke /design-consultation or /plan-design-review
- Full review pipeline → invoke /autoplan
- Bugs/errors → invoke /investigate
- QA/testing site behavior → invoke /qa or /qa-only
- Code review/diff check → invoke /review
- Visual polish → invoke /design-review
- Ship/deploy/PR → invoke /ship or /land-and-deploy
- Save progress → invoke /context-save
- Resume context → invoke /context-restore
- Author a backlog-ready spec/issue → invoke /spec

## Design System
Read DESIGN.md before visual or UI work: it defines the fonts, colors, spacing, and
aesthetic direction. Ask the user before departing from it. When reviewing or QA-ing
UI, flag code that doesn't match DESIGN.md.
