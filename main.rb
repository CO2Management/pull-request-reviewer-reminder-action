# frozen_string_literal: true
require 'octokit'
require 'time'

GITHUB_TOKEN = ENV['GITHUB_TOKEN']
REMINDER_MESSAGE = ENV['REMINDER_MESSAGE']
REVIEW_TURNAROUND_HOURS = ENV['REVIEW_TURNAROUND_HOURS']
SECOND_REMINDER_MESSAGE = ENV['SECOND_REMINDER_MESSAGE']
SECOND_REVIEW_TURNAROUND_HOURS = ENV['SECOND_REVIEW_TURNAROUND_HOURS']

client = Octokit::Client.new(access_token: GITHUB_TOKEN)
repo = ENV['GITHUB_REPOSITORY']

begin
  pull_requests = client.pull_requests(repo, state: 'open')

  pull_requests.each do |pr|
    puts "pr #{pr.number}, title: #{pr.title}"

    # Get reviews and comments
    reviews = client.pull_request_reviews(repo, pr.number)
    comments = client.issue_comments(repo, pr.number)

    # Skip if there are no requested reviewers
    if pr.requested_reviewers.empty?
      puts "No requested reviewers for PR ##{pr.number}, skipping."
      next
    end

    pull_request_created_at = Time.parse(pr.created_at)
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
    add_reminder_comment = "#{reviewers} \n#{reminder_to_send.to_s}"
    has_reminder_comment = comments.any? { |c| c[:body].to_s.include?(reminder_to_send.to_s) }

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
