require "influxdb"
require 'date'

class MrInfluxDB
  attr_reader :client, :precision

  def initialize(host, port, username, password, database)
    @client = InfluxDB::Client.new(
      database,
      host: host,
      port: port,
      username: username,
      password: password,
      time_precision: "ns",
      retry: false,
    )
  end

  def check_connection
    client.list_databases
  end


  def copy(another, ms, from, to, col_types)
    tags = {}
    client.query("show tag keys from foobar")[0]["values"].each { |v| tags[v["tagKey"]] = true }

    count = 0
    read_batch(ms, from, to) do |points|
      insert_points = points.map do |point|
        count += 1
        create_point_to_insert(ms, tags, point, col_types)
      end

      puts insert_points
      another.client.write_points(insert_points)
    end

    count
  end

  private

  def read_batch(ms, from, to)
    limit = 1000
    times = 0
    loop do
      offset = times * limit
      times += 1
      d = client.query(
        "select * from #{ms} where %{from} <= time and time <= %{to} limit %{limit} offset %{offset}",
        params: {from: from, to: to, limit: limit, offset: offset},
      )
      points = d[0] ? d[0]["values"] : []
      yield(points) if block_given?
      break if points.length == 0
    end
  end

  def create_value(value, type)
    case type
    when "integer"
      value.to_i
    when "float"
      value.to_f
    else
      value
    end
  end

  def create_point_to_insert(ms, tags, point, col_types)
    data = {
      series: ms,
      tags: {},
      values: {},
    }

    point.each do |key, value|
      if key == "time"
        data[:timestamp] = time_to_epoch(DateTime.parse(point["time"]).to_time)
      elsif tags[key]
        data[:tags][key] = create_value(value, col_types[key])
      else
        data[:values][key] = create_value(value, col_types[key])
      end
    end

    data
  end

  def time_to_epoch(t)
    "#{t.to_i}#{t.nsec}"
  end
end

def main
  i1 = MrInfluxDB.new("localhost", 8086, "influxdb_from", "password", "test")
  i1.check_connection

  i2 = MrInfluxDB.new("localhost", 8087, "influxdb_to", "password", "tests")
  i2.check_connection

  # data = []
  # value = (0..360).to_a.map {|i| Math.send(:sin, i / 10.0) * 10 }.each
  # 100.times do
  #   t = Time.now
  #   data << {
  #     series: 'foobar',
  #     timestamp: "#{t.to_i}#{t.nsec}",
  #     tags:   { host: ['server_1', 'server_2'].sample, region: 'us' },
  #     values: { internal: 5, external: 0.453345, value: value.next, },
  #   }
  #   sleep 0.01
  # end
  # i1.client.write_points(data)

  puts i1.copy(i2 ,"foobar", "2022-01-21T00:00:00Z", "2022-01-23T00:00:00Z", {
    "internal" => "float",
    "value" => "float",
  })
end

main()

