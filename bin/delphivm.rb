#!/usr/bin/env ruby
begin
  $LOAD_PATH.unshift File.join(File.dirname($0), '..', 'lib')
  
  #require 'bundler/setup'

  require 'DelphiVM'

  if ARGV[0] == 'backtrace'
    ::BACKTRACE = true
    ARGV.shift
  end
  
  ARGV << 'vendor:import' << '-c' if defined? Ocra

  $0 = Pathname($0).basename('.rb').to_s

  $thor_runner = true
  Delphivm::Runner.start(ARGV)

rescue Interrupt => e
  puts "\nQuitting..."
  puts e.backtrace.join("\n") if defined? ::BACKTRACE
  exit 1
rescue Exception => e
  puts e.message
  puts e.backtrace.join("\n") if defined? ::BACKTRACE
  exit 1
end
