import { createElement } from 'lwc';
import AddScenarioModal from 'c/addScenarioModal';

describe('c-add-scenario-modal', () => {
    let element;

    beforeEach(() => {
        element = createElement('c-add-scenario-modal', { is: AddScenarioModal });
        document.body.appendChild(element);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    // =========================================================================
    // Rendering
    // =========================================================================

    it('renders the modal with required fields', () => {
        return Promise.resolve().then(() => {
            const dialog = element.shadowRoot.querySelector('[role="dialog"]');
            expect(dialog).not.toBeNull();
            expect(dialog.getAttribute('aria-label')).toBe('Add Test Scenario');

            const allInputs = element.shadowRoot.querySelectorAll('lightning-input');
            expect(allInputs.length).toBeGreaterThan(0);
        });
    });

    it('renders category combobox with correct options', () => {
        return Promise.resolve().then(() => {
            const comboboxes = element.shadowRoot.querySelectorAll('lightning-combobox');
            expect(comboboxes.length).toBeGreaterThan(0);
            // First combobox is category, second is roleProfile
            const catCombo = comboboxes[0];
            expect(catCombo.options.some(o => o.value === 'Sales')).toBe(true);
            expect(catCombo.options.some(o => o.value === 'Service')).toBe(true);
            expect(catCombo.options.some(o => o.value === 'Experience')).toBe(true);
        });
    });

    // =========================================================================
    // Validation — required fields
    // =========================================================================

    it('shows developerName error when saving with empty name', () => {
        return Promise.resolve()
            .then(() => {
                const saveBtn = element.shadowRoot.querySelector('lightning-button[label="Add Scenario"]');
                saveBtn.click();
            })
            .then(() => {
                const error = element.shadowRoot.querySelector('#developerName-error');
                expect(error).not.toBeNull();
                expect(error.textContent).toContain('required');
            });
    });

    it('shows scenarioClass error when saving without Apex class', () => {
        return Promise.resolve()
            .then(() => {
                // Set developerName but leave scenarioClass blank
                setInputValue(element, '[data-field="developerName"]', 'Test_Scenario');
                const saveBtn = element.shadowRoot.querySelector('lightning-button[label="Add Scenario"]');
                saveBtn.click();
            })
            .then(() => {
                const error = element.shadowRoot.querySelector('#scenarioClass-error');
                expect(error).not.toBeNull();
                expect(error.textContent).toContain('required');
            });
    });

    it('shows changeReason error when saving without reason', () => {
        return Promise.resolve()
            .then(() => {
                setInputValue(element, '[data-field="developerName"]', 'Test_Scenario');
                setInputValue(element, '[data-field="scenarioClass"]', 'AccountCrudScenario');
                const saveBtn = element.shadowRoot.querySelector('lightning-button[label="Add Scenario"]');
                saveBtn.click();
            })
            .then(() => {
                const error = element.shadowRoot.querySelector('#changeReason-error');
                expect(error).not.toBeNull();
                expect(error.textContent).toContain('required');
            });
    });

    // =========================================================================
    // Validation — invalid formats
    // =========================================================================

    it('shows error for developerName starting with a digit', () => {
        return Promise.resolve()
            .then(() => {
                setInputValue(element, '[data-field="developerName"]', '1Invalid');
                const saveBtn = element.shadowRoot.querySelector('lightning-button[label="Add Scenario"]');
                saveBtn.click();
            })
            .then(() => {
                const error = element.shadowRoot.querySelector('#developerName-error');
                expect(error).not.toBeNull();
                expect(error.textContent).toContain('letter');
            });
    });

    it('shows error for timeout out of range', () => {
        return Promise.resolve()
            .then(() => {
                setInputValue(element, '[data-field="developerName"]', 'Valid_Name');
                setInputValue(element, '[data-field="scenarioClass"]', 'AccountCrudScenario');
                setInputValue(element, '[data-field="changeReason"]', 'reason');
                setInputValue(element, '[data-field="timeoutSec"]', '999');
                const saveBtn = element.shadowRoot.querySelector('lightning-button[label="Add Scenario"]');
                saveBtn.click();
            })
            .then(() => {
                const error = element.shadowRoot.querySelector('#timeoutSec-error');
                expect(error).not.toBeNull();
                expect(error.textContent).toContain('60');
            });
    });

    it('shows error for CPU budget out of range', () => {
        return Promise.resolve()
            .then(() => {
                setInputValue(element, '[data-field="developerName"]', 'Valid_Name');
                setInputValue(element, '[data-field="scenarioClass"]', 'AccountCrudScenario');
                setInputValue(element, '[data-field="changeReason"]', 'reason');
                setInputValue(element, '[data-field="cpuBudget"]', '99999');
                const saveBtn = element.shadowRoot.querySelector('lightning-button[label="Add Scenario"]');
                saveBtn.click();
            })
            .then(() => {
                const error = element.shadowRoot.querySelector('#cpuBudget-error');
                expect(error).not.toBeNull();
                expect(error.textContent).toContain('10,000');
            });
    });

    // =========================================================================
    // Valid submission
    // =========================================================================

    it('fires save event with correct payload when all required fields are valid', () => {
        const saveSpy = jest.fn();
        element.addEventListener('save', saveSpy);

        return Promise.resolve()
            .then(() => {
                setInputValue(element, '[data-field="developerName"]', 'New_Scenario');
                setInputValue(element, '[data-field="scenarioClass"]', 'AccountCrudScenario');
                setInputValue(element, '[data-field="changeReason"]', 'Adding for regression coverage');
                const saveBtn = element.shadowRoot.querySelector('lightning-button[label="Add Scenario"]');
                saveBtn.click();
            })
            .then(() => {
                expect(saveSpy).toHaveBeenCalledTimes(1);
                const detail = saveSpy.mock.calls[0][0].detail;
                expect(detail.developerName).toBe('New_Scenario');
                expect(detail.scenarioClass).toBe('AccountCrudScenario');
                expect(detail.changeReason).toBe('Adding for regression coverage');
            });
    });

    it('does not fire save event when validation fails', () => {
        const saveSpy = jest.fn();
        element.addEventListener('save', saveSpy);

        return Promise.resolve()
            .then(() => {
                // Leave all fields empty
                const saveBtn = element.shadowRoot.querySelector('lightning-button[label="Add Scenario"]');
                saveBtn.click();
            })
            .then(() => {
                expect(saveSpy).not.toHaveBeenCalled();
            });
    });

    // =========================================================================
    // Close
    // =========================================================================

    it('fires close event when Cancel button clicked', () => {
        const closeSpy = jest.fn();
        element.addEventListener('close', closeSpy);

        return Promise.resolve()
            .then(() => {
                const cancelBtn = element.shadowRoot.querySelector('lightning-button[label="Cancel"]');
                cancelBtn.click();
            })
            .then(() => {
                expect(closeSpy).toHaveBeenCalledTimes(1);
            });
    });

    it('fires close event when X button clicked', () => {
        const closeSpy = jest.fn();
        element.addEventListener('close', closeSpy);

        return Promise.resolve()
            .then(() => {
                const closeBtn = element.shadowRoot.querySelector('.slds-modal__close');
                closeBtn.click();
            })
            .then(() => {
                expect(closeSpy).toHaveBeenCalledTimes(1);
            });
    });

    it('fires close event when Escape key pressed', () => {
        const closeSpy = jest.fn();
        element.addEventListener('close', closeSpy);

        return Promise.resolve()
            .then(() => {
                const section = element.shadowRoot.querySelector('section[role="dialog"]');
                section.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
            })
            .then(() => {
                expect(closeSpy).toHaveBeenCalledTimes(1);
            });
    });

    // =========================================================================
    // Accessibility
    // =========================================================================

    it('required inputs have aria-required attributes', () => {
        return Promise.resolve().then(() => {
            const devNameInput = element.shadowRoot.querySelector('[data-field="developerName"]');
            expect(devNameInput.getAttribute('aria-required')).toBe('true');

            const classInput = element.shadowRoot.querySelector('[data-field="scenarioClass"]');
            expect(classInput.getAttribute('aria-required')).toBe('true');

            const reasonInput = element.shadowRoot.querySelector('[data-field="changeReason"]');
            expect(reasonInput.getAttribute('aria-required')).toBe('true');
        });
    });

    it('error messages are associated with their fields via aria-describedby', () => {
        return Promise.resolve()
            .then(() => {
                const saveBtn = element.shadowRoot.querySelector('lightning-button[label="Add Scenario"]');
                saveBtn.click();
            })
            .then(() => {
                const devNameInput = element.shadowRoot.querySelector('[data-field="developerName"]');
                const describedBy  = devNameInput.getAttribute('aria-describedby');
                expect(describedBy).toBe('developerName-error');

                const errorEl = element.shadowRoot.querySelector('#developerName-error');
                expect(errorEl).not.toBeNull();
            });
    });
});

// =========================================================================
// Helper — triggers onchange on a lightning-input
// =========================================================================
function setInputValue(element, selector, value) {
    const input = element.shadowRoot.querySelector(selector);
    if (!input) return;
    input.value = value;
    input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}
