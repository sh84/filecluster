require 'open3'
require 'shellwords'

class Iostat
  attr_reader :w_await, :r_await, :util, :disk_name
  def initialize(path)
    @path = path
    @w_await = 0
    @r_await = 0
    @util = 0
    @disk_name = 'unknown'
    run
  end

  def run
    @run = true
    Thread.new do
      disk_await_monitor
    end
  end

  def stop
    @run = false
  end

  private

  def disk_await_monitor
    drive = `df #{@path.shellescape}`.split("\n")[1].split(' ')[0].split('/').last
    Open3.popen3('iostat -x 1 -p') do |_, stderr, _, thread|
      while line = stderr.gets
        update_stats(line) if line.split(' ')[0] == drive
        unless @run
          Process.kill('KILL', thread.pid) rescue nil
          break
        end
      end
    end
  end

  def update_stats(line)
    parts = line.gsub(/\s+/, ' ').split(' ')
    @disk_name = parts.first
    @util = parts.last.to_f
    @w_await = parts[parts.size - 2].to_f
    @r_await = parts[parts.size - 3].to_f
  end
end
