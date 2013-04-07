
def option_parser_init(descriptions, text)
  options = {}
  OptionParser.new do |opts|
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
  end.parse!
  options
end
