#!/usr/bin/env ruby

require 'optparse'

options = {}

OptionParser.new do |parser|
  parser.on("-a", "--address ADDRESS", "Payment address to query") do |address|
    options[:address] = address
  end
  parser.on("-n", "--network [NETWORK]", "Such as mainnet or testnet") do |network|
    options[:network] = network || 'mainnet'
  end
  parser.on("-m", "--magic [MAGICNUMBER]", "Defaults to 1097911063") do |magic|
    options[:magic] = magic || '1097911063'
  end
  parser.on("-e", "--era [ERA]", "Era to query") do |era|
    options[:era] = era || 'mary-era'
  end
end.parse!

options[:network] ||= 'mainnet'
options[:magic] ||= 1097911063
options[:era] ||= 'mary-era'

network = if options[:network] == 'testnet'
  "testnet-magic #{options[:magic]}"
else
  'mainnet'
end

puts `cardano-cli query utxo --address #{options[:address]} --#{network}}`
