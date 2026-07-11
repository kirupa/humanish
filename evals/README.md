# Evals

This folder contains evaluation suites for Humanish skills.

The goal of these evals is not just to check whether a skill can produce output that "looks good." The goal is to verify that the skill creates a measurable improvement over a baseline response and that it activates only when it should.

## Evaluation Layers

Each skill should ideally be evaluated along three layers:

1. `trigger` evals
   These check whether the skill should be used for a given prompt.

2. `generation` evals
   These compare output quality with and without the skill on prompts where the skill should help.

3. `regression` checks
   These guard against known style failures, formatting problems, and rule drift.

## Recommended Method

For generation evals, run each prompt twice:

1. without the skill
2. with the skill

Then score both outputs using the rubric for that skill.

The skill is providing value when:

- the skill-assisted output scores higher on the core rubric dimensions
- correctness does not get worse
- prohibited style regressions do not appear

## Folder Layout

Each skill eval folder should contain:

- `README.md`: suite overview and evaluation philosophy
- `rubric.md`: scoring dimensions and pass criteria
- `trigger-evals.yaml`: prompts that should and should not trigger the skill
- `generation-evals.yaml`: prompts for A/B comparison
- `regression-checks.yaml`: high-priority constraints and failure modes
