# Report Format

The eval runner uses a JSON report file as the source of truth and generates a matching HTML report for browser viewing.

## Workflow

1. Run the suite:

```bash
ruby evals/run_evals.rb run technical-casual
```

By default, this creates:

- `evals/reports/technical-casual-YYYY-MM-DD.json`
- `evals/reports/technical-casual-YYYY-MM-DD.html`

You can also provide your own output base:

```bash
ruby evals/run_evals.rb run technical-casual evals/reports/technical-casual-demo
```

That creates:

- `evals/reports/technical-casual-demo.json`
- `evals/reports/technical-casual-demo.html`

2. Fill in the JSON report by hand or with a separate automation step:

- mark trigger outcomes
- score baseline and skill-assisted outputs
- record regression failures
- record the decision for each generation case as `win`, `tie`, or `loss`

3. Validate the report:

```bash
ruby evals/run_evals.rb validate evals/reports/technical-casual-YYYY-MM-DD.json
```

4. Summarize the report:

```bash
ruby evals/run_evals.rb summarize evals/reports/technical-casual-YYYY-MM-DD.json
```

This updates the JSON summary fields and regenerates the matching HTML report.

Optionally write a Markdown scorecard too:

```bash
ruby evals/run_evals.rb summarize evals/reports/technical-casual-YYYY-MM-DD.json evals/reports/technical-casual-YYYY-MM-DD.md
```

If you want to use the lower-level scaffold step directly, it also writes both artifacts:

```bash
ruby evals/run_evals.rb scaffold technical-casual
```

That command creates a draft JSON report and a matching draft HTML view.

## JSON Shape

Each report contains:

- `meta`
- `trigger_results`
- `generation_results`
- `summary`

## Trigger Results

Each trigger result includes:

- `id`
- `title`
- `expected_trigger`
- `actual_trigger`
- `pass`
- `notes`

## Generation Results

Each generation result includes:

- `id`
- `title`
- `mode`
- `baseline`
- `skill`
- `regression_failures`
- `decision`
- `notes`

The `baseline` and `skill` objects each contain:

- `scores`
- `total`
- `notes`

The score keys are:

- `trigger_fit`
- `intuition_first`
- `teaching_anchor`
- `structure_and_flow`
- `visual_thinking`
- `tone_and_readability`
- `technical_precision`
- `rule_compliance`

Each score must be an integer from `0` to `2`.

## Decision Semantics

For generation cases:

- `win`: the skill-assisted version is better
- `tie`: there is no material difference
- `loss`: the baseline is better

## Regression Failures

`regression_failures` should contain check IDs from `regression-checks.yaml`.

Example:

```json
["tc_reg_001", "tc_reg_007"]
```

## Summary Fields

The runner computes:

- `trigger_pass_rate`
- `generation_success_rate`
- `high_priority_regression_failures`

You can still add notes in:

- `summary.overall_notes`

## HTML Output

The generated HTML report is intended to be committed when it is useful as a readable artifact or demo.

It should:

- mirror the JSON report content
- render cleanly in a browser without extra tooling
- stay in sync whenever `run` or `summarize` is used
