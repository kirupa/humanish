# Technical Casual Evals

This suite evaluates whether the `technical-casual` skill actually improves technical writing in the ways it promises.

The suite is intentionally broad. It covers both computer topics and non-computer technical topics so we can verify that the skill generalizes across technical domains instead of quietly collapsing back into developer-only writing.

## What We Are Testing

We want to know:

- does the skill trigger for the right prompts?
- does it improve explainers that benefit from intuition-first teaching?
- does it work well outside software topics, including engineering, math, electrical systems, manufacturing, and physics-flavored explainers?
- does it avoid over-applying itself to docs, release notes, or formal writing?
- does it stay out of softer subjects like history and philosophy where the format is a poor fit?
- does it preserve important style constraints such as avoiding double dashes?

## Suite Structure

- `trigger-evals.yaml`
  Prompts where the skill should trigger and prompts where it should stay out of the way.

- `generation-evals.yaml`
  A set of prompts across the major article modes described by the skill:
  design-tradeoff, walkthrough, conversion/model, and toy-implementation.
  The suite includes software, mechanical, electrical, mathematical, thermal, and manufacturing examples, plus negative controls.

- `regression-checks.yaml`
  Checks for important style rules and failure modes.

- `rubric.md`
  Human scoring guide for comparing baseline outputs against skill-assisted outputs.

## How To Use This Suite

The easiest way to start is:

```bash
ruby evals/run_evals.rb run technical-casual
```

That command always creates both:

- `evals/reports/technical-casual-YYYY-MM-DD.json`
- `evals/reports/technical-casual-YYYY-MM-DD.html`

The JSON file is the editable report data. The HTML file is the rendered browser view of the same report.

For each generation eval:

1. Generate a baseline response without the skill.
2. Generate a second response with the skill.
3. Score both responses using `rubric.md`.
4. Record whether the skill materially improved the result.

After scoring the results, validate and summarize with:

```bash
ruby evals/run_evals.rb validate evals/reports/technical-casual-YYYY-MM-DD.json
ruby evals/run_evals.rb summarize evals/reports/technical-casual-YYYY-MM-DD.json
```

`summarize` recalculates the summary fields and refreshes the HTML output automatically.

## Coverage Map

Representative domains currently covered:

- software and computing
- mechanical systems
- electrical systems
- math and statistics
- manufacturing processes
- physical systems and energy transfer

Representative non-fit boundaries currently covered:

- history prompts
- philosophy prompts
- checklist and reference-style writing

## What Counts As Value

The skill is providing value when it improves:

- clarity
- intuition-building
- structural teaching quality
- visual thinking
- tone and readability

without introducing:

- generic hype language
- over-stylized fluff
- broken technical precision
- double dashes
- software-default framing on non-computer topics
- forced metaphors or forced tradeoff sections
