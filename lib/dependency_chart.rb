# frozen_string_literal: true

require './lib/chart_base'
require 'open3'

class Rules
  def ignore
    @ignore = true
  end

  def ignored?
    @ignore
  end
end

class DependencyChart < ChartBase
  class LinkRules < Rules
    attr_accessor :line_color, :label
  end

  def initialize rules_block
    super()
    @rules_block = rules_block
    @link_rules_block = ->(link_name, link_rules) {}
  end

  def run
    instance_eval(&@rules_block) if @rules_block

    svg = execute_graphviz(build_dot_graph.join("\n"))
    "<h1>Dependencies</h1>#{svg}"
  end

  def link_rules &block
    @link_rules_block = block
  end

  def find_links
    result = []
    issues.each do |issue|
      result += issue.issue_links
    end
    result
  end

  def make_dot_link issue_link:, link_rules:
    result = String.new
    result << issue_link.origin.key.inspect
    result << ' -> '
    result << issue_link.other_issue.key.inspect
    result << '['
    result << 'label=' << (link_rules.label || issue_link.label).inspect
    result << ',color=' << (link_rules.line_color || 'black').inspect
    result << '];'
    result
  end

  def make_dot_issue issue_key:, issue_type_rules:
    result = String.new
    result << issue_key.inspect
    result << '['
    result << "label=\"#{issue_key}|Story\""
    result << ',shape=Mrecord,style=filled,fillcolor="#FFCCFF"]'
    result
  end

  def build_dot_graph
    issue_links = find_links

    issue_keys = Set.new
    link_graph = []

    issue_links.each do |link|
      link_rules = LinkRules.new
      @link_rules_block.call link.name, link_rules
      next if link_rules.ignored?

      link_graph << make_dot_link(issue_link: link, link_rules: link_rules)

      issue_keys << link.origin.key
      issue_keys << link.other_issue.key
    end

    dot_graph = []
    dot_graph << 'digraph mygraph {'
    dot_graph << 'rankdir=LR'

    # Sort the keys so they are proccessed in a deterministic order.
    issue_keys.to_a.sort.each do |key|
      dot_graph << make_dot_issue(issue_key: key, issue_type_rules: nil)
    end

    dot_graph += link_graph
    dot_graph << '}'
    dot_graph
  end

  def execute_graphviz dot_graph
    Open3.popen3('dot -Tsvg') do |stdin, stdout, _stderr, _wait_thread|
      stdin.write dot_graph
      stdin.close
      return stdout.read
    end
  rescue => e # rubocop:disable Style/RescueStandardError
    message = "Unable to execute the command 'dot' which is part of graphviz. " \
      'Ensure that graphviz is installed and that dot is in your path.'
    puts message, e, e.backtrace
    message
  end
end
