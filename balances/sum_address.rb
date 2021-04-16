#!/usr/bin/env ruby

require 'optparse'
require 'json'

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

utxos = `cardano-cli query utxo --address #{options[:address]} --#{network}`

totals = {}

lovelace = utxos.split(/\n/)[2..-1].sum do |utxo|
  matched = utxo.match(/\s(\d+)\slovelace/)
  if matched
    matched[1].to_i
  else
    0
  end
end

totals['lovelace'] = lovelace

tokens_regex = /\+\s(\d+)\s(\w+\.*\w+)/

utxos.split(/\n/)[2..-1].each do |utxo|
  matched = utxo.match(tokens_regex)
  if matched
    length = matched.length
    i = 1
    arr = []
    while i < length
      arr << matched[i]
      i += 1
    end
    arr.each_cons(2) do |pair|
      totals[pair[1]] = totals[pair[1]].to_i + pair[0].to_i
    end
  end
end

puts totals.to_json

