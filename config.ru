require "bundler/setup"

$: << File.join(__dir__, "lib")

require "gravatard"
require "gravatard/application"

run Gravatard::Application
