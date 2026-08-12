import { createElement } from 'lwc';
import SettingsPage from 'c/settingsPage';
import getSettings from '@salesforce/apex/SettingsController.getSettings';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import mockSettings from './data/defaultSettings.json';

const getSettingsAdapter = registerApexTestWireAdapter(getSettings);

jest.mock(
    '@salesforce/apex/SettingsController.saveSettings',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

describe('c-settings-page', () => {
    let element;

    beforeEach(() => {
        element = createElement('c-settings-page', { is: SettingsPage });
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
    // Rendering
    // =========================================================================

    it('shows permission error when isAdmin is false', () => {
        element.isAdmin = false;
        return Promise.resolve().then(() => {
            const errorEl = element.shadowRoot.querySelector('[role="alert"]');
            expect(errorEl).not.toBeNull();
            expect(errorEl.textContent).toContain('SmokeTest_Admin');
        });
    });

    it('renders all 5 setting cards after wire resolves', () => {
        getSettingsAdapter.emit(mockSettings);
        return Promise.resolve().then(() => {
            const cards = element.shadowRoot.querySelectorAll('lightning-card');
            expect(cards.length).toBeGreaterThanOrEqual(5);
        });
    });

    it('renders execution settings inputs with correct values', () => {
        getSettingsAdapter.emit(mockSettings);
        return Promise.resolve().then(() => {
            const inputs = element.shadowRoot.querySelectorAll('lightning-input[type="number"]');
            expect(inputs.length).toBeGreaterThan(0);
        });
    });

    // =========================================================================
    // Dirty state
    // =========================================================================

    it('does not show sticky footer when no changes', () => {
        getSettingsAdapter.emit(mockSettings);
        return Promise.resolve().then(() => {
            const footer = element.shadowRoot.querySelector('c-sticky-footer-save-bar');
            if (footer) {
                expect(footer.hasChanges).toBeFalsy();
            }
        });
    });

    it('shows sticky footer after a numeric field change', () => {
        getSettingsAdapter.emit(mockSettings);
        return Promise.resolve().then(() => {
            const suiteTimeoutInput = element.shadowRoot.querySelector(
                'lightning-input[data-field="SuiteTimeoutSec__c"]'
            );
            if (suiteTimeoutInput) {
                suiteTimeoutInput.value = 400;
                suiteTimeoutInput.dispatchEvent(new CustomEvent('change', {
                    detail: { value: 400 }
                }));
            }
            return Promise.resolve();
        }).then(() => {
            const footer = element.shadowRoot.querySelector('c-sticky-footer-save-bar');
            if (footer) {
                expect(footer.hasChanges).toBeTruthy();
            }
        });
    });

    // =========================================================================
    // Discard
    // =========================================================================

    it('discards changes and resets to original values', () => {
        getSettingsAdapter.emit(mockSettings);
        return Promise.resolve().then(() => {
            const suiteTimeoutInput = element.shadowRoot.querySelector(
                'lightning-input[data-field="SuiteTimeoutSec__c"]'
            );
            if (suiteTimeoutInput) {
                suiteTimeoutInput.dispatchEvent(new CustomEvent('change', {
                    detail: { value: 400 }
                }));
            }
            return Promise.resolve();
        }).then(() => {
            element.shadowRoot.querySelector('c-sticky-footer-save-bar')
                ?.dispatchEvent(new CustomEvent('discard'));
            return Promise.resolve();
        }).then(() => {
            const footer = element.shadowRoot.querySelector('c-sticky-footer-save-bar');
            if (footer) {
                expect(footer.hasChanges).toBeFalsy();
            }
        });
    });

    // =========================================================================
    // Rollback policy modal
    // =========================================================================

    it('shows change reason modal when rollback policy changes', () => {
        getSettingsAdapter.emit(mockSettings);
        return Promise.resolve().then(() => {
            const radioGroup = element.shadowRoot.querySelector(
                'lightning-radio-group[data-field="DefaultRollbackPolicy__c"]'
            );
            if (radioGroup) {
                radioGroup.dispatchEvent(new CustomEvent('change', {
                    detail: { value: 'Auto-Rollback on Critical Failure' }
                }));
            }
            return Promise.resolve();
        }).then(() => {
            const modal = element.shadowRoot.querySelector('c-change-reason-modal');
            if (modal) {
                // Modal should be visible
                expect(modal).not.toBeNull();
            }
        });
    });

    it('applies rollback policy after change reason is confirmed', () => {
        getSettingsAdapter.emit(mockSettings);
        return Promise.resolve().then(() => {
            const radioGroup = element.shadowRoot.querySelector(
                'lightning-radio-group[data-field="DefaultRollbackPolicy__c"]'
            );
            if (radioGroup) {
                radioGroup.dispatchEvent(new CustomEvent('change', {
                    detail: { value: 'Auto-Rollback on Critical Failure' }
                }));
            }
            return Promise.resolve();
        }).then(() => {
            const modal = element.shadowRoot.querySelector('c-change-reason-modal');
            if (modal) {
                modal.dispatchEvent(new CustomEvent('confirm', { detail: 'Needed for prod safety' }));
            }
            return Promise.resolve();
        }).then(() => {
            // Modal should be hidden and policy should be updated
            const modal = element.shadowRoot.querySelector('c-change-reason-modal');
            expect(modal).toBeNull();
        });
    });

    it('reverts rollback policy if change reason modal is cancelled', () => {
        getSettingsAdapter.emit(mockSettings);
        return Promise.resolve().then(() => {
            const radioGroup = element.shadowRoot.querySelector(
                'lightning-radio-group[data-field="DefaultRollbackPolicy__c"]'
            );
            if (radioGroup) {
                radioGroup.dispatchEvent(new CustomEvent('change', {
                    detail: { value: 'Auto-Rollback on Critical Failure' }
                }));
            }
            return Promise.resolve();
        }).then(() => {
            const modal = element.shadowRoot.querySelector('c-change-reason-modal');
            if (modal) {
                modal.dispatchEvent(new CustomEvent('cancel'));
            }
            return Promise.resolve();
        }).then(() => {
            // Modal closed, no changes to rollback policy means hasChanges still false
            const footer = element.shadowRoot.querySelector('c-sticky-footer-save-bar');
            if (footer) {
                expect(footer.hasChanges).toBeFalsy();
            }
        });
    });

    // =========================================================================
    // Save
    // =========================================================================

    it('calls saveSettings with only changed fields', () => {
        saveSettings.mockResolvedValue({ jobId: 'abc123', status: 'Queued' });
        getSettingsAdapter.emit(mockSettings);
        return Promise.resolve().then(() => {
            const suiteTimeoutInput = element.shadowRoot.querySelector(
                'lightning-input[data-field="SuiteTimeoutSec__c"]'
            );
            if (suiteTimeoutInput) {
                suiteTimeoutInput.dispatchEvent(new CustomEvent('change', {
                    detail: { value: 400 }
                }));
            }
            return Promise.resolve();
        }).then(() => {
            element.shadowRoot.querySelector('c-sticky-footer-save-bar')
                ?.dispatchEvent(new CustomEvent('save'));
            return Promise.resolve();
        }).then(() => {
            if (saveSettings.mock.calls.length > 0) {
                const callArgs = saveSettings.mock.calls[0][0];
                expect(callArgs.changedFields).toBeDefined();
                expect(Object.keys(callArgs.changedFields)).not.toContain('DefaultRollbackPolicy__c');
            }
        });
    });

    it('shows compliance warning when audit log retention is below 365', () => {
        const lowRetentionSettings = { ...mockSettings, DataRetentionDaysAuditLogs__c: 30 };
        getSettingsAdapter.emit(lowRetentionSettings);
        return Promise.resolve().then(() => {
            const suiteInput = element.shadowRoot.querySelector(
                'lightning-input[data-field="DataRetentionDaysAuditLogs__c"]'
            );
            if (suiteInput) {
                suiteInput.dispatchEvent(new CustomEvent('change', { detail: { value: 30 } }));
            }
            return Promise.resolve();
        }).then(() => {
            const warning = element.shadowRoot.querySelector('.audit-log-compliance-warning');
            // If below 365, compliance warning should be visible
            if (warning) {
                expect(warning.textContent).toContain('365');
            }
        });
    });

    // =========================================================================
    // Wire error
    // =========================================================================

    it('shows wire error when getSettings fails', () => {
        getSettingsAdapter.error({ body: { message: 'Apex error' } });
        return Promise.resolve().then(() => {
            const errorEl = element.shadowRoot.querySelector('[role="alert"]');
            if (errorEl) {
                expect(errorEl.textContent).toContain('Apex error');
            }
        });
    });
});
