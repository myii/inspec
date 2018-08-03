# encoding: utf-8

require 'json'
require 'net/http'

module Inspec::Reporters
  class Automate < JsonMerged
    def initialize(config)
      super(config)

      # allow the insecure flag
      @config['verify_ssl'] = !@config['insecure'] if @config.key?('insecure')

      # default to not verifying ssl for sending reports
      @config['verify_ssl'] = @config['verify_ssl'] || false
    end

    def enriched_report
      # grab the report from the parent class
      final_report = report_merged

      # Label this content as an inspec_report
      final_report[:type] = 'inspec_report'

      final_report[:end_time] = Time.now.utc.strftime('%FT%TZ')
      final_report[:node_uuid] = @config['node_uuid'] || @run_data[:platform][:uuid]
      raise Inspec::ReporterError, 'Cannot find a UUID for your node. Please specify one via json-config.' if final_report[:node_uuid].nil?

      final_report[:report_uuid] = @config['report_uuid'] || uuid_from_string(final_report[:end_time] + final_report[:node_uuid])

      # optional json-config passthrough options
      %w{node_name environment roles recipies job_uuid}.each do |option|
        final_report[option.to_sym] = @config[option] unless @config[option].nil?
      end
      final_report
    end

    def send_report
      headers = { 'Content-Type' => 'application/json' }
      headers['x-data-collector-token'] = @config['token']
      headers['x-data-collector-auth'] = 'version=1.0'

      uri = URI(@config['url'])
      req = Net::HTTP::Post.new(uri.path, headers)
      req.body = enriched_report.to_json
      begin
        Inspec::Log.debug "Posting report to Chef Automate: #{uri.path}"
        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = uri.scheme == 'https'
        if @config['verify_ssl'] == true
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        else
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end

        http.request(req)
        return true
      rescue => e
        Inspec::Log.error "send_report: POST to #{uri.path} returned: #{e.message}"
        return false
      end
    end

    private

    # This hashes the passed string into SHA1.
    # Then it downgrades the 160bit SHA1 to a 128bit
    # then we format it as a valid UUIDv5.
    def uuid_from_string(string)
      hash = Digest::SHA1.new
      hash.update(string)
      ary = hash.digest.unpack('NnnnnN')
      ary[2] = (ary[2] & 0x0FFF) | (5 << 12)
      ary[3] = (ary[3] & 0x3FFF) | 0x8000
      # rubocop:disable Style/FormatString
      '%08x-%04x-%04x-%04x-%04x%08x' % ary
    end
  end
end
