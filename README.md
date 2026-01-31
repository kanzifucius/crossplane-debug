# crossplane-debug

Debug Crossplane compositions, functions (KCL, Go templates, patch-and-transform, auto-ready), and managed resources - a skill for AI coding agents.

## Features

- Debug composition rendering issues with `crossplane beta render`
- Extract compositions from remote clusters for local debugging
- Troubleshoot function execution (KCL, Go templates, patch-and-transform)
- Diagnose resource creation failures and dependency problems
- Trace claim/XR status and managed resource conditions
- Common error patterns and solutions reference

## Installation

```bash
npx skills add kanzifucius/crossplane-debug
```

You'll be prompted to select which AI agents to install to.

### Install to specific agents

```bash
npx skills add kanzifucius/crossplane-debug -a claude-code -a opencode
```

## Supported Agents

This skill works with 40+ AI coding agents including:

- OpenCode
- Claude Code
- Cursor
- Codex
- GitHub Copilot
- Windsurf
- And many more...

See the full list at [skills.sh](https://skills.sh).

## Usage

After installation, the skill is automatically triggered when working with Crossplane resources. Keywords that activate the skill:

- "crossplane"
- "composition"
- "XR" / "composite resource"
- "claim"
- "function-kcl"
- "managed resource"

### Example Prompts

```
"Debug why my XR isn't creating resources"
"Help me troubleshoot this Crossplane composition"
"The function-kcl step is failing, can you help?"
"Extract the composition from my cluster for local debugging"
```

### Manual Extraction Script

The skill includes a helper script for extracting compositions from remote clusters:

```bash
# After installation, find the script in your agent's skill directory
./scripts/extract-composition.sh <composition-name> [xr-kind] [xr-name]

# Examples:
./scripts/extract-composition.sh my-database-composition
./scripts/extract-composition.sh my-app-composition XMyApp my-app-instance
```

This creates a `debug-<composition-name>/` directory with all files needed for `crossplane beta render`.

## What's Included

```
skills/crossplane-debug/
├── SKILL.md                      # Main skill instructions
├── scripts/
│   └── extract-composition.sh    # Cluster extraction helper
└── references/
    ├── common-errors.md          # Error patterns and solutions
    └── kcl-patterns.md           # KCL syntax patterns for compositions
```

## Debugging Workflow

The skill guides you through a systematic debugging approach:

```
Issue reported
    |
    v
Do you have composition files locally?
    |
    +--NO--> Extract from cluster first
    |        Run: scripts/extract-composition.sh
    |
    +--YES--> Is the composition rendering correctly?
                 |
                 +--NO--> Run `crossplane beta render` locally
                 |
                 +--YES--> Are resources being created?
                              |
                              +--NO--> Check XR/Claim status
                              |        Run `crossplane beta trace`
                              |
                              +--YES--> Are resources Ready?
                                           |
                                           +--NO--> Check managed resource conditions
                                           |
                                           +--YES--> Issue is external to Crossplane
```

## Requirements

- kubectl (for cluster debugging)
- crossplane CLI (for `beta render` and `beta trace`)

## License

MIT

## Links

- [GitHub Repository](https://github.com/kanzifucius/crossplane-debug)
- [skills.sh](https://skills.sh) - Universal skills manager
- [Crossplane Documentation](https://docs.crossplane.io)
