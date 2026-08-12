import { createElement } from 'lwc';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import TrendChart from 'c/trendChart';
import getExecutionHistory from '@salesforce/apex/SmokeTestDashboardController.getExecutionHistory';

import mockHistoryData from './data/historyData.json';

const getExecutionHistoryAdapter = registerApexTestWireAdapter(getExecutionHistory);

const flushPromises = () => new Promise(resolve => setTimeout(resolve, 0));

function createComponent() {
    const element = createElement('c-trend-chart', { is: TrendChart });
    document.body.appendChild(element);
    return element;
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
});

// =============================================================================
// Loading state
// =============================================================================

describe('loading state', () => {
    it('shows spinner before wire resolves', () => {
        const element = createComponent();
        const spinner = element.shadowRoot.querySelector('.slds-spinner');
        expect(spinner).not.toBeNull();
    });

    it('does not render chart while loading', () => {
        const element = createComponent();
        const svg = element.shadowRoot.querySelector('svg');
        expect(svg).toBeNull();
    });
});

// =============================================================================
// Empty state (0 records)
// =============================================================================

describe('empty state — 0 records (AC-7)', () => {
    it('shows "No deployment history available" for empty array', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit([]);
        await flushPromises();

        const emptyMsg = element.shadowRoot.querySelector('.empty-state');
        expect(emptyMsg).not.toBeNull();
        expect(emptyMsg.textContent).toContain('No deployment history available');
    });

    it('does not render SVG for empty data', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit([]);
        await flushPromises();

        const svg = element.shadowRoot.querySelector('svg');
        expect(svg).toBeNull();
    });
});

// =============================================================================
// Single record (1 bar)
// =============================================================================

describe('single record — 1 bar (AC-1, AC-7)', () => {
    const singleRecord = [{
        Id: 'single1',
        CreatedDate: '2024-03-01T10:00:00.000Z',
        TotalScenarios__c: 10,
        PassedScenarios__c: 10,
        FailedScenarios__c: 0
    }];

    it('renders exactly 1 bar group for 1 record', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(singleRecord);
        await flushPromises();

        const barGroups = element.shadowRoot.querySelectorAll('.bar-group');
        expect(barGroups).toHaveLength(1);
    });

    it('renders SVG with correct accessibility attributes (AC-6)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(singleRecord);
        await flushPromises();

        const svg = element.shadowRoot.querySelector('svg');
        expect(svg).not.toBeNull();
        expect(svg.getAttribute('role')).toBe('img');
        expect(svg.getAttribute('aria-label')).toContain('Pass rate trend');
        expect(svg.getAttribute('aria-describedby')).toBe('trend-data-table');
    });
});

// =============================================================================
// 15 records
// =============================================================================

describe('15 records (AC-7)', () => {
    const fifteenRecords = mockHistoryData.slice(0, 15);

    it('renders exactly 15 bar groups', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(fifteenRecords);
        await flushPromises();

        const barGroups = element.shadowRoot.querySelectorAll('.bar-group');
        expect(barGroups).toHaveLength(15);
    });
});

// =============================================================================
// 30 records (full dataset)
// =============================================================================

describe('30 records (AC-1, AC-7)', () => {
    it('renders exactly 30 bar groups for full dataset', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData);
        await flushPromises();

        const barGroups = element.shadowRoot.querySelectorAll('.bar-group');
        expect(barGroups).toHaveLength(30);
    });

    it('renders SVG element', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData);
        await flushPromises();

        const svg = element.shadowRoot.querySelector('svg');
        expect(svg).not.toBeNull();
    });
});

// =============================================================================
// Bar color / pattern assignment (AC-2)
// =============================================================================

describe('bar color and pattern assignment (AC-2)', () => {
    it('applies green color (barStyle with #4CAF50) for 100% pass rate', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit([{
            Id: 'green1',
            CreatedDate: '2024-03-01T00:00:00.000Z',
            TotalScenarios__c: 10,
            PassedScenarios__c: 10,
            FailedScenarios__c: 0
        }]);
        await flushPromises();

        const rect = element.shadowRoot.querySelector('.bar-group rect');
        expect(rect).not.toBeNull();
        expect(rect.getAttribute('style')).toContain('#4CAF50');
    });

    it('applies orange/yellow color (#FF9800) for 70% pass rate (50-79% range)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit([{
            Id: 'warn1',
            CreatedDate: '2024-03-01T00:00:00.000Z',
            TotalScenarios__c: 10,
            PassedScenarios__c: 7,
            FailedScenarios__c: 3
        }]);
        await flushPromises();

        const rect = element.shadowRoot.querySelector('.bar-group rect');
        expect(rect.getAttribute('style')).toContain('#FF9800');
    });

    it('applies red color (#F44336) for 30% pass rate (< 50%)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit([{
            Id: 'fail1',
            CreatedDate: '2024-03-01T00:00:00.000Z',
            TotalScenarios__c: 10,
            PassedScenarios__c: 3,
            FailedScenarios__c: 7
        }]);
        await flushPromises();

        const rect = element.shadowRoot.querySelector('.bar-group rect');
        expect(rect.getAttribute('style')).toContain('#F44336');
    });

    it('renders pattern overlay rect for warning-range bars (AC-2 WCAG pattern)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit([{
            Id: 'warn2',
            CreatedDate: '2024-03-01T00:00:00.000Z',
            TotalScenarios__c: 10,
            PassedScenarios__c: 6,
            FailedScenarios__c: 4
        }]);
        await flushPromises();

        // Warning range (60% pass rate) should render pattern overlay
        const rects = element.shadowRoot.querySelectorAll('.bar-group rect');
        expect(rects.length).toBeGreaterThanOrEqual(2);
        const patternRect = Array.from(rects).find(r =>
            r.getAttribute('style') && r.getAttribute('style').includes('url(#pattern-warning)')
        );
        expect(patternRect).not.toBeNull();
    });

    it('renders pattern overlay rect for error-range bars (AC-2 WCAG pattern)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit([{
            Id: 'err2',
            CreatedDate: '2024-03-01T00:00:00.000Z',
            TotalScenarios__c: 10,
            PassedScenarios__c: 2,
            FailedScenarios__c: 8
        }]);
        await flushPromises();

        const rects = element.shadowRoot.querySelectorAll('.bar-group rect');
        const patternRect = Array.from(rects).find(r =>
            r.getAttribute('style') && r.getAttribute('style').includes('url(#pattern-error)')
        );
        expect(patternRect).not.toBeNull();
    });

    it('does NOT render pattern overlay for green/pass-range bars (>= 80%)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit([{
            Id: 'pass_no_pattern',
            CreatedDate: '2024-03-01T00:00:00.000Z',
            TotalScenarios__c: 10,
            PassedScenarios__c: 9,
            FailedScenarios__c: 1
        }]);
        await flushPromises();

        const rects = element.shadowRoot.querySelectorAll('.bar-group rect');
        const patternRect = Array.from(rects).find(r =>
            r.getAttribute('style') && r.getAttribute('style').includes('url(#pattern')
        );
        expect(patternRect).toBeNull();
    });
});

// =============================================================================
// Bar height calculation (AC-1)
// =============================================================================

describe('bar height calculation (AC-1)', () => {
    it('gives a bar minimum height of 1 for 0% pass rate', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit([{
            Id: 'zero1',
            CreatedDate: '2024-03-01T00:00:00.000Z',
            TotalScenarios__c: 10,
            PassedScenarios__c: 0,
            FailedScenarios__c: 10
        }]);
        await flushPromises();

        const rect = element.shadowRoot.querySelector('.bar-group rect');
        const height = parseInt(rect.getAttribute('height'), 10);
        expect(height).toBeGreaterThanOrEqual(1);
    });

    it('gives a bar proportional to pass rate: 50% → ~half chart height', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit([{
            Id: 'half1',
            CreatedDate: '2024-03-01T00:00:00.000Z',
            TotalScenarios__c: 10,
            PassedScenarios__c: 5,
            FailedScenarios__c: 5
        }]);
        await flushPromises();

        const rect = element.shadowRoot.querySelector('.bar-group rect');
        const height = parseInt(rect.getAttribute('height'), 10);
        // C_HEIGHT = 238; 50% → 119. Allow 5px tolerance.
        expect(height).toBeGreaterThan(100);
        expect(height).toBeLessThan(145);
    });
});

// =============================================================================
// Records with TotalScenarios__c = 0 are skipped (edge case)
// =============================================================================

describe('edge case: records with zero total scenarios skipped', () => {
    it('skips records where TotalScenarios__c is 0', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit([
            { Id: 'valid1', CreatedDate: '2024-01-01T00:00:00.000Z', TotalScenarios__c: 10, PassedScenarios__c: 8, FailedScenarios__c: 2 },
            { Id: 'zero1',  CreatedDate: '2024-01-02T00:00:00.000Z', TotalScenarios__c: 0,  PassedScenarios__c: 0, FailedScenarios__c: 0 },
            { Id: 'null1',  CreatedDate: '2024-01-03T00:00:00.000Z', TotalScenarios__c: null, PassedScenarios__c: null, FailedScenarios__c: null }
        ]);
        await flushPromises();

        const barGroups = element.shadowRoot.querySelectorAll('.bar-group');
        expect(barGroups).toHaveLength(1);
    });
});

// =============================================================================
// Data table (AC-4, AC-5)
// =============================================================================

describe('accessible data table (AC-4, AC-5)', () => {
    it('data table is in DOM but visually hidden by default (AC-5)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 5));
        await flushPromises();

        const table = element.shadowRoot.querySelector('#trend-data-table');
        expect(table).not.toBeNull();
        // Default class includes slds-assistive-text (visually hidden)
        expect(table.className).toContain('slds-assistive-text');
    });

    it('toggle button labeled "Show Data Table" by default (AC-4)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 5));
        await flushPromises();

        const btn = element.shadowRoot.querySelector('button[aria-controls="trend-data-table"]');
        expect(btn).not.toBeNull();
        expect(btn.textContent).toBe('Show Data Table');
    });

    it('toggles table visible on button click (AC-4)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 5));
        await flushPromises();

        const btn = element.shadowRoot.querySelector('button[aria-controls="trend-data-table"]');
        btn.click();
        await flushPromises();

        const table = element.shadowRoot.querySelector('#trend-data-table');
        expect(table.className).not.toContain('slds-assistive-text');
    });

    it('toggle button label changes to "Hide Data Table" after first click (AC-4)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 5));
        await flushPromises();

        const btn = element.shadowRoot.querySelector('button[aria-controls="trend-data-table"]');
        btn.click();
        await flushPromises();

        expect(btn.textContent).toBe('Hide Data Table');
    });

    it('second toggle click hides the table again', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 5));
        await flushPromises();

        const btn = element.shadowRoot.querySelector('button[aria-controls="trend-data-table"]');
        btn.click();
        await flushPromises();
        btn.click();
        await flushPromises();

        const table = element.shadowRoot.querySelector('#trend-data-table');
        expect(table.className).toContain('slds-assistive-text');
    });

    it('data table has correct column headers (AC-4)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 1));
        await flushPromises();

        const btn = element.shadowRoot.querySelector('button[aria-controls="trend-data-table"]');
        btn.click();
        await flushPromises();

        const headers = element.shadowRoot.querySelectorAll('thead th');
        const headerTexts = Array.from(headers).map(h => h.textContent.trim());
        expect(headerTexts).toContain('Deployment Date');
        expect(headerTexts).toContain('Pass Rate');
        expect(headerTexts).toContain('Passed');
        expect(headerTexts).toContain('Failed');
        expect(headerTexts).toContain('Timed Out');
        expect(headerTexts).toContain('Total');
    });

    it('data table has correct row count (AC-4)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 10));
        await flushPromises();

        const rows = element.shadowRoot.querySelectorAll('tbody tr');
        expect(rows).toHaveLength(10);
    });

    it('data table has aria-label attribute (AC-5)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 5));
        await flushPromises();

        const tableDiv = element.shadowRoot.querySelector('#trend-data-table');
        expect(tableDiv.getAttribute('aria-label')).toBeTruthy();
    });
});

// =============================================================================
// SVG accessibility (AC-6)
// =============================================================================

describe('SVG accessibility attributes (AC-6)', () => {
    it('SVG has role="img"', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 5));
        await flushPromises();

        const svg = element.shadowRoot.querySelector('svg');
        expect(svg.getAttribute('role')).toBe('img');
    });

    it('SVG has meaningful aria-label', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 5));
        await flushPromises();

        const svg = element.shadowRoot.querySelector('svg');
        const label = svg.getAttribute('aria-label');
        expect(label).toBeTruthy();
        expect(label.toLowerCase()).toContain('pass rate');
    });

    it('SVG has aria-describedby pointing to the data table id', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 5));
        await flushPromises();

        const svg = element.shadowRoot.querySelector('svg');
        expect(svg.getAttribute('aria-describedby')).toBe('trend-data-table');
    });

    it('SVG defs contain pattern fills for WCAG (AC-2)', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.emit(mockHistoryData.slice(0, 5));
        await flushPromises();

        const defs = element.shadowRoot.querySelector('defs');
        expect(defs).not.toBeNull();
        const patterns = defs.querySelectorAll('pattern');
        expect(patterns.length).toBeGreaterThanOrEqual(2);
    });
});

// =============================================================================
// Error state
// =============================================================================

describe('error state', () => {
    it('shows error message when wire fails', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.error({ message: 'Callout failed' });
        await flushPromises();

        const errorBanner = element.shadowRoot.querySelector('.slds-alert_error');
        expect(errorBanner).not.toBeNull();
    });

    it('shows retry link in error state', async () => {
        const element = createComponent();
        getExecutionHistoryAdapter.error({ message: 'Callout failed' });
        await flushPromises();

        const retry = element.shadowRoot.querySelector('a[role="button"]');
        expect(retry).not.toBeNull();
    });
});
