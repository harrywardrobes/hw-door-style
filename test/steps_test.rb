$LOAD_PATH.unshift File.expand_path('../src', __dir__)
module UI
  @timers = {}; @n = 0
  def self.start_timer(_s, rep = false, &b) = (@n += 1; @timers[@n] = [rep, b]; @n)
  def self.stop_timer(id) = @timers.delete(id)
  def self.messagebox(m) = (puts "MSG #{m}")
  # one pass of SketchUp's event loop: every due timer once
  def self.pump
    @timers.dup.each { |id, (rep, b)| next unless @timers.key?(id); @timers.delete(id) unless rep; b.call }
  end
  def self.pending = @timers.size
end
module HarryWardrobes; module DoorStyle; module Log; def self.error(*a) = (puts "LOG #{a[0]} #{a[1].message}"); end; end; end
require 'json'
require 'hw_door_style/core/steps'
S = HarryWardrobes::DoorStyle::Steps
out = []
t0 = Time.now
S.run(nil, [['net', -> { sleep 0.3; 42 }, :bg, ->(r) { out << [:after, r, Thread.current == Thread.main]; r }],
            ['main', -> { out << [:main, Thread.current == Thread.main]; 7 }],
            ['net2', -> { raise 'boom' if false; sleep 0.1; 'x' }, :bg]],
      done: ->(r) { out << [:done, r] }, fail: ->(e) { out << [:fail, e.message] })
ticks = 0
until out.any? { |o| [:done, :fail].include?(o[0]) } || Time.now - t0 > 5
  UI.pump; ticks += 1; sleep 0.005
end
p out, ticks, (Time.now - t0).round(2)
out2 = []
S.run(nil, [['bad', -> { raise ArgumentError, 'no network' }, :bg]], done: ->(_r) { out2 << :done }, fail: ->(e) { out2 << e.message })
20.times { UI.pump; sleep 0.01 }
p out2, UI.pending
