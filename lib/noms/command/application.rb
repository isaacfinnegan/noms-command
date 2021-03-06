#!ruby

require 'noms/command/version'

require 'mime-types'
require 'v8'

require 'noms/command'

class NOMS

end

class NOMS::Command

end

class NOMS::Command::Application < NOMS::Command::Base

    # Should user-agent actually be here?
    attr_accessor :window, :options,
        :type, :body, :useragent,
        :document

    def initialize(origin, argv, attrs={})
        @document = nil
        @origin = NOMS::Command::URInion.parse(origin)
        if @origin.scheme == 'file' and @origin.host.nil?
            @origin.host = 'localhost'
        end
        @argv = argv
        @options = { }
        @type = nil

        @log = attrs[:logger] || default_logger

        @window = NOMS::Command::Window.new($0, @origin, :logger => @log)

        @log.debug "Application #{argv[0]} has origin: #{origin}"
        @useragent = NOMS::Command::UserAgent.new(@origin, :logger => @log,
                                                  :specified_identities => (attrs[:specified_identities] || []),
                                                  :cache => (attrs.has_key?(:cache) ? attrs[:cache] : true),
                                                  :plaintext_identity => (attrs.has_key?(:plaintext_identity) ?
                                                      attrs[:plaintext_identity] : nil))
    end

    def fetch!
        # Get content and build object, set @type
        case @origin.scheme
        when 'file'
            @type = (MIME::Types.of(@origin.path).first || MIME::Types['text/plain'].first).content_type
            @body = File.open(@origin.path, 'r') { |fh| fh.read }
        when 'data'
            @type = @origin.mime_type
            raise NOMS::Command::Error.new("data URLs must contain application/json") unless @type == 'application/json'
            @body = @origin.data
        when /^http/
            response, landing_url = @useragent.get(@origin)
            new_url = landing_url
            @origin = new_url
            @useragent.origin = new_url
            @window.origin = new_url
            if response.success?
                # Unlike typical ReST data sources, this
                # should very rarely fail unless there is
                # a legitimate communication issue.
                @type = response.content_type || 'text/plain'
                @body = response.body
            else
                raise NOMS::Command::Error.new("Failed to request #{@origin}: #{response.statusText}")
            end
        else
            raise NOMS::Command::Error.new("noms command #{@argv[0].inspect} not found: not a URL or bookmark")
        end

        case @type
        when /^(application|text)\/(x-|)json/
            begin
                @body = JSON.parse(@body)
            rescue JSON::ParserError => e
                raise NOMS::Command::Error.new("JSON error in #{@origin}: #{e.message}")
            end
            if @body.respond_to? :has_key? and @body.has_key? '$doctype'
                @type = @body['$doctype']
                @document = NOMS::Command::Document.new @body
                @document.argv = @argv
                @document.exitcode = 0
            else
                @type = 'noms-raw'
            end
        end
    end

    def exitcode
        @document ? @document.exitcode : 0
    end

    def render!
        if @document and @document.script
            # Crashes when using @window as global object
            @v8 = V8::Context.new
            # Set up same-origin context and stuff--need
            # Ruby objects to do XHR and limit local I/O
            @window.document = @document
            @v8[:window] = @window
            @v8[:document] = @document
            @v8.eval 'var alert = function (s) { window.alert(s); };'
            @v8.eval 'var prompt = function (s, echo) { window.prompt(s, echo); };'
            @v8.eval 'var location = window.location;'
            @v8.eval 'var console = window.console;'
            NOMS::Command::XMLHttpRequest.origin = @origin
            NOMS::Command::XMLHttpRequest.useragent = @useragent
            @v8[:XMLHttpRequest] = NOMS::Command::XMLHttpRequest
            script_index = 0
            @document.script.each do |script|
                if script.respond_to? :has_key? and script.has_key? '$source'
                    # Parse relative URL and load
                    request_error = nil
                    begin
                        response, landing_url = @useragent.get(script['$source'])
                    rescue StandardError => e
                        @log.debug "Setting request_error (#{e.class}) to #{e.message})"
                        request_error = e
                    end
                    # Don't need landing_url
                    script_name = File.basename(@useragent.absolute_url(script['$source']).path)
                    script_ref = "#{script_index},#{script_name}"
                    if request_error.nil? and response.success?
                        case response.content_type
                        when /^(application|text)\/(x-|)javascript/
                            begin
                                @v8.eval response.body
                            rescue StandardError => e
                                @log.warn "Javascript[#{script_ref}] error: #{e.message}"
                                @log.debug { e.backtrace.join("\n") }
                            end
                        else
                            @log.warn "Unsupported script type '#{response.content_type.inspect}' " +
                                "for script from #{script['$source'].inspect}"
                        end
                    else
                        if request_error
                            @log.warn "Couldn't load script from #{script['$source'].inspect} " +
                                "(#{request_error.class}): #{request_error.message})"
                            @log.debug { request_error.backtrace.join("\n") }
                        else
                            @log.warn "Couldn't load script from #{script['$source'].inspect}: " +
                                "#{response.statusText}"
                        end
                    end
                else
                    # It's javascript text
                    script_ref = "#{script_index},\"#{abbrev(script)}\""
                    begin
                        @v8.eval script
                    rescue StandardError => e
                        @log.warn "Javascript[#{script_ref}] error: #{e.message}"
                        @log.debug { e.backtrace.join("\n") }
                    end
                end
                script_index += 1
            end
        end
    end

    def abbrev(s, limit=10)
        if s.length > (limit - 3)
            s[0 .. (limit - 3)] + '...'
        else
            s
        end
    end

    def display
        case @type
        when 'noms-v2'
            body = _sanitize(@document.body)
            NOMS::Command::Formatter.new(body, :logger => @log).render
        when 'noms-raw'
            @body.to_yaml
        when /^text(\/|$)/
            @body
        else
            if @window.isatty
                # Should this be here?
                @log.warn "Unknown data of type '#{@type}' not sent to terminal"
                []
            else
                @body
            end
        end
    end

    # Get rid of V8 stuff
    def _sanitize(thing)
        if thing.kind_of? V8::Array or thing.respond_to? :to_ary
            thing.map do |item|
                _sanitize item
            end
        elsif thing.respond_to? :keys
            Hash[
                 thing.keys.map do |key|
                     [key, _sanitize(thing[key])]
                 end]
        else
            thing
        end
    end

end
