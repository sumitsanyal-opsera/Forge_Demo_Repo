import { createElement } from 'lwc';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import SmokeTestCenter from 'c/smokeTestCenter';
import checkUserPermissions from '@salesforce/apex/SmokeTestDashboardController.checkUserPermissions';
import getLatestExecution from '@salesforce/apex/SmokeTestDashboardController.getLatestExecution';

import mockAdminPermissions  from './data/adminPermissions.json';
import mockViewerPermissions from './data/viewerPermissions.json';
import mockNoPermissions     from './data/noPermissions.json';
import mockProgressEvent     from './data/progressEvent.json';
import mockCompleteEvent     from './data/completeEvent.json';

const checkUserPermissionsAdapter = registerApexTestWireAdapter(checkUserPermissions);
const getLatestExecutionAdapter   = registerApexTestWireAdapter(getLatestExecution);

const PROGRESS_CHANNEL = '/event/SmokeTestProgress__e';
const COMPLETE_CHANNEL = '/event/SmokeTestComplete__e';

const flushPromises = () => new Promise(resolve => setTimeout(resolve, 0));

function createComponent() {
    const element = createElement('c-smoke-test-center', { is: SmokeTestCenter });
    // Mock NavigationMixin.Navigate to prevent infinite recursion in test environment
    element[NavigationMixin.Navigate] = jest.fn();
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
    it('shows spinner before wire data resolves', () => {
        const element = createComponent();
        const spinner = element.shadowRoot.querySelector('.slds-spinner');
        expect(spinner).not.toBeNull();
    });

    it('does not render app shell while loading', () => {
        const element = createComponent();
        const appShell = element.shadowRoot.querySelector('.app-shell');
        expect(appShell).toBeNull();
    });
});

// =============================================================================
// Admin permission state
// =============================================================================

describe('admin user', () => {
    it('renders app shell for admin user', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const appShell = element.shadowRoot.querySelector('.app-shell');
        expect(appShell).not.toBeNull();
    });

    it('does not render access-denied card for admin user', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const denied = element.shadowRoot.querySelector('.access-denied');
        expect(denied).toBeNull();
    });

    it('renders admin-only security panels slot for admin user', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const adminPanels = element.shadowRoot.querySelector('.admin-panels');
        expect(adminPanels).not.toBeNull();
    });

    it('hides spinner after data resolves', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const spinner = element.shadowRoot.querySelector('.slds-spinner');
        expect(spinner).toBeNull();
    });
});

// =============================================================================
// Viewer permission state
// =============================================================================

describe('viewer user', () => {
    it('renders app shell for viewer user', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockViewerPermissions);
        await flushPromises();

        const appShell = element.shadowRoot.querySelector('.app-shell');
        expect(appShell).not.toBeNull();
    });

    it('does not render admin-only security panels for viewer', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockViewerPermissions);
        await flushPromises();

        const adminPanels = element.shadowRoot.querySelector('.admin-panels');
        expect(adminPanels).toBeNull();
    });

    it('does not show access-denied for viewer', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockViewerPermissions);
        await flushPromises();

        const denied = element.shadowRoot.querySelector('.access-denied');
        expect(denied).toBeNull();
    });
});

// =============================================================================
// No permission state
// =============================================================================

describe('unauthorized user', () => {
    it('renders access-denied card when permissionLevel is none', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockNoPermissions);
        await flushPromises();

        const denied = element.shadowRoot.querySelector('.access-denied');
        expect(denied).not.toBeNull();
    });

    it('does not render app shell for unauthorized user', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockNoPermissions);
        await flushPromises();

        const appShell = element.shadowRoot.querySelector('.app-shell');
        expect(appShell).toBeNull();
    });

    it('access-denied message contains permission set name', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockNoPermissions);
        await flushPromises();

        const denied = element.shadowRoot.querySelector('.access-denied');
        expect(denied.textContent).toContain('SmokeTest_Dashboard_Viewer');
    });
});

// =============================================================================
// Error state
// =============================================================================

describe('error handling', () => {
    it('renders error banner when wire adapter returns an error', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.error({ body: { message: 'Permission check failed' }, status: 500 });
        await flushPromises();

        const errorBanner = element.shadowRoot.querySelector('[role="alert"]');
        expect(errorBanner).not.toBeNull();
    });

    it('shows error message from body when available', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.error({ body: { message: 'Server error occurred' }, status: 500 });
        await flushPromises();

        const errorBanner = element.shadowRoot.querySelector('[role="alert"]');
        expect(errorBanner.textContent).toContain('Server error occurred');
    });

    it('shows fallback message when error body has no message', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.error({});
        await flushPromises();

        const errorBanner = element.shadowRoot.querySelector('[role="alert"]');
        expect(errorBanner.textContent).toContain('Unable to verify permissions');
    });

    it('renders retry button in error state', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.error({ body: { message: 'Error' } });
        await flushPromises();

        const retryButton = element.shadowRoot.querySelector('button');
        expect(retryButton).not.toBeNull();
        expect(retryButton.textContent.trim()).toBe('Retry');
    });

    it('hides spinner in error state', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.error({ body: { message: 'Error' } });
        await flushPromises();

        const spinner = element.shadowRoot.querySelector('.slds-spinner');
        expect(spinner).toBeNull();
    });
});

// =============================================================================
// Sidebar navigation rendering
// =============================================================================

describe('sidebar navigation', () => {
    it('renders exactly 8 navigation items', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const navItems = element.shadowRoot.querySelectorAll('.slds-nav-vertical__item');
        expect(navItems.length).toBe(8);
    });

    it('renders three navigation sections', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const sections = element.shadowRoot.querySelectorAll('.slds-nav-vertical__section');
        expect(sections.length).toBe(3);
    });

    it('renders Dashboard, Configuration, and History section headings', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const headings = element.shadowRoot.querySelectorAll('.slds-nav-vertical__title');
        const headingTexts = Array.from(headings).map(h => h.textContent.trim());
        expect(headingTexts).toContain('Dashboard');
        expect(headingTexts).toContain('Configuration');
        expect(headingTexts).toContain('History');
    });

    it('marks overview as active by default', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const activeItems = element.shadowRoot.querySelectorAll('.slds-is-active');
        expect(activeItems.length).toBe(1);

        const overviewLink = element.shadowRoot.querySelector('[data-page-id="overview"]');
        const overviewItem = overviewLink.closest('li');
        expect(overviewItem.classList.contains('slds-is-active')).toBe(true);
    });
});

// =============================================================================
// Navigation event dispatching
// =============================================================================

describe('navigation events', () => {
    it('updates activePageId when a nav item is clicked', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const executionDetailLink = element.shadowRoot.querySelector('[data-page-id="executionDetail"]');
        executionDetailLink.click();
        await flushPromises();

        const activeItem = element.shadowRoot.querySelector('.slds-is-active');
        expect(activeItem.querySelector('[data-page-id="executionDetail"]')).not.toBeNull();
    });

    it('calls NavigationMixin.Navigate when a nav item is clicked', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const overviewLink = element.shadowRoot.querySelector('[data-page-id="overview"]');
        overviewLink.click();
        await flushPromises();

        expect(element[NavigationMixin.Navigate]).toHaveBeenCalledWith(
            expect.objectContaining({
                type: 'standard__navItemPage',
                attributes: expect.objectContaining({ apiName: 'overview' })
            })
        );
    });

    it('routes to security page when Security Health nav item is clicked', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const securityLink = element.shadowRoot.querySelector('[data-page-id="security"]');
        securityLink.click();
        await flushPromises();

        expect(element[NavigationMixin.Navigate]).toHaveBeenCalledWith(
            expect.objectContaining({
                type: 'standard__navItemPage',
                attributes: expect.objectContaining({ apiName: 'security' })
            })
        );
    });
});

// =============================================================================
// Onboarding card conditional rendering (AC-1, AC-5)
// =============================================================================

describe('onboarding card visibility', () => {
    it('renders c-onboarding-card when getLatestExecution returns null', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        getLatestExecutionAdapter.emit(null);
        await flushPromises();

        const onboardingCard = element.shadowRoot.querySelector('c-onboarding-card');
        expect(onboardingCard).not.toBeNull();
    });

    it('does not render c-onboarding-card when execution data exists', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        getLatestExecutionAdapter.emit({ Id: 'a001', Status__c: 'Completed', OverallResult__c: 'Pass' });
        await flushPromises();

        const onboardingCard = element.shadowRoot.querySelector('c-onboarding-card');
        expect(onboardingCard).toBeNull();
    });

    it('does not render c-onboarding-card before execution wire resolves', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const onboardingCard = element.shadowRoot.querySelector('c-onboarding-card');
        expect(onboardingCard).toBeNull();
    });

    it('passes isAdmin=true to onboarding card for admin user', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        getLatestExecutionAdapter.emit(null);
        await flushPromises();

        const onboardingCard = element.shadowRoot.querySelector('c-onboarding-card');
        expect(onboardingCard).not.toBeNull();
        expect(onboardingCard.isAdmin).toBe(true);
    });

    it('passes isAdmin=false to onboarding card for viewer user', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockViewerPermissions);
        getLatestExecutionAdapter.emit(null);
        await flushPromises();

        const onboardingCard = element.shadowRoot.querySelector('c-onboarding-card');
        expect(onboardingCard).not.toBeNull();
        expect(onboardingCard.isAdmin).toBe(false);
    });

    it('shows dashboard panels (not onboarding) when execution data exists', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        getLatestExecutionAdapter.emit({ Id: 'a001', Status__c: 'Completed', OverallResult__c: 'Pass' });
        await flushPromises();

        const slot = element.shadowRoot.querySelector('slot');
        expect(slot).not.toBeNull();
    });

    it('hides onboarding and shows dashboard after execution wire returns data', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        getLatestExecutionAdapter.emit(null);
        await flushPromises();
        expect(element.shadowRoot.querySelector('c-onboarding-card')).not.toBeNull();

        getLatestExecutionAdapter.emit({ Id: 'a001', Status__c: 'Completed', OverallResult__c: 'Pass' });
        await flushPromises();
        expect(element.shadowRoot.querySelector('c-onboarding-card')).toBeNull();
    });
});

// =============================================================================
// Platform Event subscription (AC-1, AC-5)
// =============================================================================

describe('Platform Event subscription', () => {
    it('subscribes to SmokeTestProgress__e on connectedCallback', async () => {
        createComponent();
        await flushPromises();

        const progressCall = subscribe.mock.calls.find(c => c[0] === PROGRESS_CHANNEL);
        expect(progressCall).toBeDefined();
        expect(progressCall[1]).toBe(-1);
        expect(typeof progressCall[2]).toBe('function');
    });

    it('subscribes to SmokeTestComplete__e on connectedCallback', async () => {
        createComponent();
        await flushPromises();

        const completeCall = subscribe.mock.calls.find(c => c[0] === COMPLETE_CHANNEL);
        expect(completeCall).toBeDefined();
        expect(completeCall[1]).toBe(-1);
        expect(typeof completeCall[2]).toBe('function');
    });

    it('registers onError handler on connectedCallback', async () => {
        createComponent();
        await flushPromises();

        expect(onError).toHaveBeenCalledWith(expect.any(Function));
    });

    it('unsubscribes from both channels on disconnectedCallback', async () => {
        const element = createComponent();
        await flushPromises();

        document.body.removeChild(element);
        await flushPromises();

        expect(unsubscribe).toHaveBeenCalledTimes(2);
    });
});

// =============================================================================
// Progress event handling (AC-2)
// =============================================================================

describe('progress event handling', () => {
    it('updates progressData when a progress event is received', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const progressCall = subscribe.mock.calls.find(c => c[0] === PROGRESS_CHANNEL);
        progressCall[2](mockProgressEvent);
        await flushPromises();

        const indicator = element.shadowRoot.querySelector('.progress-indicator');
        expect(indicator).not.toBeNull();
        expect(indicator.textContent).toContain('3');
        expect(indicator.textContent).toContain('10');
    });

    it('shows progress label with correct text format', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const progressCall = subscribe.mock.calls.find(c => c[0] === PROGRESS_CHANNEL);
        progressCall[2](mockProgressEvent);
        await flushPromises();

        const indicator = element.shadowRoot.querySelector('.progress-indicator');
        expect(indicator.textContent.trim()).toContain('In Progress:');
        expect(indicator.textContent.trim()).toContain('scenarios complete');
    });

    it('ignores duplicate progress events (idempotent — same completedScenarios)', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const progressCall = subscribe.mock.calls.find(c => c[0] === PROGRESS_CHANNEL);
        progressCall[2](mockProgressEvent); // completedScenarios = 3
        await flushPromises();

        // Send a lower count — should be ignored
        progressCall[2]({
            data: { payload: { ...mockProgressEvent.data.payload, CompletedScenarios__c: 2 } }
        });
        await flushPromises();

        // Should still show 3 (the higher count)
        const indicator = element.shadowRoot.querySelector('.progress-indicator');
        expect(indicator.textContent).toContain('3');
    });

    it('hides progress indicator before any progress events', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const indicator = element.shadowRoot.querySelector('.progress-indicator');
        expect(indicator).toBeNull();
    });
});

// =============================================================================
// Complete event handling (AC-3)
// =============================================================================

describe('complete event handling', () => {
    it('dispatches refreshdashboard event on complete event', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const refreshHandler = jest.fn();
        element.addEventListener('refreshdashboard', refreshHandler);

        const completeCall = subscribe.mock.calls.find(c => c[0] === COMPLETE_CHANNEL);
        completeCall[2](mockCompleteEvent);
        await flushPromises();

        expect(refreshHandler).toHaveBeenCalledTimes(1);
    });

    it('refreshdashboard event detail contains executionId and overallResult', async () => {
        const element = createComponent();
        await flushPromises();

        let capturedDetail;
        element.addEventListener('refreshdashboard', e => { capturedDetail = e.detail; });

        const completeCall = subscribe.mock.calls.find(c => c[0] === COMPLETE_CHANNEL);
        completeCall[2](mockCompleteEvent);
        await flushPromises();

        expect(capturedDetail.executionId).toBe('a00000000000001AAA');
        expect(capturedDetail.overallResult).toBe('Pass');
        expect(capturedDetail.totalDurationMs).toBe(45000);
    });

    it('clears progressData after complete event', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        // First set progressData via progress event
        const progressCall = subscribe.mock.calls.find(c => c[0] === PROGRESS_CHANNEL);
        progressCall[2](mockProgressEvent);
        await flushPromises();

        const indicatorBefore = element.shadowRoot.querySelector('.progress-indicator');
        expect(indicatorBefore).not.toBeNull();

        // Now send complete event
        const completeCall = subscribe.mock.calls.find(c => c[0] === COMPLETE_CHANNEL);
        completeCall[2](mockCompleteEvent);
        await flushPromises();

        const indicatorAfter = element.shadowRoot.querySelector('.progress-indicator');
        expect(indicatorAfter).toBeNull();
    });
});

// =============================================================================
// Auto-refresh timer (AC-4)
// =============================================================================

describe('auto-refresh timer', () => {
    it('starts a 30-second setInterval after first progress event', async () => {
        const setIntervalSpy = jest.spyOn(global, 'setInterval');

        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const progressCall = subscribe.mock.calls.find(c => c[0] === PROGRESS_CHANNEL);
        progressCall[2](mockProgressEvent);

        expect(setIntervalSpy).toHaveBeenCalledWith(expect.any(Function), 30000);
        setIntervalSpy.mockRestore();
    });

    it('does not start duplicate timers on repeated progress events', async () => {
        const setIntervalSpy = jest.spyOn(global, 'setInterval');

        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const progressCall = subscribe.mock.calls.find(c => c[0] === PROGRESS_CHANNEL);
        progressCall[2](mockProgressEvent);
        progressCall[2]({
            data: { payload: { ...mockProgressEvent.data.payload, CompletedScenarios__c: 5 } }
        });

        // setInterval should only be called once (timer guard _refreshTimerId check)
        expect(setIntervalSpy).toHaveBeenCalledTimes(1);
        setIntervalSpy.mockRestore();
    });

    it('clears timer on complete event', async () => {
        const clearIntervalSpy = jest.spyOn(global, 'clearInterval');

        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        // Start timer via progress event
        const progressCall = subscribe.mock.calls.find(c => c[0] === PROGRESS_CHANNEL);
        progressCall[2](mockProgressEvent);

        // Send complete event — should clear timer
        const completeCall = subscribe.mock.calls.find(c => c[0] === COMPLETE_CHANNEL);
        completeCall[2](mockCompleteEvent);

        expect(clearIntervalSpy).toHaveBeenCalled();
        clearIntervalSpy.mockRestore();
    });

    it('clears timer on disconnectedCallback', async () => {
        const clearIntervalSpy = jest.spyOn(global, 'clearInterval');

        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        // Start timer
        const progressCall = subscribe.mock.calls.find(c => c[0] === PROGRESS_CHANNEL);
        progressCall[2](mockProgressEvent);

        document.body.removeChild(element);

        expect(clearIntervalSpy).toHaveBeenCalled();
        clearIntervalSpy.mockRestore();
    });
});

// =============================================================================
// empApi error fallback (error handling, reconnection, AC-7)
// =============================================================================

describe('empApi error fallback', () => {
    it('retries subscription on empApi error (up to 3 times)', async () => {
        createComponent();
        await flushPromises();

        // Initial 2 subscribe calls (progress + complete)
        const initialSubscribeCount = subscribe.mock.calls.length;

        const errorCallback = onError.mock.calls[0][0];

        // First error → retry (setTimeout scheduled, not executed without fake timers)
        errorCallback({ code: 'STREAMING_LIMIT_EXCEEDED' });

        // subscribe should NOT be called again synchronously (it's inside setTimeout)
        expect(subscribe.mock.calls.length).toBe(initialSubscribeCount);
    });

    it('shows fallback warning banner after exceeding max retry attempts', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const errorCallback = onError.mock.calls[0][0];

        // Exceed MAX_RETRY_ATTEMPTS (3): on the 4th call, fallback activates
        errorCallback({}); // retryCount → 1
        errorCallback({}); // retryCount → 2
        errorCallback({}); // retryCount → 3
        errorCallback({}); // 3 is NOT < 3 → fallback
        await flushPromises();

        const warning = element.shadowRoot.querySelector('.fallback-warning');
        expect(warning).not.toBeNull();
    });

    it('starts auto-refresh timer when entering fallback mode', async () => {
        const setIntervalSpy = jest.spyOn(global, 'setInterval');

        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const errorCallback = onError.mock.calls[0][0];
        errorCallback({});
        errorCallback({});
        errorCallback({});
        errorCallback({}); // triggers fallback

        expect(setIntervalSpy).toHaveBeenCalledWith(expect.any(Function), 30000);
        setIntervalSpy.mockRestore();
    });
});

// =============================================================================
// Manual refresh button (AC-6)
// =============================================================================

describe('manual refresh button', () => {
    it('renders manual refresh button in the content header', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const refreshBtn = element.shadowRoot.querySelector('[data-id="manual-refresh"]');
        expect(refreshBtn).not.toBeNull();
    });

    it('dispatches refreshdashboard event when refresh button is clicked', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        await flushPromises();

        const refreshHandler = jest.fn();
        element.addEventListener('refreshdashboard', refreshHandler);

        const refreshBtn = element.shadowRoot.querySelector('[data-id="manual-refresh"]');
        refreshBtn.click();
        await flushPromises();

        expect(refreshHandler).toHaveBeenCalledTimes(1);
    });

    it('manual refresh button is always visible regardless of execution state', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        getLatestExecutionAdapter.emit({ Id: 'a001', Status__c: 'Completed', OverallResult__c: 'Pass' });
        await flushPromises();

        const refreshBtn = element.shadowRoot.querySelector('[data-id="manual-refresh"]');
        expect(refreshBtn).not.toBeNull();
    });
});
