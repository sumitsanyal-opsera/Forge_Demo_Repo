import { LightningElement, api } from 'lwc';

export default class StickyFooterSaveBar extends LightningElement {
    @api hasChanges = false;
    @api isSaving   = false;

    handleSave() {
        this.dispatchEvent(new CustomEvent('save'));
    }

    handleDiscard() {
        this.dispatchEvent(new CustomEvent('discard'));
    }
}
