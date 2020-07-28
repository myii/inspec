# copyright: 2015, Vulcano Security GmbH

require "inspec/resources/command"
require "shellwords"

module Inspec::Resources
  class Lines
    attr_reader :output

    def initialize(raw, desc)
      @output = raw
      @desc = desc
    end

    def lines
      output.split("\n")
    end

    def to_s
      @desc
    end
  end

  class MysqlSession < Inspec.resource(1)
    name "mysql_session"
    supports platform: "unix"
    supports platform: "windows"
    desc "Use the mysql_session InSpec audit resource to test SQL commands run against a MySQL database."
    example <<~EXAMPLE
      sql = mysql_session('my_user','password','host')
      describe sql.query('show databases like \'test\';') do
        its('stdout') { should_not match(/test/) }
      end
    EXAMPLE

    def initialize(user = nil, pass = nil, host = "localhost", port = nil, socket = nil)
      @user = user
      @pass = pass
      @host = host
      @port = port
      @socket = socket
      init_fallback if user.nil? || pass.nil?
      skip_resource("Can't run MySQL SQL checks without authentication") if @user.nil? || @pass.nil?
    end

    def query(q, db = "")
      mysql_cmd = create_mysql_cmd(q, db)
      cmd = if !@pass.nil?
              inspec.command(mysql_cmd, redact_regex: /(mysql -u\w+ -p).+(\s-(h|S).*)/)
            else
              inspec.command(mysql_cmd)
            end
      out = cmd.stdout + "\n" + cmd.stderr
      if cmd.exit_status != 0 || out =~ /Can't connect to .* MySQL server/ || out.downcase =~ /^error:.*/
        Lines.new(out, "MySQL query with errors: #{q}")
      else
        Lines.new(cmd.stdout.strip, "MySQL query: #{q}")
      end
    end

    def to_s
      "MySQL Session"
    end

    private

    def escape_string(query)
      Shellwords.escape(query)
    end

    def create_mysql_cmd(q, db = "")
      # TODO: simple escape, must be handled by a library
      # that does this securely
      escaped_query = q.gsub(/\\/, '\\\\').gsub(/"/, '\\"').gsub(/\$/, '\\$')

      # construct the query
      command = "mysql"
      command += " -u#{escape_string(@user)}" unless @user.nil?
      command += " -p#{escape_string(@pass)}" unless @pass.nil?

      if !@socket.nil?
        command += " -S #{@socket}"
      else
        command += " -h #{@host}"
      end
      command += " --port #{@port}" unless @port.nil?
      command += " #{db}" unless db.empty?
      command += %{ -s -e "#{escaped_query}"}
      command
    end

    def init_fallback
      # support debian mysql administration login
      return if inspec.platform.in_family?("windows")

      debian = inspec.command("test -f /etc/mysql/debian.cnf && cat /etc/mysql/debian.cnf").stdout
      return if debian.empty?

      user = debian.match(/^\s*user\s*=\s*([^ ]*)\s*$/)
      pass = debian.match(/^\s*password\s*=\s*([^ ]*)\s*$/)
      return if user.nil? || pass.nil?

      @user = user[1]
      @pass = pass[1]
    end
  end
end
