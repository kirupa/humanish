#!/usr/bin/env ruby

require "json"
require "yaml"
require "time"
require "fileutils"

ROOT = File.expand_path(__dir__)
REPORTS_DIR = File.join(ROOT, "reports")

RUBRIC_DIMENSIONS = [
  "trigger_fit",
  "intuition_first",
  "teaching_anchor",
  "structure_and_flow",
  "visual_thinking",
  "tone_and_readability",
  "technical_precision",
  "rule_compliance"
].freeze

def usage
  puts <<~TEXT
    Usage:
      ruby evals/run_evals.rb run <skill> [output-base]
      ruby evals/run_evals.rb scaffold <skill> [output.json]
      ruby evals/run_evals.rb validate <report.json>
      ruby evals/run_evals.rb summarize <report.json> [output.md] [output.html]

    Examples:
      ruby evals/run_evals.rb run technical-casual
      ruby evals/run_evals.rb scaffold technical-casual
      ruby evals/run_evals.rb validate evals/reports/technical-casual-2026-07-11.json
      ruby evals/run_evals.rb summarize evals/reports/technical-casual-2026-07-11.json
  TEXT
end

def skill_dir(skill)
  File.join(ROOT, skill)
end

def load_yaml(path)
  YAML.load_file(path)
end

def load_skill_suite(skill)
  dir = skill_dir(skill)
  raise "Missing eval suite for #{skill}: #{dir}" unless Dir.exist?(dir)

  {
    trigger: load_yaml(File.join(dir, "trigger-evals.yaml")),
    generation: load_yaml(File.join(dir, "generation-evals.yaml")),
    regression: load_yaml(File.join(dir, "regression-checks.yaml"))
  }
end

def blank_scores
  RUBRIC_DIMENSIONS.each_with_object({}) { |dimension, memo| memo[dimension] = nil }
end

def default_report_json_path(skill)
  File.join(REPORTS_DIR, "#{skill}-#{Time.now.strftime("%Y-%m-%d")}.json")
end

def normalize_report_json_path(skill, requested_path = nil)
  return default_report_json_path(skill) if requested_path.nil? || requested_path.strip.empty?
  return requested_path if requested_path.end_with?(".json")

  "#{requested_path}.json"
end

def html_report_path_for(json_path)
  json_path.sub(/\.json\z/, ".html")
end

def escape_html(value)
  value.to_s
    .gsub("&", "&amp;")
    .gsub("<", "&lt;")
    .gsub(">", "&gt;")
end

def decision_class(decision)
  case decision
  when "win"
    "decision-win"
  when "loss"
    "decision-loss"
  else
    "decision-tie"
  end
end

def render_html_report(report, output_path)
  trigger_results = report.fetch("trigger_results", [])
  generation_results = report.fetch("generation_results", [])
  summary = report.fetch("summary", {})

  trigger_pass_rate = summary["trigger_pass_rate"]
  generation_success_rate = summary["generation_success_rate"]
  high_priority_failures = summary.fetch("high_priority_regression_failures", [])

  html = <<~HTML
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{escape_html(report.dig("meta", "skill"))} Eval Report</title>
      <style>
        :root {
          --bg: #f6f1e8;
          --paper: #fffdf9;
          --ink: #1a1f1d;
          --muted: #5f685f;
          --line: #ddd2c1;
          --accent: #0f7b6c;
          --accent-soft: #dff4ef;
          --warn: #a2511c;
          --warn-soft: #fff0e4;
          --bad: #8d2331;
          --bad-soft: #fde8eb;
          --good: #176b3a;
          --good-soft: #e4f7ea;
          --mono: "SFMono-Regular", "Menlo", "Consolas", monospace;
          --sans: "Avenir Next", "Segoe UI", system-ui, sans-serif;
          --serif: "Iowan Old Style", "Georgia", serif;
        }
        * { box-sizing: border-box; }
        body {
          margin: 0;
          background:
            radial-gradient(circle at top left, #fff7db 0, rgba(255,247,219,0) 35%),
            linear-gradient(180deg, #f7f2e9 0%, #f3ede2 100%);
          color: var(--ink);
          font-family: var(--sans);
        }
        .page { max-width: 1180px; margin: 0 auto; padding: 40px 24px 64px; }
        .hero, .section, .card {
          background: var(--paper);
          border: 1px solid var(--line);
          box-shadow: 0 12px 32px rgba(44, 36, 26, 0.06);
        }
        .hero {
          border-radius: 24px;
          padding: 28px;
          box-shadow: 0 14px 40px rgba(44, 36, 26, 0.08);
        }
        .eyebrow {
          font-size: 12px;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--muted);
          margin: 0 0 10px;
        }
        h1, h2, h3, h4 { margin: 0; }
        h1 {
          font-family: var(--serif);
          font-size: 42px;
          line-height: 1.05;
          margin-bottom: 12px;
        }
        h2 {
          font-family: var(--serif);
          font-size: 30px;
          margin-bottom: 8px;
        }
        h3 {
          font-size: 20px;
          margin-bottom: 10px;
        }
        .hero p, .section-intro, .notes {
          line-height: 1.6;
          color: #2d332f;
        }
        .meta, .cards, .compare-grid {
          display: grid;
          gap: 16px;
        }
        .meta {
          grid-template-columns: repeat(auto-fit, minmax(180px, max-content));
          gap: 12px;
        }
        .pill {
          border-radius: 999px;
          padding: 8px 12px;
          font-size: 14px;
          background: var(--accent-soft);
          color: #0d5f54;
          border: 1px solid #bfe8de;
        }
        .cards {
          grid-template-columns: repeat(4, minmax(0, 1fr));
          margin-top: 22px;
        }
        .card {
          border-radius: 20px;
          padding: 18px;
        }
        .card h2 {
          font-family: var(--sans);
          font-size: 14px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted);
          margin-bottom: 10px;
        }
        .metric {
          font-size: 42px;
          font-weight: 700;
          line-height: 1;
          margin-bottom: 8px;
        }
        .good { color: var(--good); }
        .warn { color: var(--warn); }
        .bad { color: var(--bad); }
        .section {
          margin-top: 28px;
          border-radius: 24px;
          padding: 24px;
        }
        table {
          width: 100%;
          border-collapse: collapse;
          font-size: 15px;
        }
        th, td {
          text-align: left;
          padding: 12px 10px;
          border-bottom: 1px solid var(--line);
          vertical-align: top;
        }
        th {
          font-size: 12px;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted);
        }
        .decision {
          display: inline-block;
          border-radius: 999px;
          padding: 5px 10px;
          font-size: 12px;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
        }
        .decision-win { background: var(--good-soft); color: var(--good); }
        .decision-loss { background: var(--bad-soft); color: var(--bad); }
        .decision-tie { background: var(--warn-soft); color: var(--warn); }
        .example {
          margin-top: 18px;
          padding-top: 18px;
          border-top: 1px solid var(--line);
        }
        .compare-grid {
          grid-template-columns: repeat(2, minmax(0, 1fr));
          gap: 18px;
          margin-top: 14px;
        }
        .sample {
          border-radius: 18px;
          border: 1px solid var(--line);
          padding: 16px;
          background: #fffdfa;
        }
        .sample h4 {
          margin-bottom: 10px;
          font-size: 13px;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted);
        }
        .sample p {
          margin: 0;
          line-height: 1.7;
          white-space: pre-wrap;
        }
        .sample.baseline { background: var(--warn-soft); border-color: #f0d5be; }
        .sample.skill { background: var(--accent-soft); border-color: #bfe8de; }
        .mono { font-family: var(--mono); font-size: 13px; }
        code { font-family: var(--mono); }
        ul { margin: 12px 0 0 20px; line-height: 1.7; }
        @media (max-width: 980px) {
          .cards { grid-template-columns: repeat(2, minmax(0, 1fr)); }
          .compare-grid { grid-template-columns: 1fr; }
        }
        @media (max-width: 640px) {
          h1 { font-size: 34px; }
          .cards { grid-template-columns: 1fr; }
        }
      </style>
    </head>
    <body>
      <div class="page">
        <section class="hero">
          <p class="eyebrow">Eval Report</p>
          <h1>#{escape_html(report.dig("meta", "skill"))} Evaluation</h1>
          <p>
            Browser-friendly report generated from the JSON report file. This page is created by
            <code>evals/run_evals.rb</code> and is always paired with the JSON report by default.
          </p>
          <div class="meta">
            <span class="pill">Skill: #{escape_html(report.dig("meta", "skill"))}</span>
            <span class="pill">Status: #{escape_html(report.dig("meta", "status") || "unknown")}</span>
            <span class="pill">Generated: #{escape_html(report.dig("meta", "generated_at"))}</span>
          </div>
        </section>

        <section class="cards">
          <article class="card">
            <h2>Trigger Pass Rate</h2>
            <div class="metric #{trigger_pass_rate && trigger_pass_rate >= 80 ? "good" : "warn"}">#{trigger_pass_rate ? "#{trigger_pass_rate}%" : "n/a"}</div>
            <div>#{trigger_results.count { |r| r["pass"] == true }} of #{trigger_results.length} trigger cases passed.</div>
          </article>
          <article class="card">
            <h2>Generation Success</h2>
            <div class="metric #{generation_success_rate && generation_success_rate >= 70 ? "good" : "warn"}">#{generation_success_rate ? "#{generation_success_rate}%" : "n/a"}</div>
            <div>#{generation_results.count { |r| r["decision"] == "win" }} of #{generation_results.length} generation cases were wins.</div>
          </article>
          <article class="card">
            <h2>High-Priority Regressions</h2>
            <div class="metric #{high_priority_failures.empty? ? "good" : "bad"}">#{high_priority_failures.length}</div>
            <div>High-priority regression failures recorded in this report.</div>
          </article>
          <article class="card">
            <h2>Negative Controls</h2>
            <div class="metric warn">#{generation_results.count { |r| r["decision"] == "loss" }}</div>
            <div>Losses can be healthy when the skill is a bad fit for the prompt.</div>
          </article>
        </section>

        <section class="section">
          <h2>Trigger Results</h2>
          <p class="section-intro">These checks verify whether the skill is activating on the right kinds of prompts.</p>
          <table>
            <thead>
              <tr>
                <th>Case</th>
                <th>Expected</th>
                <th>Actual</th>
                <th>Pass</th>
                <th>Notes</th>
              </tr>
            </thead>
            <tbody>
  HTML

  trigger_results.each do |result|
    html << <<~ROW
              <tr>
                <td>#{escape_html(result["title"])}</td>
                <td>#{escape_html(result["expected_trigger"].inspect)}</td>
                <td>#{result["actual_trigger"].nil? ? "n/a" : escape_html(result["actual_trigger"].inspect)}</td>
                <td>#{result["pass"].nil? ? "n/a" : escape_html(result["pass"].inspect)}</td>
                <td>#{escape_html(result["notes"])}</td>
              </tr>
    ROW
  end

  html << <<~HTML
            </tbody>
          </table>
        </section>

        <section class="section">
          <h2>Generation Results</h2>
          <p class="section-intro">These are the A/B cases that compare baseline output against skill-assisted output.</p>
          <table>
            <thead>
              <tr>
                <th>Case</th>
                <th>Mode</th>
                <th>Baseline</th>
                <th>Skill</th>
                <th>Decision</th>
              </tr>
            </thead>
            <tbody>
  HTML

  generation_results.each do |result|
    html << <<~ROW
              <tr>
                <td>#{escape_html(result["title"])}</td>
                <td><span class="mono">#{escape_html(result["mode"])}</span></td>
                <td>#{escape_html((result.dig("baseline", "total") || "n/a").to_s)}</td>
                <td>#{escape_html((result.dig("skill", "total") || "n/a").to_s)}</td>
                <td><span class="decision #{decision_class(result["decision"])}">#{escape_html(result["decision"] || "n/a")}</span></td>
              </tr>
    ROW
  end

  html << <<~HTML
            </tbody>
          </table>
        </section>

        <section class="section">
          <h2>Detailed Comparisons</h2>
          <p class="section-intro">If baseline and skill output excerpts are available in the report JSON, they appear here side by side.</p>
  HTML

  generation_results.each do |result|
    baseline_excerpt = result.dig("baseline", "output_excerpt").to_s
    skill_excerpt = result.dig("skill", "output_excerpt").to_s
    next if baseline_excerpt.empty? && skill_excerpt.empty?

    html << <<~EXAMPLE
          <div class="example">
            <h3>#{escape_html(result["title"])}</h3>
            <div class="compare-grid">
              <div class="sample baseline">
                <h4>Baseline</h4>
                <p>#{escape_html(baseline_excerpt)}</p>
              </div>
              <div class="sample skill">
                <h4>Skill-Assisted</h4>
                <p>#{escape_html(skill_excerpt)}</p>
              </div>
            </div>
          </div>
    EXAMPLE
  end

  html << <<~HTML
        </section>
      </div>
    </body>
    </html>
  HTML

  FileUtils.mkdir_p(File.dirname(output_path))
  File.write(output_path, html)
  puts "Wrote HTML report: #{output_path}"
end

def scaffold_report(skill, output_path = nil, render_html: true)
  suite = load_skill_suite(skill)
  FileUtils.mkdir_p(REPORTS_DIR)

  output_path = normalize_report_json_path(skill, output_path)

  report = {
    "meta" => {
      "skill" => skill,
      "generated_at" => Time.now.iso8601,
      "report_version" => 1,
      "status" => "draft"
    },
    "trigger_results" => suite[:trigger]["cases"].map do |case_data|
      {
        "id" => case_data["id"],
        "title" => case_data["title"],
        "expected_trigger" => case_data["should_trigger"],
        "actual_trigger" => nil,
        "pass" => nil,
        "notes" => ""
      }
    end,
    "generation_results" => suite[:generation]["cases"].map do |case_data|
      {
        "id" => case_data["id"],
        "title" => case_data["title"],
        "mode" => case_data["mode"],
        "baseline" => {
          "scores" => blank_scores,
          "total" => nil,
          "notes" => ""
        },
        "skill" => {
          "scores" => blank_scores,
          "total" => nil,
          "notes" => ""
        },
        "regression_failures" => [],
        "decision" => nil,
        "notes" => ""
      }
    end,
    "summary" => {
      "trigger_pass_rate" => nil,
      "generation_success_rate" => nil,
      "high_priority_regression_failures" => [],
      "overall_notes" => ""
    }
  }

  File.write(output_path, JSON.pretty_generate(report) + "\n")
  puts "Scaffolded report: #{output_path}"
  render_html_report(report, html_report_path_for(output_path)) if render_html
  output_path
end

def ensure_score_range!(case_id, label, scores)
  scores.each do |dimension, value|
    next if value.nil?
    unless value.is_a?(Integer) && value.between?(0, 2)
      raise "#{case_id} #{label} score for #{dimension} must be an integer between 0 and 2"
    end
  end
end

def compute_total(scores)
  values = scores.values
  return nil if values.any?(&:nil?)
  values.sum
end

def validate_report(report_path)
  report = JSON.parse(File.read(report_path))
  errors = []

  unless report.dig("meta", "skill")
    errors << "Missing meta.skill"
  end

  report.fetch("trigger_results", []).each do |result|
    if !result["actual_trigger"].nil? && ![true, false].include?(result["actual_trigger"])
      errors << "#{result['id']} actual_trigger must be true, false, or null"
    end
    if !result["pass"].nil? && ![true, false].include?(result["pass"])
      errors << "#{result['id']} pass must be true, false, or null"
    end
  end

  report.fetch("generation_results", []).each do |result|
    begin
      ensure_score_range!(result["id"], "baseline", result.fetch("baseline").fetch("scores"))
      ensure_score_range!(result["id"], "skill", result.fetch("skill").fetch("scores"))
    rescue => e
      errors << e.message
    end

    if !result["decision"].nil? && !%w[win tie loss].include?(result["decision"])
      errors << "#{result['id']} decision must be win, tie, loss, or null"
    end
  end

  if errors.empty?
    puts "Validation passed: #{report_path}"
    true
  else
    puts "Validation failed: #{report_path}"
    errors.each { |error| puts "  - #{error}" }
    false
  end
end

def summarize_report(report_path, markdown_path = nil, html_path = nil)
  report = JSON.parse(File.read(report_path))
  skill = report.dig("meta", "skill")
  skill_suite = load_skill_suite(skill)

  trigger_results = report.fetch("trigger_results", [])
  generation_results = report.fetch("generation_results", [])
  regression_checks = skill_suite[:regression]["checks"]

  trigger_completed = trigger_results.count { |result| !result["pass"].nil? }
  trigger_passes = trigger_results.count { |result| result["pass"] == true }
  trigger_pass_rate = trigger_completed.zero? ? nil : (trigger_passes.to_f / trigger_completed * 100).round(1)

  generation_completed = generation_results.count { |result| !result["decision"].nil? }
  generation_wins = generation_results.count { |result| result["decision"] == "win" }
  generation_success_rate = generation_completed.zero? ? nil : (generation_wins.to_f / generation_completed * 100).round(1)

  high_priority_regression_ids = regression_checks
    .select { |check| check["priority"] == "high" }
    .map { |check| check["id"] }

  high_priority_failures = generation_results.flat_map do |result|
    result.fetch("regression_failures", []).select { |id| high_priority_regression_ids.include?(id) }
      .map { |id| "#{result['id']}: #{id}" }
  end

  generation_results.each do |result|
    result["baseline"]["total"] = compute_total(result["baseline"]["scores"])
    result["skill"]["total"] = compute_total(result["skill"]["scores"])
  end

  report["summary"]["trigger_pass_rate"] = trigger_pass_rate
  report["summary"]["generation_success_rate"] = generation_success_rate
  report["summary"]["high_priority_regression_failures"] = high_priority_failures

  File.write(report_path, JSON.pretty_generate(report) + "\n")
  render_html_report(report, html_path || html_report_path_for(report_path))

  lines = []
  lines << "# Eval Report"
  lines << ""
  lines << "- Skill: `#{skill}`"
  lines << "- Report: `#{File.basename(report_path)}`"
  lines << "- Trigger pass rate: #{trigger_pass_rate.nil? ? 'n/a' : "#{trigger_pass_rate}%"}"
  lines << "- Generation success rate: #{generation_success_rate.nil? ? 'n/a' : "#{generation_success_rate}%"}"
  lines << "- High-priority regression failures: #{high_priority_failures.empty? ? '0' : high_priority_failures.length}"
  lines << ""
  lines << "## Generation Results"
  lines << ""

  generation_results.each do |result|
    lines << "- `#{result['id']}` #{result['title']}: baseline=#{result['baseline']['total'] || 'n/a'}, skill=#{result['skill']['total'] || 'n/a'}, decision=#{result['decision'] || 'n/a'}"
  end

  unless high_priority_failures.empty?
    lines << ""
    lines << "## High-Priority Regression Failures"
    lines << ""
    high_priority_failures.each do |failure|
      lines << "- #{failure}"
    end
  end

  markdown = lines.join("\n") + "\n"
  puts markdown

  if markdown_path
    FileUtils.mkdir_p(File.dirname(markdown_path))
    File.write(markdown_path, markdown)
    puts "Wrote markdown summary: #{markdown_path}"
  end
end

def run_eval_suite(skill, output_path = nil)
  json_path = scaffold_report(skill, output_path, render_html: false)
  summarize_report(json_path)
end

command = ARGV.shift

case command
when "run"
  skill = ARGV.shift
  if skill.nil?
    usage
    exit 1
  end
  run_eval_suite(skill, ARGV.shift)
when "scaffold"
  skill = ARGV.shift
  if skill.nil?
    usage
    exit 1
  end
  scaffold_report(skill, ARGV.shift)
when "validate"
  report_path = ARGV.shift
  if report_path.nil?
    usage
    exit 1
  end
  exit(validate_report(report_path) ? 0 : 1)
when "summarize"
  report_path = ARGV.shift
  if report_path.nil?
    usage
    exit 1
  end
  summarize_report(report_path, ARGV.shift, ARGV.shift)
else
  usage
  exit 1
end
