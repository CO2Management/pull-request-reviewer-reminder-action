# frozen_string_literal: true
require 'octokit'
require 'time'

GITHUB_TOKEN = ENV['GITHUB_TOKEN']
REMINDER_MESSAGE = ENV['REMINDER_MESSAGE']
REVIEW_TURNAROUND_HOURS = ENV['REVIEW_TURNAROUND_HOURS']
SECOND_REMINDER_MESSAGE = ENV['SECOND_REMINDER_MESSAGE']
SECOND_REVIEW_TURNAROUND_HOURS = ENV['SECOND_REVIEW_TURNAROUND_HOURS']

client = Octokit::Client.new(access_token: GITHUB_TOKEN, per_page: 100)
repo = ENV['GITHUB_REPOSITORY']

begin
  pull_requests = client.pull_requests(repo, state: 'open')

  pull_requests.each do |pr|
    puts "pr #{pr.number}, title: #{pr.title}"

    # Get timeline events and reviews
    timeline = client.get("/repos/#{repo}/issues/#{pr.number}/timeline", per_page: 100)
    review_requested_events = timeline.select { |e| e[:event] == 'review_requested' }
    reviews = client.pull_request_reviews(repo, pr.number)
    comments = client.issue_comments(repo, pr.number)

    # Skip if there are no pending reviews
    if review_requested_events.empty? || pr.requested_reviewers.empty?
      puts "No pending reviews for PR ##{pr.number}, skipping."
      next
    end

    created_at_value = review_requested_events.last[:created_at]
    pull_request_created_at = created_at_value.is_a?(Time) ? created_at_value : Time.parse(created_at_value)
    current_time = Time.now
    review_by_time = pull_request_created_at + (REVIEW_TURNAROUND_HOURS.to_i * 3600)
    second_review_by_time = SECOND_REVIEW_TURNAROUND_HOURS ? (pull_request_created_at + (SECOND_REVIEW_TURNAROUND_HOURS.to_i * 3600)) : nil

    puts "currentTime: #{current_time.to_s}"
    puts "reviewByTime: #{review_by_time.to_s}"
    puts "secondReviewByTime: #{second_review_by_time.to_s}" if second_review_by_time

    reminder_to_send = nil
    if second_review_by_time && current_time >= second_review_by_time
      reminder_to_send = SECOND_REMINDER_MESSAGE
    elsif current_time >= review_by_time
      reminder_to_send = REMINDER_MESSAGE
    end

    unless reminder_to_send
      puts "No reminders to send for PR ##{pr.number}, skipping."
      next
    end

    reviewers = pr.requested_reviewers.map { |rr| "@#{rr[:login]}" }.join(', ')
    add_reminder_comment = "#{reviewers} \n#{reminder_to_send}"
    has_reminder_comment = comments.any? { |c| c[:body].include?(reminder_to_send) }

    if has_reminder_comment
      puts "Reminder comment already exists for PR ##{pr.number}, skipping."
      next
    end

    client.add_comment(repo, pr.number, add_reminder_comment)
    puts "comment created: #{add_reminder_comment}"
  end
rescue StandardError => e
  puts "Failed: #{e.message}"
  exit(1)
end
