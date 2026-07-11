# Humanish

Humanish is a collection of agent skills designed to help AI write like a great human writer.

The goal is simple: make AI writing feel sharper, more natural, more specific, and less like it was assembled from familiar patterns.

## What This Repo Holds

Each folder in this repository represents a writing-focused skill, playbook, or style system.

The first collection area is:

- `technical-casual`: skills for explaining technical ideas in a relaxed, clear, human way

## Structure

Each skill should typically include:

- `SKILL.md`: the main instructions for the agent
- supporting references, examples, or notes as needed

The repo also includes:

- `evals/`: evaluation suites, a lightweight runner, and browser-ready report artifacts

## Running Evals

The default eval command is:

```bash
ruby evals/run_evals.rb run technical-casual
```

That creates both of these files by default:

- `evals/reports/technical-casual-YYYY-MM-DD.json`
- `evals/reports/technical-casual-YYYY-MM-DD.html`

The JSON file is the source of truth. The HTML file is the rendered report you can open directly in a browser.

## Direction

Humanish is for writing that sounds like a person with taste, judgment, and a point of view.

That usually means:

- less filler
- fewer canned transitions
- more specificity
- better rhythm
- clearer technical explanation
- stronger voice without losing accuracy
