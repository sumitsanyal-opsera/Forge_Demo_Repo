import { LightningElement, api, track } from 'lwc';

export default class CloudTemplateCard extends LightningElement {
    @api templateKey;
    @api templateName;
    @api description;
    @api scenarioCount = 0;
    @api icon = 'standard:account';

    @track _selected = false;

    @api
    get isSelected() {
        return this._selected;
    }
    set isSelected(value) {
        this._selected = value;
    }

    get cardClass() {
        return 'slds-card slds-card_boundary cloud-template-card'
            + (this._selected ? ' cloud-template-card_selected' : '');
    }

    get scenarioCountLabel() {
        return this.scenarioCount === 1
            ? '1 scenario'
            : this.scenarioCount + ' scenarios';
    }

    handleCheckboxChange(event) {
        this._selected = event.target.checked;
        this.dispatchEvent(new CustomEvent('templateselected', {
            detail: {
                key:      this.templateKey,
                selected: this._selected
            },
            bubbles:  true,
            composed: false
        }));
    }
}
