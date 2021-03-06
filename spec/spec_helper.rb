# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  SimpleCov.add_filter do |src_file|
    File.basename(src_file.filename) == 'config.rb'
  end
end

require 'require_all'
require_all 'lib'

def make_test_filename basename
  "spec/tmp/#{basename}"
end

def load_issue key
  Issue.new(raw: JSON.parse(File.read("spec/testdata/#{key}.json")))
end

def defaultCycletimeConfig
  today = Date.parse('2021-12-17')

  block = lambda do |_|
    start_at created
    stop_at last_resolution
  end
  CycleTimeConfig.new parent_config: nil, label: 'default', block: block, today: today
end

def load_complete_sample_issues
  json = JSON.parse(File.read('./spec/complete_sample/sample_0.json'))
  json['issues'].collect { |raw| Issue.new raw: raw }
end

def load_complete_sample_columns
  json = JSON.parse(File.read('./spec/complete_sample/sample_board_1_configuration.json'))
  json['columnConfig']['columns'].collect do |column|
    BoardColumn.new column
  end
end

def load_complete_sample_statuses
  statuses = []

  json = JSON.parse(File.read('./spec/complete_sample/sample_statuses.json'))
  json.each do |type_config|
    issue_type = type_config['name']
    type_config['statuses'].each do |status_config|
      category_config = status_config['statusCategory']
      statuses << Status.new(
        name: status_config['name'], id: status_config['id'],
        category_name: category_config['name'], category_id: category_config['id']
      )
    end
  end
  statuses
end

def load_complete_sample_date_range
  Time.parse('2021-09-14T00:00:00+00:00')..Time.parse('2021-12-13T23:59:59+00:00')
end

def mock_change field:, value:, time:, value_id: 2, old_value: nil, old_value_id: nil, artificial: false
  time = Time.parse(time) if time.is_a? String
  ChangeItem.new time: time, author: 'Tolkien', artificial: artificial, raw: {
    'field' => field,
    'to' => value_id,
    'toString' => value,
    'from' => old_value_id,
    'fromString' => old_value
  }
end

# Pass in a list of [issue, start_time, stop_time] tuples
def mock_cycletime_config stub_values: []
  stub_values.each do |line|
    line[1] = Time.parse(line[1]) if line[1].is_a? String
    line[2] = Time.parse(line[2]) if line[2].is_a? String
  end

  config = CycleTimeConfig.new parent_config: nil, label: nil, block: nil
  config.start_at ->(issue) { stub_values.find { |stub_issue, _start, _stop| stub_issue == issue }&.[](1) }
  config.stop_at  ->(issue) { stub_values.find { |stub_issue, _start, _stop| stub_issue == issue }&.[](2) }
  config
end

# Duplicated from ChartBase. Should this be in a module?
def chart_format object
  if object.is_a? Time
    # "2022-04-09T11:38:30-07:00"
    object.strftime '%Y-%m-%dT%H:%M:%S%z'
  else
    object.to_s
  end
end

def to_time string
  if string =~ /^(\d{4})-(\d{2})-(\d{2})$/
    Time.new $1.to_i, $2.to_i, $3.to_i, 0, 0, 0, '+00:00'
  else
    Time.parse string
  end
end
