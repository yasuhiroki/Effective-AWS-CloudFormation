require 'yaml'
require 'active_support'

common = YAML.load_file(ARGV[0])
base = YAML.load_file(ARGV[1])

p common
p base

puts YAML.dump( common.deep_merge(base) )

