def option_parser_init(descriptions, text, args=ARGV)
  options = {}
  optparse = OptionParser.new do |opts|
    opts.banner = text
    opts.separator "Options:"
    
    descriptions.each_entry do |key, desc|
      options[key] = desc[:default]
      opts.on("-#{desc[:short]}", "--#{desc[:full]}#{desc[:no_val] ? '' : '='+desc[:full].upcase}", desc[:text]) {|s| options[key] = s }
    end
    opts.on_tail("-?", "--help", "Show this message") do
      puts opts
      exit
    end
    opts.on_tail("-v", "--version", "Show version") do
      puts FC::VERSION
      exit
    end
  end
  optparse.parse!(args)
  options['optparse'] = optparse
  options
end

def size_to_human(size)
  return "0" if size == 0
  units = %w{B KB MB GB TB}
  minus = size < 0
  size = -1 * size if minus
  e = (Math.log(size)/Math.log(1024)).floor
  s = "%.2f" % (size.to_f / 1024**e)
  (minus ? '-' : '')+s.sub(/\.?0*$/, units[e])
end

def human_to_size(size)
  r = /^(\d+(\.\d+)?)\s*(.*)/
  units = {'k' => 1024, 'm' => 1024*1024, 'g' => 1024*1024*1024, 't' => 1024*1024*1024*1024}
  return nil unless matches = size.to_s.match(r)
  unit = units[matches[3].to_s.strip.downcase[0]]
  result = matches[1].to_f
  result *= unit if unit
  result.to_i
end

def stdin_read_val(name, can_empty = false)
  while val = Readline.readline("#{name}: ", false).strip.downcase
    if val.empty? && !can_empty
      puts "Input non empty #{name}."
    else 
      if block_given?
        if err = yield(val) 
          puts err
        else 
          return val
        end
      else 
        return val
      end
    end
  end
end

def colorize_string(str, color)
  return str unless color
  case color.to_s
  when 'red'
    color_code = 31
  when 'green'
    color_code = 32
  when 'yellow'
    color_code = 33
  when 'pink'
    color_code = 35
  else
    color_code = color.to_i
  end 
  "\e[#{color_code}m#{str}\e[0m"
end
