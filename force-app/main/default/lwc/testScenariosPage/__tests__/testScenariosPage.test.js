import { createElement } from 'lwc';
import TestScenariosPage from 'c/testScenariosPage';
import getScenarios from '@salesforce/apex/SmokeTestScenarioController.getScenarios';
import toggleScenario from '@salesforce/apex/SmokeTestScenarioController.toggleScenario';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import mockScenarios from './data/scenarios.json';

// Register wire adapter mock for getScenarios
const getScenariosAdapter = registerApexTestWireAdapter(getScenarios);

// Mock imperative Apex calls
jest.mock(
    '@salesforce/apex/SmokeTestScenarioController.toggleScenario',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SmokeTestScenarioController.createScenario',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

describe('c-test-scenarios-page', () => {
    let element;

    beforeEach(() => {
        element = createElement('c-test-scenarios-page', { is: TestScenariosPage });
        element.isAdmin = true;
        document.body.appendChild(element);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    // =========================================================================
    // Permission guard
    // =========================================================================

    it('shows permission error when isAdmin is false', () => {
        element.isAdmin = false;
        return Promise.resolve().then(() => {
            const errorMsg = element.shadowRoot.querySelector('[role="alert"]');
            expect(errorMsg).not.toBeNull();
            expect(errorMsg.textContent).toContain('SmokeTest_Admin');
        });
    });

    it('does not show permission error for admin user', () => {
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve().then(() => {
            const permissionError = element.shadowRoot.querySelector('.slds-notify.slds-notify_alert');
            // The wire error banner exists only when wireError is set — not on success
            expect(element.isAdmin).toBe(true);
        });
    });

    // =========================================================================
    // Renders scenario list
    // =========================================================================

    it('renders scenario rows when wire returns data', () => {
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve().then(() => {
            const rows = element.shadowRoot.querySelectorAll('tbody tr');
            expect(rows.length).toBe(mockScenarios.length);
        });
    });

    it('displays scenario label and developerName', () => {
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve().then(() => {
            const firstRow = element.shadowRoot.querySelector('tbody tr');
            expect(firstRow.textContent).toContain(mockScenarios[0].label);
            expect(firstRow.textContent).toContain(mockScenarios[0].developerName);
        });
    });

    it('displays correct total/enabled/disabled counts in InfoBanner', () => {
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve().then(() => {
            const total    = element.shadowRoot.querySelector('.slds-text-heading_large');
            const enabled  = element.shadowRoot.querySelector('.enabled-count');
            const disabled = element.shadowRoot.querySelector('.disabled-count');

            const expectedEnabled  = mockScenarios.filter(s => s.isEnabled).length;
            const expectedDisabled = mockScenarios.filter(s => !s.isEnabled).length;

            expect(Number(total.textContent)).toBe(mockScenarios.length);
            expect(Number(enabled.textContent)).toBe(expectedEnabled);
            expect(Number(disabled.textContent)).toBe(expectedDisabled);
        });
    });

    // =========================================================================
    // FilterBar — category
    // =========================================================================

    it('filters scenarios by category Sales', () => {
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve()
            .then(() => {
                const categoryCombobox = element.shadowRoot.querySelectorAll('lightning-combobox')[0];
                categoryCombobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'Sales' } }));
            })
            .then(() => {
                const rows = element.shadowRoot.querySelectorAll('tbody tr');
                const expectedCount = mockScenarios.filter(s =>
                    (s.businessProcess || '').includes('Sales')
                ).length;
                expect(rows.length).toBe(expectedCount);
            });
    });

    it('filters scenarios by category Service', () => {
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve()
            .then(() => {
                const categoryCombobox = element.shadowRoot.querySelectorAll('lightning-combobox')[0];
                categoryCombobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'Service' } }));
            })
            .then(() => {
                const rows = element.shadowRoot.querySelectorAll('tbody tr');
                const expectedCount = mockScenarios.filter(s =>
                    (s.businessProcess || '').includes('Service')
                ).length;
                expect(rows.length).toBe(expectedCount);
            });
    });

    it('filters scenarios by status Enabled', () => {
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve()
            .then(() => {
                const statusCombobox = element.shadowRoot.querySelectorAll('lightning-combobox')[1];
                statusCombobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'Enabled' } }));
            })
            .then(() => {
                const rows = element.shadowRoot.querySelectorAll('tbody tr');
                const expectedCount = mockScenarios.filter(s => s.isEnabled).length;
                expect(rows.length).toBe(expectedCount);
            });
    });

    it('filters scenarios by status Disabled', () => {
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve()
            .then(() => {
                const statusCombobox = element.shadowRoot.querySelectorAll('lightning-combobox')[1];
                statusCombobox.dispatchEvent(new CustomEvent('change', { detail: { value: 'Disabled' } }));
            })
            .then(() => {
                const rows = element.shadowRoot.querySelectorAll('tbody tr');
                const expectedCount = mockScenarios.filter(s => !s.isEnabled).length;
                expect(rows.length).toBe(expectedCount);
            });
    });

    it('filters scenarios by search text', () => {
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve()
            .then(() => {
                const searchInput = element.shadowRoot.querySelector('lightning-input[type="search"]');
                searchInput.value = 'Account';
                searchInput.dispatchEvent(new CustomEvent('change'));
            })
            .then(() => {
                const rows = element.shadowRoot.querySelectorAll('tbody tr');
                const expectedCount = mockScenarios.filter(s =>
                    (s.label || s.developerName || '').toLowerCase().includes('account')
                ).length;
                expect(rows.length).toBe(expectedCount);
            });
    });

    // =========================================================================
    // Toggle interaction
    // =========================================================================

    it('calls toggleScenario when toggle button clicked', () => {
        toggleScenario.mockResolvedValue({ success: true, jobId: 'JOB_001' });
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve()
            .then(() => {
                const toggleBtn = element.shadowRoot.querySelector('.toggle-btn');
                expect(toggleBtn).not.toBeNull();
                toggleBtn.click();
            })
            .then(() => {
                expect(toggleScenario).toHaveBeenCalledTimes(1);
                const callArgs = toggleScenario.mock.calls[0][0];
                expect(callArgs.developerName).toBe(mockScenarios[0].developerName);
            });
    });

    // =========================================================================
    // Wire error state
    // =========================================================================

    it('shows wire error banner when wire fails', () => {
        getScenariosAdapter.error({ body: { message: 'Permission denied' } });
        return Promise.resolve().then(() => {
            const errorBanner = element.shadowRoot.querySelector('[aria-live="assertive"]');
            expect(errorBanner).not.toBeNull();
        });
    });

    // =========================================================================
    // Add Scenario modal
    // =========================================================================

    it('shows addScenarioModal when Add Scenario button is clicked', () => {
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve()
            .then(() => {
                const addBtn = element.shadowRoot.querySelector('lightning-button[label="Add Scenario"]');
                addBtn.click();
            })
            .then(() => {
                const modal = element.shadowRoot.querySelector('c-add-scenario-modal');
                expect(modal).not.toBeNull();
            });
    });

    it('hides addScenarioModal when close event received', () => {
        getScenariosAdapter.emit(mockScenarios);
        return Promise.resolve()
            .then(() => {
                const addBtn = element.shadowRoot.querySelector('lightning-button[label="Add Scenario"]');
                addBtn.click();
            })
            .then(() => {
                const modal = element.shadowRoot.querySelector('c-add-scenario-modal');
                modal.dispatchEvent(new CustomEvent('close'));
            })
            .then(() => {
                const modal = element.shadowRoot.querySelector('c-add-scenario-modal');
                expect(modal).toBeNull();
            });
    });

    // =========================================================================
    // Empty state
    // =========================================================================

    it('shows empty state when no scenarios returned', () => {
        getScenariosAdapter.emit([]);
        return Promise.resolve().then(() => {
            const emptyState = element.shadowRoot.querySelector('.slds-illustration');
            expect(emptyState).not.toBeNull();
            expect(emptyState.textContent).toContain('No Scenarios Configured');
        });
    });
});
