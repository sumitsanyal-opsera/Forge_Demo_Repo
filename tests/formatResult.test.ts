import { describe, it, expect } from 'vitest';
import { formatResult } from '../src/formatResult';

describe('formatResult', () => {
  it('formats a result with all fields including xsdRule', () => {
    const result = {
      line: 5,
      column: 3,
      message: 'Element is not allowed',
      phase: 'xsd' as const,
      xsdRule: 'cvc-complex-type.2.4.a',
    };
    expect(formatResult(result, 'path/to/file.xml')).toBe(
      'path/to/file.xml:5:3 [xsd] Element is not allowed (rule: cvc-complex-type.2.4.a)'
    );
  });

  it('omits rule suffix when xsdRule is null', () => {
    const result = {
      line: 2,
      column: 0,
      message: 'Unexpected end of document',
      phase: 'wellformedness' as const,
      xsdRule: null,
    };
    expect(formatResult(result, 'file.xml')).toBe(
      'file.xml:2:0 [wellformedness] Unexpected end of document'
    );
  });

  it('formats a Phase 1 well-formedness error correctly', () => {
    const result = {
      line: 3,
      column: 1,
      message: 'Opening tag has no closing tag',
      phase: 'wellformedness' as const,
      xsdRule: null,
    };
    const output = formatResult(result, 'malformed.xml');
    expect(output).toContain('[wellformedness]');
    expect(output).toContain('malformed.xml:3:1');
    expect(output).not.toContain('(rule:');
  });
});
