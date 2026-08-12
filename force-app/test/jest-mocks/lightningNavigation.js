// Jest mock for lightning/navigation
import { LightningElement } from 'lwc';

const CurrentPageReference = jest.fn();

const Navigate = Symbol('Navigate');
const GenerateUrl = Symbol('GenerateUrl');

function NavigationMixin(Base) {
    return class extends Base {
        [Navigate](pageReference, replace) {
            this[NavigationMixin.Navigate](pageReference, replace);
        }
        [GenerateUrl](pageReference) {
            return this[NavigationMixin.GenerateUrl](pageReference);
        }
    };
}

NavigationMixin.Navigate = Navigate;
NavigationMixin.GenerateUrl = GenerateUrl;

export { NavigationMixin, CurrentPageReference };
