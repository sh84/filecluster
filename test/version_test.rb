require 'helper'

class VersionTest < Test::Unit::TestCase
  should "version exist" do
      assert FC::VERSION
  end
end
