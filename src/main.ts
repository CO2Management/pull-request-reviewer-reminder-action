import * as core from '@actions/core'
import * as github from '@actions/github'

async function run(): Promise<void> {
  const octokit = github.getOctokit(core.getInput('github_token'))
  const reminderMessage = core.getInput('reminder_message')
  const reviewTurnaroundHours = core.getInput('review_turnaround_hours')

  // optional second reminder
  const secondReminderMessage = core.getInput('second_reminder_message', { required: false })
  const secondReviewTurnaroundHours = core.getInput('second_review_turnaround_hours', { required: false })

  try {
    const {data: pullRequests} = await octokit.pulls.list({
      ...github.context.repo,
      state: 'open'
    })

    for (const pr of pullRequests) {
      core.info(`pr ${pr.number}, title: ${pr.title}`)

      const pullRequestResponse = await octokit.graphql<PullRequestResponse>(
        `
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              timelineItems(first: 50, itemTypes: [REVIEW_REQUESTED_EVENT]) {
                nodes {
                  __typename
                  ... on ReviewRequestedEvent {
                    createdAt
                  }
                }
              },
              reviews(first: 50, states: [PENDING]) {
                nodes {
                  __typename
                  ... on PullRequestReview {
                    createdAt
                  }
                }
              },
              comments(first: 100) {
                nodes {
                  body
                }
              }
            }
          }
        }
        `,
        {
          owner: github.context.repo.owner,
          name: github.context.repo.repo,
          number: pr.number
        }
      )

      // Skip if there are no review requests
      if (
        pullRequestResponse.repository.pullRequest.timelineItems.nodes
          .length === 0
      ) {
        core.info('No review requests found, skipping')
        continue
      }

      // Skip if there are no reviews in the 'PENDING' state
      if (pullRequestResponse.repository.pullRequest.reviews.nodes.length === 0) {
        core.info('No reviews found in the PENDING state, skipping')
        continue
      }

      const pullRequestCreatedAt =
        pullRequestResponse.repository.pullRequest.timelineItems.nodes[0]
          .createdAt

      const currentTime = new Date().getTime()

      const reviewByTime =
        new Date(pullRequestCreatedAt).getTime() +
        1000 * 60 * 60 * parseInt(reviewTurnaroundHours, 10)

      const secondReviewByTime = secondReviewTurnaroundHours 
        ? new Date(pullRequestCreatedAt).getTime() + 1000 * 60 * 60 * parseInt(secondReviewTurnaroundHours, 10)
        : null

      core.info(`currentTime: ${new Date(currentTime)}`)
      core.info(`reviewByTime: ${new Date(reviewByTime)}`)
      if (secondReviewByTime) {
        core.info(`secondReviewByTime: ${new Date(secondReviewByTime)}`)
      }

      let reminderToSend = null

      if (secondReviewByTime !== null && currentTime >= secondReviewByTime) {
        reminderToSend = secondReminderMessage || ""
      } else if (currentTime >= reviewByTime) {
        reminderToSend = reminderMessage
      }

      if (!reminderToSend) {
        core.info('Not yet time to send a reminder, skipping')
        continue
      }

      const {data: pullRequest} = await octokit.pulls.get({
        ...github.context.repo,
        pull_number: pr.number
      })

      const reviewers = pullRequest.requested_reviewers
        .map(rr => `@${rr.login}`)
        .join(', ')

      const addReminderComment = `${reviewers} \n${reminderToSend}`
      const hasReminderComment =
        pullRequestResponse.repository.pullRequest.comments.nodes.filter(
          node => {
            return node.body.match(RegExp(reminderToSend)) != null
          }
        ).length > 0

      if (hasReminderComment) {
        core.info('Reminder comment already exists, skipping')
        continue
      }

      await octokit.issues.createComment({
        ...github.context.repo,
        issue_number: pullRequest.number,
        body: addReminderComment
      })

      core.info(
        `comment created: ${addReminderComment}`
      )
    }
  } catch (error) {
    core.setFailed(error.message)
  }
}

interface PullRequestResponse {
  repository: {
    pullRequest: {
      timelineItems: {
        nodes: Node[]
      }
      reviews: {
        nodes: Node[]
      }
      comments: {
        nodes: {
          body: string
        }[]
      }
    }
  }
}

interface Node {
  __typename: string
  createdAt: string
}

run()
