# Exercise the real lane with a local DSL stub: never load Fastlane, read a key,
# contact Apple, or submit anything. Only the candidate boundary is under test.

module UI
  def self.user_error!(message)
    raise ArgumentError, message
  end
end

class SubmissionLaneHarness
  attr_reader :lanes, :deliveries
  def initialize
    @lanes = {}
    @deliveries = []
    instance_eval(File.read(File.expand_path('../ios/fastlane/Fastfile', __dir__)))
  end
  def default_platform(*) ; end
  def platform(*) ; yield ; end
  def before_all(*) ; end
  def desc(*) ; end
  def lane(name, &block) ; @lanes[name] = block ; end
  def deliver(options) ; @deliveries << options ; end
end

def assert(condition, message)
  raise message unless condition
end

lane = SubmissionLaneHarness.new
[{}, {version: '1.0'}, {build_number: '35'},
 {version: 'latest', build_number: '35'},
 {version: '1.0', build_number: 'latest'},
 {version: '1.0', build_number: '0'}].each do |options|
  rejected = false
  begin
    lane.lanes[:submit_for_review].call(options)
  rescue ArgumentError
    rejected = true
  end
  assert(rejected, "Invalid candidate was accepted: #{options}")
end
assert(lane.deliveries.empty?, 'Missing candidate caused an Apple delivery')
puts 'ok 1 - explicit candidate required before delivery'

lane.lanes[:submit_for_review].call(version: '1.0', build_number: '35')
assert(lane.deliveries.length == 1, 'Expected one delivery')
delivery = lane.deliveries.first
{app_version: '1.0', build_number: '35', automatic_release: false,
 reject_if_possible: false, skip_binary_upload: true}.each do |key, expected|
  assert(delivery[key] == expected, "Incorrect #{key}: #{delivery[key]}")
end
assert(!delivery.key?(:submission_information), 'Blanket compliance declarations are forbidden')
puts 'ok 2 - selected candidate preserves manual release and existing declarations'
