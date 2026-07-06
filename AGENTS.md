# Repository Instructions

## GitHub Issue Workflow

- Do not commit GitHub Issue work directly to `main`.
- For each Issue, create a dedicated work branch from `main`.
- Open a pull request targeting `main` for the Issue work.
- Keep each pull request scoped to its Issue unless the user explicitly asks to combine work.
- Include the related Issue number in the pull request body, using `Closes #<number>` when the PR should close the Issue.

## Implementation Completion Rule

- When asked to implement code changes, continue through commit, push, and pull request creation before responding.
- Leave the pull request open when reporting back to the user.

## Review Follow-up Workflow

- After addressing review comments from Cursor, add a pull request comment containing `bugbot run`.
- This comment starts Cursor Bugbot for the updated pull request.
