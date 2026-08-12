import { LightningElement, api, track } from 'lwc';

export default class ChangeReasonModal extends LightningElement {
    @api headerLabel = 'Change Reason Required';
    @api bodyText    = 'Please provide a reason for this configuration change.';

    @track reason    = '';
    @track hasError  = false;

    get errorMessage() {
        return this.hasError ? 'Change reason is required' : '';
    }

    handleReasonChange(event) {
        this.reason   = event.target.value;
        this.hasError = false;
    }

    handleSave() {
        if (!this.reason || !this.reason.trim()) {
            this.hasError = true;
            return;
        }
        this.dispatchEvent(new CustomEvent('confirm', { detail: this.reason.trim() }));
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') {
            this.handleCancel();
        }
    }
}
