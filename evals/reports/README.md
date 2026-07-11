# Reports

This folder stores generated eval reports and Markdown summaries.

Typical flow:

1. Scaffold a report JSON with `ruby evals/run_evals.rb scaffold <skill>`
2. Fill in results
3. Validate with `ruby evals/run_evals.rb validate <report.json>`
4. Summarize with `ruby evals/run_evals.rb summarize <report.json>`
