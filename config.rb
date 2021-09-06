require './extract_cycle_times'
require 'csv'

# The goal was to make both the configuration itself and the issue/loader
# objects easy to read so the tricky (specifically meta programming) parts 
# are all in here. Be cautious when changing this file.
class ConfigBase
	class ExportColumns < BasicObject
		attr_reader :columns
		def initialize = @columns = []

		def date label, block
			@columns << [:date, label, block]
		end

		def string label, block
			@columns << [:string, label, block]
		end

		def method_missing method_name, *args, &block
			-> (issue) { issue.__send__ method_name, *args }
		end
	end

	attr_reader :issues

	def self.export prefix:, project: nil, filter: nil, jql: nil, &block
		instance = ConfigBase.new prefix: prefix, project: project, filter: filter, jql: jql
		instance.instance_eval &block
	end

	def initialize prefix:, project:, filter:, jql:, &block
		@csv_filename = "target/#{prefix}.csv"
		@issues = Extractor.new(prefix).run
	end

	def columns write_headers: true, &block
		columns = ExportColumns.new
		columns.instance_eval &block

		File.open(@csv_filename, 'w') do |file|
			if write_headers
				line = columns.columns.collect { |type, label, proc| label }
				file.puts CSV.generate_line(line)
			end
			issues.each do |issue|
				line = []
				columns.columns.each do |type, name, block|
					# Invoke the block that will retrieve the result from Issue
					result = instance_exec(issue, &block)
					# Convert that result to the appropriate type
					line << __send__(:"to_#{type}", result)
				end
				file.puts CSV.generate_line(line)
			end
		end
	end

	# TODO: to_date needs to know which timezone we're converting to.
	def to_date object
		object.to_date
	end

	def to_string object
		object.to_s
	end

end

class Config < ConfigBase
	export prefix: 'foo', project: 'SP' do
		issues.each do |issue|
			# Remove specific changes that we want to ignore
		end

		columns write_headers: true do
			date 'Start', first_time_not_in_status('Backlog')
		    date 'Done', last_time_in_status('Done')
		    string 'Type', type
		    string 'Key', key
		    string 'Summary', summary
		end
	end
end
