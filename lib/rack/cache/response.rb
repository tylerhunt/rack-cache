require 'set'

module Rack::Cache

  module ResponseHelpers

    # A Hash of name=value pairs that correspond to the Cache-Control
    # header. Valueless parameters (e.g., must-revalidate, no-store)
    # have a Hash value of true.
    def cache_control
      @cache_control ||= 
        (headers['Cache-Control'] || '').split(/\s*,\s*/).inject({}) do |hash,token|
          name, value = token.split(/\s*=\s*/, 2)
          hash[name.downcase] = (value || true) unless name.empty?
          hash
        end
    end

    # The number of seconds from #date that the object should be fresh for. This
    # method uses the max-age Cache-Control directive if present and falls back
    # to the Expires header. If no freshness information is available, zero is
    # returned.
    def max_age
      @max_age ||=
        if value = cache_control['max-age']
          value.to_i
        else
          expires_at - date
        end
    end

    # Sets the maximum age of the response to the specified value.
    def max_age=(value)
      @max_age = value
    end

    # HTTP allows caches to take liberties with the freshness of objects; by
    # specifying this header, you're telling the cache that you want
    # it to strictly follow the freshness information provided with the
    # response.
    def must_revalidate?
      cache_control['must-revalidate']
    end

    # Indicates that the response should not be cached.
    def no_cache?
      cache_control['no-cache']
    end

    # Indicates that the response should not be stored.
    def no_store?
      cache_control['no-store']
    end

    # The expiration date of the response as specified by the Expires header;
    # or, when no Expires header is present, the date of the response.
    def expires_at
      @expires_at ||=
        if time = headers['Expires']
          Time.httpdate(time)
        else
          date
        end
    end

    CACHEABLE_RESPONSE_CODES = Set.new([200, 203, 300, 301, 302, 404, 410])

    def cacheable?
      CACHEABLE_RESPONSE_CODES.include?(status) &&
      !(no_store? || no_cache?)
    end

  end


  module Cacheable

    # The time at which this response is being processed.
    attr_reader :now

    # The date the response was generated by the origin server.
    attr_reader :date

    # The amount of time that's elapsed between the response's date and when
    # the response started to be processed.
    attr_reader :age

    # The response's time-to-live, in seconds.
    def ttl
      max_age - age
    end

    def ttl=(value)
      @max_age = age + value
    end

    # Does the response's
    def fresh?
      ttl > 0
    end

    # Does the response's max_age meet or exceed its age?
    def stale?
      ttl <= 0
    end

    # Is the response from the origin server or has it been loaded from cache?
    def original?
      age == 0
    end

    def persist
      status, header, this = finish
      [ status, header, body ]
    end

    def recalculate_freshness!
      now = Time.now
      @date = 
        if date = headers['Date']
          Time.httpdate(date)
        else
          headers['Date'] = now.httpdate
          now
        end
      if headers['Age'] && !@original_response
        @original_response = false
        @now = now
        @age = now - @date
      else
        @original_response = true
        @now = @date
        @age = 0
      end
      headers['Age'] = @age.to_i.to_s
    end

  private

    def initialize_cacheable
      recalculate_freshness!
    end

    def self.extended(object)
      object.__send__(:initialize_cacheable)
      super
    end

  end

  class Response < Rack::Response
    include ResponseHelpers

    def self.activate(object)
      status, header, body = object
      response = new(body, status, header)
      response.extend Cacheable
      response
    end
  end

  class MockResponse < Rack::MockResponse
    include ResponseHelpers
    include Cacheable

    def initialize(*args, &b)
      super
      initialize_cacheable
    end
  end

end
