require 'bundler'
Bundler.require(:default, :development)
require 'rspec' # => required for RubyMine to be able to run specs

Dir[File.expand_path(File.dirname(__FILE__) + '/support/**/*.rb')].each { |f| require f }

RSpec.configure do |config|

  config.mock_with :rspec
  require 'rspec/process_mocks' # This line must be after 'config.mock_with :rspec'

  # gets rid of the bacetrace that we don't care about
  config.backtrace_clean_patterns = [/\.rvm\/gems\//]

end
