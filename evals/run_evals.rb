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
      ruby evals/run_evals.rb scaffold <skill> [output.json]
      ruby evals/run_evals.rb validate <report.json>
      ruby evals/run_evals.rb summarize <report.json> [output.md]

    Examples:
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

def scaffold_report(skill, output_path = nil)
  suite = load_skill_suite(skill)
  FileUtils.mkdir_p(REPORTS_DIR)

  output_path ||= File.join(REPORTS_DIR, "#{skill}-#{Time.now.strftime("%Y-%m-%d")}.json")

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

def summarize_report(report_path, markdown_path = nil)
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

command = ARGV.shift

case command
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
  summarize_report(report_path, ARGV.shift)
else
  usage
  exit 1
end
