#!/usr/bin/env ruby

require 'optparse'
require 'json'

options = {}

OptionParser.new do |parser|
  parser.on("-a", "--address ADDRESS", "Payment address to query") do |address|
    options[:address] = address
  end
  parser.on("-d", "--destination-address ADDRESS", Array, "Address(es) to deliver") do |destination_addresses|
    options[:destination_addresses] = destination_addresses
  end
  parser.on("-r", "--return-address ADDRESS", "Return Address to deliver remaining ADA and assets") do |return_address|
    options[:return_address] = return_address
  end
  parser.on("-t", "--token TOKEN", Array, "Token(s) to deliver") do |tokens|
    options[:tokens] = tokens
  end
  parser.on("--metadata METADATA_FILE", "Metadata file") do |metadata|
    options[:metadata] = metadata
  end
  parser.on("--policy POLICY_FILE", "Policy file to parse") do |policy|
    options[:policy] = policy
  end
  parser.on("--policy-signing-key POLICY_SIGNING_KEY", "Signing key for policy") do |policy_skey|
    options[:policy_skey] = policy_skey
  end
  parser.on("--payment-signing-key PAYMENT_SIGNING_KEY", "Signing key for payment address") do |payment_skey|
    options[:payment_skey] = payment_skey
  end
  parser.on("-p", "--protocol-file PROTOCOL_FILE", "Protocol JSON file") do |file|
    options[:protocol_file] = file
  end
  parser.on("-n", "--network [NETWORK]", "Such as mainnet or testnet") do |network|
    options[:network] = network
  end
  parser.on("-m", "--magic [MAGICNUMBER]", "Defaults to 1097911063") do |magic|
    options[:magic] = magic
  end
  parser.on("-e", "--era [ERA]", "Era to query") do |era|
    options[:era] = era
  end
end.parse!

options[:return_address] ||= options[:address]
options[:network] ||= 'mainnet'
options[:magic] ||= '1097911063'
options[:era] ||= 'mary-era'

network = if options[:network] == 'testnet'
  "testnet-magic #{options[:magic]}"
else
  'mainnet'
end

before_slot = JSON.parse(File.read(options[:policy]))['scripts'].find {|hash| hash['type'] == 'before'}['slot']

utxos_table = `cardano-cli query utxo --address #{options[:address]} --#{network} --#{options[:era]}`

sum_address_command = File.expand_path('../balances/sum_address.rb', File.dirname(__FILE__))
totals = JSON.parse(`#{sum_address_command} -a #{options[:address]} -n #{options[:network]} -e #{options[:era]}`)
total_lovelace_out = 0
tmp_file = "transaction_#{Time.now.to_i}"

utxos = utxos_table.split(/\n/)[2..-1]
if utxos.empty?
  puts 'UTXOs empty'
  exit 1
end

txs_in = utxos.map do |utxo|
  matched = utxo.match(/^(\w+)\s+(\d+)/)
  if matched
    "--tx-in #{matched[1]}##{matched[2]}"
  end
end.compact

txs_out = options[:destination_addresses].map.with_index do |address, index|
  amount = 1500000
  total_lovelace_out += amount
  "--tx-out #{address} #{amount}+\"1 #{options[:tokens][index]}\""
end.compact

new_totals = totals
new_totals['lovelace'] -= total_lovelace_out
prior_tokens = new_totals.map do |token, amount|
  "+\"#{amount} #{token}\""
end
return_tx_out = "--tx-out #{options[:return_address]} #{new_totals['lovelace']}" + prior_tokens.join('')

build_raw_transaction_command = """
cardano-cli transaction build-raw \
  --invalid-hereafter #{before_slot} \
  --#{options[:era]} \
  --fee 0 \
  #{txs_in.join(' ')} \
  #{txs_out.join(' ')} \
  #{return_tx_out} \
  --mint=#{options[:tokens].join('+')} \
  --metadata-json-file #{options[:metadata]} \
  --out-file #{tmp_file}.raw
"""

`#{build_raw_transaction_command}`

calculate_min_fee_command = """
cardano-cli transaction calculate-min-fee \
  --tx-body-file #{tmp_file}.raw \
  --tx-in-count #{txs_in.count} \
  --tx-out-count #{txs_out.count + 1} \
  --witness-count 2 \
  --#{network} \
  --protocol-params-file #{options[:protocol_file]}
"""

fee = `#{calculate_min_fee_command}`.strip

build_raw_transaction_with_fees_command = """
cardano-cli transaction build-raw \
  --invalid-hereafter #{before_slot} \
  --#{options[:era]} \
  --fee #{fee} \
  #{txs_in.join(' ')} \
  #{txs_out.join(' ')} \
  #{return_tx_out} \
  --mint=#{options[:tokens].join('+')} \
  --metadata-json-file #{options[:metadata]} \
  --out-file #{tmp_file}.raw
"""

`#{build_raw_transaction_with_fees_command}`

sign_raw_transaction_command = """
cardano-cli transaction sign \
  --signing-key-file #{options[:payment_skey]} \
  --signing-key-file #{options[:policy_skey]} \
  --script-file #{options[:policy]} \
  --#{network} \
  --tx-body-file #{tmp_file}.raw \
  --out-file #{tmp_file}.signed
"""

`#{sign_raw_transaction_command}`

`cardano-cli transaction submit --tx-file #{tmp_file}.signed --#{network}`
