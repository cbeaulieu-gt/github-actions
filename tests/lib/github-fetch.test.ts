import * as exec from '@actions/exec';

jest.mock('@actions/exec');
const mockGetExecOutput = exec.getExecOutput as jest.MockedFunction<typeof exec.getExecOutput>;

import { fetchRunLogsSafe } from '../../src/lib/github';

describe('fetchRunLogsSafe', () => {
  beforeEach(() => {
    jest.resetAllMocks();
  });

  it('downloads logs and truncates to maxBytes', async () => {
    const longOutput = 'x'.repeat(20000);
    mockGetExecOutput.mockResolvedValue({
      exitCode: 0,
      stdout: longOutput,
      stderr: '',
    });

    const result = await fetchRunLogsSafe('ghs_token', '12345', 16000);

    expect(mockGetExecOutput).toHaveBeenCalledWith(
      'gh',
      ['run', 'view', '12345', '--log-failed'],
      expect.objectContaining({
        env: expect.objectContaining({ GH_TOKEN: 'ghs_token' }),
      })
    );
    expect(result.length).toBeLessThanOrEqual(16000);
    expect(result).toBe('x'.repeat(16000));
  });

  it('returns full output when under maxBytes', async () => {
    mockGetExecOutput.mockResolvedValue({
      exitCode: 0,
      stdout: 'short log',
      stderr: '',
    });

    const result = await fetchRunLogsSafe('ghs_token', '99', 16000);
    expect(result).toBe('short log');
  });

  it('throws with a clear error when gh run view fails', async () => {
    mockGetExecOutput.mockResolvedValue({
      exitCode: 1,
      stdout: '',
      stderr: 'run 99999 not found',
    });

    await expect(fetchRunLogsSafe('ghs_token', '99999', 16000)).rejects.toThrow(
      /Failed to download lint logs.*run 99999 not found/
    );
  });

  it('tolerates non-zero exit with empty stderr (SIGPIPE-like)', async () => {
    mockGetExecOutput.mockResolvedValue({
      exitCode: 141,
      stdout: 'partial output',
      stderr: '',
    });

    const result = await fetchRunLogsSafe('ghs_token', '12345', 16000);
    expect(result).toBe('partial output');
  });
});
