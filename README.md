# Pull Request reviewer reminder action

## Summary
Action to send Github mentions when there are pull requests pending for review, after one or two specified time windows.

## Setup
Create a file with the following content under `.github/workflows/pull-request-reviewer-reminder.yml`.

```yml
name: 'Pull request reviewer reminder'
on:
  schedule:
    # Check reviews every weekday at 7:00
    - cron: '0 7 * * 1-5'
    
jobs:
  pull-request-reviewer-reminder: 
    runs-on: ubuntu-latest
    steps:
      - uses: CO2Management/pull-request-reviewer-reminder-action@main
        with:
          github_repository: 'CO2Management/co2m' # Required. Repository where the action is based.
          github_token: ${{ secrets.GITHUB_TOKEN }} # Required
          reminder_message: 'Three business days have passed since the review started. Give priority to reviews as much as possible.' # Required. Messages to send to reviewers on Github.
          review_turnaround_hours: 72 # Required. This is the deadline for reviews. If this time is exceeded, a reminder wil be send.
          # Optional inputs
          second_reminder_message: 'A week has passed since the review started. This is a gentle and last reminder to review the changes.' # Optional
          second_review_turnaround_hours: 168 # Optional
          
