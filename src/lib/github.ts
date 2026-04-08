import * as github from '@actions/github';
import * as exec from '@actions/exec';

/**
 * Fetches the head branch name for a pull request via the GitHub API.
 *
 * @param token - GitHub token for API authentication
 * @param owner - Repository owner (e.g., 'cbeaulieu-gt')
 * @param repo - Repository name (e.g., 'github-actions')
 * @param prNumber - Pull request number
 * @returns The head branch ref string (e.g., 'feature/my-fix')
 */
export async function fetchPrBranchName(
  token: string,
  owner: string,
  repo: string,
  prNumber: number
): Promise<string> {
  const octokit = github.getOctokit(token);
  const { data } = await octokit.rest.pulls.get({
    owner,
    repo,
    pull_number: prNumber,
  });
  return data.head.ref;
}

/**
 * Downloads failed run logs via `gh run view --log-failed` and truncates to maxBytes.
 *
 * Uses getExecOutput instead of piping through `head -c` to avoid SIGPIPE
 * false failures when the output exceeds the limit.
 *
 * @param token - GitHub token for gh CLI authentication
 * @param runId - Workflow run ID to fetch logs for
 * @param maxBytes - Maximum number of bytes to return (truncates from end)
 * @returns The (possibly truncated) log output string
 * @throws Error if gh run view fails with a non-empty stderr message
 */
export async function fetchRunLogsSafe(
  token: string,
  runId: string,
  maxBytes: number
): Promise<string> {
  const { exitCode, stdout, stderr } = await exec.getExecOutput(
    'gh',
    ['run', 'view', runId, '--log-failed'],
    {
      env: { ...process.env, GH_TOKEN: token },
      silent: true,
      ignoreReturnCode: true,
    }
  );

  if (exitCode !== 0 && stderr.trim()) {
    throw new Error(`Failed to download lint logs: ${stderr.trim()}`);
  }

  return stdout.slice(0, maxBytes);
}
