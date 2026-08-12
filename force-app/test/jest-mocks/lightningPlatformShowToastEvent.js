// Jest mock for lightning/platformShowToastEvent
export const ShowToastEventName = 'lightning__showtoast';

export class ShowToastEvent extends CustomEvent {
    constructor({ title, message, variant, mode }) {
        super(ShowToastEventName, {
            bubbles: true,
            composed: true,
            detail: { title, message, variant, mode }
        });
    }
}
