# Report Format

The eval runner uses a JSON report file as the source of truth.

## Workflow

1. Scaffold a report:

```bash
ruby evals/run_evals.rb scaffold technical-casual
```

2. Fill in the report by hand or with a separate automation step:

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

Optionally write a Markdown scorecard:

```bash
ruby evals/run_evals.rb summarize evals/reports/technical-casual-YYYY-MM-DD.json evals/reports/technical-casual-YYYY-MM-DD.md
```

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
