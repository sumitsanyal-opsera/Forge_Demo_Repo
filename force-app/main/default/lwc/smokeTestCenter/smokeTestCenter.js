import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import checkUserPermissions from '@salesforce/apex/SmokeTestDashboardController.checkUserPermissions';

const PAGE_IDS = [
    'overview', 'executionDetail', 'security',
    'scenarios', 'cicd', 'alerts',
    'history', 'auditLog'
];
const ACTIVE_CLASS  = 'slds-nav-vertical__item slds-is-active';
const DEFAULT_CLASS = 'slds-nav-vertical__item';

export default class SmokeTestCenter extends NavigationMixin(LightningElement) {
    @track activePageId = 'overview';

    _wiredPermissionResult;
    permissionData;
    permissionError;

    @wire(checkUserPermissions)
    wiredPermissions(result) {
        this._wiredPermissionResult = result;
        const { error, data } = result;
        if (data) {
            this.permissionData  = data;
            this.permissionError = undefined;
        } else if (error) {
            this.permissionError = error;
            this.permissionData  = undefined;
        }
    }

    get isLoading() {
        return !this.permissionData && !this.permissionError;
    }

    get hasError() {
        return !!this.permissionError;
    }

    get errorMessage() {
        if (!this.permissionError) return null;
        return (this.permissionError.body && this.permissionError.body.message)
            ? this.permissionError.body.message
            : 'Unable to verify permissions. Please check your connection and try again.';
    }

    get isAccessDenied() {
        return !!(this.permissionData && this.permissionData.permissionLevel === 'none');
    }

    get hasAccess() {
        return !!(this.permissionData && this.permissionData.permissionLevel !== 'none');
    }

    get isAdmin() {
        return !!(this.permissionData && this.permissionData.isAdmin);
    }

    get navItemClass() {
        const classes = {};
        PAGE_IDS.forEach(pageId => {
            classes[pageId] = this.activePageId === pageId ? ACTIVE_CLASS : DEFAULT_CLASS;
        });
        return classes;
    }

    handleNavClick(event) {
        event.preventDefault();
        const pageId = event.currentTarget.dataset.pageId;
        if (!pageId) return;
        this.activePageId = pageId;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: pageId }
        });
    }

    handleRetry() {
        this.permissionData  = undefined;
        this.permissionError = undefined;
        checkUserPermissions()
            .then(data  => { this.permissionData  = data; })
            .catch(error => { this.permissionError = error; });
    }
}
