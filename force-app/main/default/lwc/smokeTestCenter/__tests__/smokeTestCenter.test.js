import { createElement } from 'lwc';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import { NavigationMixin } from 'lightning/navigation';
import SmokeTestCenter from 'c/smokeTestCenter';
import checkUserPermissions from '@salesforce/apex/SmokeTestDashboardController.checkUserPermissions';
import getLatestExecution from '@salesforce/apex/SmokeTestDashboardController.getLatestExecution';

import mockAdminPermissions  from './data/adminPermissions.json';
import mockViewerPermissions from './data/viewerPermissions.json';
import mockNoPermissions     from './data/noPermissions.json';

const checkUserPermissionsAdapter = registerApexTestWireAdapter(checkUserPermissions);
const getLatestExecutionAdapter   = registerApexTestWireAdapter(getLatestExecution);

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
        // Wire adapter not yet emitted — component should be in loading state
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
        // getLatestExecutionAdapter never emits — wire stays undefined
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

        // Dashboard slot should be accessible
        const slot = element.shadowRoot.querySelector('slot');
        expect(slot).not.toBeNull();
    });

    it('hides onboarding and shows dashboard after execution wire returns data', async () => {
        const element = createComponent();
        checkUserPermissionsAdapter.emit(mockAdminPermissions);
        // First emit null (onboarding shows)
        getLatestExecutionAdapter.emit(null);
        await flushPromises();
        expect(element.shadowRoot.querySelector('c-onboarding-card')).not.toBeNull();

        // Then emit an execution record (onboarding hides)
        getLatestExecutionAdapter.emit({ Id: 'a001', Status__c: 'Completed', OverallResult__c: 'Pass' });
        await flushPromises();
        expect(element.shadowRoot.querySelector('c-onboarding-card')).toBeNull();
    });
});
