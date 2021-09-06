require 'cgi'
require 'json'

class Downloader
	OUTPUT_PATH = 'target/'

	def initialize
        load_jira_config
        Config.instances.each do |config|
            download_issues config
        end
    end

    def load_jira_config
		jira_config = JSON.parse File.read('jira_config.json')
		@jira_url = jira_config['url']
		@jira_email = jira_config['email']
		@jira_api_token = jira_config['api_token']
	end

    def call_command command
        puts '----', command.gsub(/\s+/, ''), ''
        `#{command}`
    end
	def download_issues config
        output_file_prefix = config.file_prefix
		jql = CGI.escape config.jql
		max_results = 100
		start_at = 0
		total = 1
        while start_at < total
            command = <<-COMMAND
            	curl --request GET \
            	--url "#{ @jira_url }/rest/api/2/search?jql=#{ jql }&maxResults=#{max_results}&startAt=#{start_at}&expand=changelog" \
                --user #{ @jira_email }:#{ @jira_api_token } \
                --header "Accept: application/json"
            COMMAND

            json = JSON.parse call_command(command)
            if json['errorMessages']
            	puts JSON.pretty_generate(json)
            	exit 1
            end
            output_file = "#{OUTPUT_PATH}#{output_file_prefix}_#{start_at}.json"
            File.open(output_file, 'w') do |file|
            	file.write(JSON.pretty_generate(json))
            end
            total = json['total'].to_i
            max_results = json['maxResults']
            start_at += json['issues'].size
        end
        # self.create_meta_json(output_file_prefix, meta_data)
    end

    def download_columns output_file_prefix, board_id
		command = <<-COMMAND
			curl --request GET \
            --url #{@jira_url}/rest/agile/1.0/board/#{board_id}/configuration \
            --user #{@jira_email}:#{@jira_api_token} \
            --header "Accept: application/json"
         COMMAND

        json = JSON.parse call_command(command)
        if json['errorMessages']
        	puts JSON.pretty_generate(json)
        	exit 1
        end

        output_file = "#{OUTPUT_PATH}#{output_file_prefix}_configuration.json"
        File.open(output_file, 'w') do |file|
        	file.write(JSON.pretty_generate(json))
        end

        puts command
    end
end

# if __FILE__ == $0
#     downloader = Downloader.new
#     downloader.download_columns 'foo', 1
#     downloader.download_issues 'foo'
# end
