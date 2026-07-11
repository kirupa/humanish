# Technical Casual Evals

This suite evaluates whether the `technical-casual` skill actually improves technical writing in the ways it promises.

## What We Are Testing

We want to know:

- does the skill trigger for the right prompts?
- does it improve explainers that benefit from intuition-first teaching?
- does it avoid over-applying itself to docs, release notes, or formal writing?
- does it preserve important style constraints such as avoiding double dashes?

## Suite Structure

- `trigger-evals.yaml`
  Prompts where the skill should trigger and prompts where it should stay out of the way.

- `generation-evals.yaml`
  A set of prompts across the major article modes described by the skill:
  design-tradeoff, walkthrough, conversion/model, and toy-implementation.

- `regression-checks.yaml`
  Checks for important style rules and failure modes.

- `rubric.md`
  Human scoring guide for comparing baseline outputs against skill-assisted outputs.

## How To Use This Suite

For each generation eval:

1. Generate a baseline response without the skill.
2. Generate a second response with the skill.
3. Score both responses using `rubric.md`.
4. Record whether the skill materially improved the result.

If you want a prebuilt report shell, run:

```bash
ruby evals/run_evals.rb scaffold technical-casual
```

After scoring the results, validate and summarize with:

```bash
ruby evals/run_evals.rb validate evals/reports/technical-casual-YYYY-MM-DD.json
ruby evals/run_evals.rb summarize evals/reports/technical-casual-YYYY-MM-DD.json
```

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
- forced metaphors or forced tradeoff sections
