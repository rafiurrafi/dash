require 'json'
require 'time'
require 'dashing'
require 'connection_pool'
require File.expand_path('../../lib/helper', __FILE__)

GITHUB_BACKEND_POOL = ConnectionPool.new(size: 3, timeout: 5) do
  conn = GithubBackend.new()
  conn
end

SCHEDULER.every '1h', :first_in => '1m' do |job|
  series = [[],[]]

  pulls_by_period = GITHUB_BACKEND_POOL.with do |conn|
    conn.pull_count_by_status(
                              :period=>'month', 
                              :orgas=>(ENV['ORGAS'].split(',') if ENV['ORGAS']), 
                              :repos=>(ENV['REPOS'].split(',') if ENV['REPOS']),
                              :since=>ENV['SINCE']
                              ).group_by_month(ENV['SINCE'].to_datetime)
  end

  pulls_by_period.each_with_index do |(period,pulls),i|
    timestamp = Time.strptime(period, '%Y-%m').to_i
    series[0] << {
      x: timestamp,
      y: pulls.count
    }
    # Add empty second series stack, and extrapolate last month for
    # better trend visualization
    series[1] << {
      x: timestamp,
      y: (i == pulls_by_period.count-1) ? GithubDashing::Helper.extrapolate_to_month(pulls.count)-pulls.count : 0
    }
  end
  
  current = series[0][-1][:y] rescue 0
  prev = series[0][-2][:y] rescue 0
  trend = GithubDashing::Helper.trend_percentage_by_month(prev, current)
  trend_class = GithubDashing::Helper.trend_class(trend)
  send_event(
             'pull_requests', 
             {
               series: series, # Prepare for showing open/closed stacked
               displayedValue: current,
               difference: trend,
               trend_class: trend_class,
               arrow: 'icon-arrow-' + trend_class
             }
             )
end
