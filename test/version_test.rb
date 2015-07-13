require 'helper'

class VersionTest < FC::TestCase
  def test_version_exist
    assert FC::VERSION
  end
end
