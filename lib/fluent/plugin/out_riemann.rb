require 'riemann/client'

class Fluent::RiemannOutput < Fluent::BufferedOutput
  Fluent::Plugin.register_output('riemann', self)

  config_param :host, :string, :default => '127.0.0.1'
  config_param :port, :integer, :default => 5555
  config_param :timeout, :integer, :default => 5
  config_param :protocol, :string, :default => 'tcp'
  config_param :service, :string, :default => nil
  config_param :types, :string, :default => 'metric:float'
  config_param :fields, :string, :default => 'message:description,level:state,metric'

  def initialize
    super
  end

  def configure(c)
    super

    @_types = parse_map(@types) do |k, t|
      case t
      when "string" then "to_s"
      when "integer" then "to_i"
      when "float" then "to_f"
      else t
      end
    end

    @_fields = parse_map(@fields) { |k, f| (f || k).to_sym }
  end

  def start
    super
  end

  def shutdown
    super
  end

  def client
    @_client ||= Riemann::Client.new :host => @host, :port => @port, :timeout => @timeout
    @protocol == 'tcp' ? @_client.tcp : @_client.udp
  end

  def format(tag, time, record)
    [tag, time, record].to_msgpack
  end

  def write(chunk)
    chunk.msgpack_each do |tag, time, record|
      event = {
        :time => time,
        :service => @service,
        :tags => tag.split('.')
      }

      if @_fields.length
        @_fields.each { |k,v| event[v] = record[k] }
      else
        flat_hash = flatten(record)
        flat_hash.each { |k,v| event[k] = v }
      end
      
      @_types.each { |k,t| event[k] = event[k].send(t) }

      client << event
    end
  end

  private
  
  def flatten(hash, recursive_key = "")
     hash.each_with_object({}) do |(k, v), ret|
       key = recursive_key + k.to_s
       if v.is_a? Hash
         ret.merge! flatten(v, key + ".")
       else
         ret[key] = v
       end
     end
   end

  def parse_map(map, &block)
    Hash[map.split(',').map do |m|
      k, v = m.split(':').map(&:strip)
      if block_given?
        [k, yield(k, v)]
      else
        [k, v]
      end
    end]
  end
end
