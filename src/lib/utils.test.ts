import { describe, expect, it } from 'vitest';
import { versionCompare } from './utils';
describe('MSIX version comparisons', () => {
  it('compares numeric segments rather than display strings', () => {
    expect(versionCompare('1.10.0.0', '1.9.65535.0')).toBe(1);
    expect(versionCompare('26.1016.6573.0', '26.1016.8622.0')).toBe(-1);
    expect(versionCompare('26.1016.8622.0', '26.1016.8622.0')).toBe(0);
  });
  it.each(['26.1016.51333', '1.2.3.4/script', '1.2.3.-4', '1.2.3.65536', '1.2.3.Infinity'])(
    'rejects a non-package version %s',
    (input) => {
      expect(() => versionCompare(input, '1.2.3.4')).toThrow();
    },
  );
});
