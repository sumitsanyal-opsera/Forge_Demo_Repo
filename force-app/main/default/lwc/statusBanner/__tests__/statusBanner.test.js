import { createElement } from 'lwc';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import StatusBanner from 'c/statusBanner';
import getLatestExecution from '@salesforce/apex/SmokeTestDashboardController.getLatestExecution';

import mockPassExecution       from './data/passExecution.json';
import mockFailExecution       from './data/failExecution.json';
import mockInProgressExecution from './data/inProgressExecution.json';

const getLatestExecutionAdapter = registerApexTestWireAdapter(getLatestExecution);

const flushPromises = () => new Promise(resolve => setTimeout(resolve, 0));

function createComponent() {
    const element = createElement('c-status-banner', { is: StatusBanner });
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
// No-data state (AC-4)
// =============================================================================

describe('no-data state', () => {
    it('renders nothing before wire resolves', () => {
        const element = createComponent();
        const banner = element.shadowRoot.querySelector('.slds-notify_alert');
        expect(banner).toBeNull();
    });

    it('renders nothing when wire emits null', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(null);
        await flushPromises();

        const banner = element.shadowRoot.querySelector('.slds-notify_alert');
        expect(banner).toBeNull();
    });
});

// =============================================================================
// Pass state (AC-1, AC-2, AC-3)
// =============================================================================

describe('pass state', () => {
    it('renders the status banner when data is available', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockPassExecution);
        await flushPromises();

        const banner = element.shadowRoot.querySelector('.slds-notify_alert');
        expect(banner).not.toBeNull();
    });

    it('applies success SLDS class for pass status (AC-1)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockPassExecution);
        await flushPromises();

        const banner = element.shadowRoot.querySelector('.slds-alert_success');
        expect(banner).not.toBeNull();
    });

    it('displays Pass text label for pass status (AC-3: text, not color alone)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockPassExecution);
        await flushPromises();

        const strong = element.shadowRoot.querySelector('strong');
        expect(strong).not.toBeNull();
        expect(strong.textContent).toBe('Pass');
    });

    it('uses success icon for pass status (AC-3: icon, not color alone)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockPassExecution);
        await flushPromises();

        const icon = element.shadowRoot.querySelector('lightning-icon');
        expect(icon).not.toBeNull();
        expect(icon.iconName).toBe('utility:success');
    });

    it('displays deployer identity from InitiatedBy__r.Name (AC-2)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockPassExecution);
        await flushPromises();

        const bannerText = element.shadowRoot.querySelector('.slds-notify_alert').textContent;
        expect(bannerText).toContain('Jane Smith');
    });

    it('displays formatted duration (AC-2)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockPassExecution);
        await flushPromises();

        const bannerText = element.shadowRoot.querySelector('.slds-notify_alert').textContent;
        // 125000ms = 2m 5s
        expect(bannerText).toContain('2m 5s');
    });

    it('renders scenario counts', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockPassExecution);
        await flushPromises();

        const bannerText = element.shadowRoot.querySelector('.slds-notify_alert').textContent;
        expect(bannerText).toContain('10');
    });
});

// =============================================================================
// Fail state (AC-1, AC-3)
// =============================================================================

describe('fail state', () => {
    it('applies error SLDS class for fail status (AC-1)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockFailExecution);
        await flushPromises();

        const banner = element.shadowRoot.querySelector('.slds-alert_error');
        expect(banner).not.toBeNull();
    });

    it('displays Fail text label (AC-3)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockFailExecution);
        await flushPromises();

        const strong = element.shadowRoot.querySelector('strong');
        expect(strong.textContent).toBe('Fail');
    });

    it('uses error icon for fail status (AC-3)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockFailExecution);
        await flushPromises();

        const icon = element.shadowRoot.querySelector('lightning-icon');
        expect(icon.iconName).toBe('utility:error');
    });

    it('displays failed scenario count', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockFailExecution);
        await flushPromises();

        const bannerText = element.shadowRoot.querySelector('.slds-notify_alert').textContent;
        expect(bannerText).toContain('4');
    });
});

// =============================================================================
// In-progress state (AC-1, AC-3)
// =============================================================================

describe('in-progress state', () => {
    it('applies offline SLDS class for in-progress status (AC-1)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockInProgressExecution);
        await flushPromises();

        const banner = element.shadowRoot.querySelector('.slds-alert_offline');
        expect(banner).not.toBeNull();
    });

    it('displays "In Progress" text label (AC-3)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockInProgressExecution);
        await flushPromises();

        const strong = element.shadowRoot.querySelector('strong');
        expect(strong.textContent).toBe('In Progress');
    });

    it('uses spinner icon for in-progress status (AC-3)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockInProgressExecution);
        await flushPromises();

        const icon = element.shadowRoot.querySelector('lightning-icon');
        expect(icon.iconName).toBe('utility:spinner');
    });

    it('falls back to TriggerSource__c when InitiatedBy__r is null (AC-2)', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockInProgressExecution);
        await flushPromises();

        const bannerText = element.shadowRoot.querySelector('.slds-notify_alert').textContent;
        expect(bannerText).toContain('Platform Event');
    });

    it('does not display duration when ExecutionTimeMs__c is null', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockInProgressExecution);
        await flushPromises();

        // ExecutionTimeMs__c is null in inProgressExecution fixture
        // Duration may show elapsed time from StartTime if StartTime is present,
        // but will not show "null" or "undefineds"
        const bannerText = element.shadowRoot.querySelector('.slds-notify_alert').textContent;
        expect(bannerText).not.toContain('null');
        expect(bannerText).not.toContain('undefined');
    });
});

// =============================================================================
// Error state
// =============================================================================

describe('error state', () => {
    it('shows error fallback when wire errors', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.error({ message: 'Network error' });
        await flushPromises();

        const warning = element.shadowRoot.querySelector('.slds-alert_warning');
        expect(warning).not.toBeNull();
    });

    it('shows retry link in error state', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.error({ message: 'Network error' });
        await flushPromises();

        const retryLink = element.shadowRoot.querySelector('a[role="button"]');
        expect(retryLink).not.toBeNull();
        expect(retryLink.textContent).toBe('retry');
    });

    it('dispatches loaderror custom event on wire error', async () => {
        const element = createComponent();
        const errorHandler = jest.fn();
        element.addEventListener('loaderror', errorHandler);

        getLatestExecutionAdapter.error({ message: 'Network error' });
        await flushPromises();

        expect(errorHandler).toHaveBeenCalledTimes(1);
    });
});

// =============================================================================
// Duration formatting
// =============================================================================

describe('duration formatting', () => {
    it('formats 125000ms as "2m 5s"', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockPassExecution); // ExecutionTimeMs__c: 125000
        await flushPromises();

        const bannerText = element.shadowRoot.querySelector('.slds-notify_alert').textContent;
        expect(bannerText).toContain('2m 5s');
    });

    it('formats 90000ms as "1m 30s"', async () => {
        const element = createComponent();
        getLatestExecutionAdapter.emit(mockFailExecution); // ExecutionTimeMs__c: 90000
        await flushPromises();

        const bannerText = element.shadowRoot.querySelector('.slds-notify_alert').textContent;
        expect(bannerText).toContain('1m 30s');
    });

    it('formats 45000ms (45s) without minutes', async () => {
        const element = createComponent();
        const shortExecution = { ...mockPassExecution, ExecutionTimeMs__c: 45000 };
        getLatestExecutionAdapter.emit(shortExecution);
        await flushPromises();

        const bannerText = element.shadowRoot.querySelector('.slds-notify_alert').textContent;
        expect(bannerText).toContain('45s');
        expect(bannerText).not.toContain('0m');
    });
});
