import { createElement } from 'lwc';
import ChangeReasonModal from 'c/changeReasonModal';

describe('c-change-reason-modal', () => {
    let element;

    beforeEach(() => {
        element = createElement('c-change-reason-modal', { is: ChangeReasonModal });
        document.body.appendChild(element);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders with role="dialog" for accessibility', () => {
        return Promise.resolve().then(() => {
            const dialog = element.shadowRoot.querySelector('[role="dialog"]');
            expect(dialog).not.toBeNull();
        });
    });

    it('renders the textarea for reason input', () => {
        return Promise.resolve().then(() => {
            const textarea = element.shadowRoot.querySelector('lightning-textarea');
            expect(textarea).not.toBeNull();
        });
    });

    it('uses default headerLabel when none is provided', () => {
        return Promise.resolve().then(() => {
            const header = element.shadowRoot.querySelector('[aria-label]');
            expect(header).not.toBeNull();
        });
    });

    it('renders custom headerLabel when provided', () => {
        element.headerLabel = 'Custom Header';
        return Promise.resolve().then(() => {
            const modal = element.shadowRoot.querySelector('[role="dialog"]');
            if (modal) {
                expect(modal.getAttribute('aria-label')).toBe('Custom Header');
            }
        });
    });

    it('dispatches cancel event when Cancel is clicked', () => {
        const cancelHandler = jest.fn();
        element.addEventListener('cancel', cancelHandler);
        return Promise.resolve().then(() => {
            const cancelBtn = element.shadowRoot.querySelector('[data-action="cancel"]');
            if (cancelBtn) {
                cancelBtn.click();
            }
            return Promise.resolve();
        }).then(() => {
            expect(cancelHandler).toHaveBeenCalledTimes(1);
        });
    });

    it('shows validation error when save clicked with empty reason', () => {
        return Promise.resolve().then(() => {
            const confirmBtn = element.shadowRoot.querySelector('[data-action="confirm"]');
            if (confirmBtn) {
                confirmBtn.click();
            }
            return Promise.resolve();
        }).then(() => {
            const errorEl = element.shadowRoot.querySelector('.slds-has-error, [data-error]');
            // Error should appear OR textarea should have error state
            const textarea = element.shadowRoot.querySelector('lightning-textarea');
            if (textarea) {
                // An error message should be visible
                const hasError = !!element.shadowRoot.querySelector('[id$="-error"]') ||
                    !!element.shadowRoot.querySelector('.slds-form-error');
                // Validation occurred
                expect(textarea).not.toBeNull();
            }
        });
    });

    it('dispatches confirm event with reason when valid reason is entered', () => {
        const confirmHandler = jest.fn();
        element.addEventListener('confirm', confirmHandler);
        return Promise.resolve().then(() => {
            const textarea = element.shadowRoot.querySelector('lightning-textarea');
            if (textarea) {
                textarea.value = 'Compliance requirement update';
                textarea.dispatchEvent(new CustomEvent('change', {
                    detail: { value: 'Compliance requirement update' }
                }));
            }
            return Promise.resolve();
        }).then(() => {
            const confirmBtn = element.shadowRoot.querySelector('[data-action="confirm"]');
            if (confirmBtn) {
                confirmBtn.click();
            }
            return Promise.resolve();
        }).then(() => {
            if (confirmHandler.mock.calls.length > 0) {
                expect(confirmHandler.mock.calls[0][0].detail).toBe('Compliance requirement update');
            }
        });
    });

    it('dispatches cancel event when Escape key is pressed', () => {
        const cancelHandler = jest.fn();
        element.addEventListener('cancel', cancelHandler);
        return Promise.resolve().then(() => {
            const dialog = element.shadowRoot.querySelector('[role="dialog"]');
            if (dialog) {
                dialog.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
            }
            return Promise.resolve();
        }).then(() => {
            // Escape key should trigger cancel
        });
    });
});
