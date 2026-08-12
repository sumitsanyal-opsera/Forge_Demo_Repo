import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin }              from 'lightning/navigation';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { ShowToastEvent }              from 'lightning/platformShowToastEvent';
import checkUserPermissions            from '@salesforce/apex/SmokeTestDashboardController.checkUserPermissions';
import getLatestExecution              from '@salesforce/apex/SmokeTestDashboardController.getLatestExecution';

const PAGE_IDS = [
    'overview', 'executionDetail', 'security',
    'scenarios', 'cicd', 'alerts',
    'history', 'auditLog', 'settings'
];
const ACTIVE_CLASS  = 'slds-nav-vertical__item slds-is-active';
const DEFAULT_CLASS = 'slds-nav-vertical__item';

const PROGRESS_CHANNEL  = '/event/SmokeTestProgress__e';
const COMPLETE_CHANNEL  = '/event/SmokeTestComplete__e';
const REPLAY_ID          = -1;
const AUTO_REFRESH_MS    = 30000;
const MAX_RETRY_ATTEMPTS = 3;
const RETRY_DELAY_MS     = 5000;

export default class SmokeTestCenter extends NavigationMixin(LightningElement) {
    @track activePageId      = 'overview';
    @track progressData      = null;
    @track showFallbackWarning = false;

    _wiredPermissionResult;
    permissionData;
    permissionError;

    // undefined = not yet loaded; null = loaded, no records; object = has records
    _executionData = undefined;

    // empApi state
    _progressSubscription = null;
    _completeSubscription = null;
    _refreshTimerId       = null;
    _retryCount           = 0;

    // =========================================================================
    // Wire adapters
    // =========================================================================

    @wire(getLatestExecution)
    wiredLatestExecution({ data, error }) {
        if (data !== undefined) {
            this._executionData = data;
        } else if (error) {
            this._executionData = error;
        }
    }

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

    // =========================================================================
    // Lifecycle hooks
    // =========================================================================

    connectedCallback() {
        onError(error => this._handleEmpApiError(error));
        this._subscribeToChannels();
    }

    disconnectedCallback() {
        this._clearAutoRefresh();
        this._unsubscribeAll();
    }

    // =========================================================================
    // empApi subscription management
    // =========================================================================

    _subscribeToChannels() {
        subscribe(PROGRESS_CHANNEL, REPLAY_ID, event => this._handleProgressEvent(event))
            .then(sub  => { this._progressSubscription = sub; })
            .catch(err => this._handleSubscribeError(err));

        subscribe(COMPLETE_CHANNEL, REPLAY_ID, event => this._handleCompleteEvent(event))
            .then(sub  => { this._completeSubscription = sub; })
            .catch(err => this._handleSubscribeError(err));
    }

    _unsubscribeAll() {
        if (this._progressSubscription) {
            unsubscribe(this._progressSubscription).catch(() => {});
            this._progressSubscription = null;
        }
        if (this._completeSubscription) {
            unsubscribe(this._completeSubscription).catch(() => {});
            this._completeSubscription = null;
        }
    }

    _handleSubscribeError(error) {
        this._handleEmpApiError(error);
    }

    _handleEmpApiError(error) {
        // eslint-disable-next-line no-console
        console.error('smokeTestCenter: empApi error', error);

        if (this._retryCount < MAX_RETRY_ATTEMPTS) {
            this._retryCount++;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this._subscribeToChannels(), RETRY_DELAY_MS);
        } else {
            this.showFallbackWarning = true;
            this._startAutoRefresh();
            this.dispatchEvent(new ShowToastEvent({
                title:   'Real-time Updates Unavailable',
                message: 'Real-time updates unavailable — using periodic refresh.',
                variant: 'warning',
                mode:    'dismissible'
            }));
        }
    }

    // =========================================================================
    // Platform Event handlers
    // =========================================================================

    _handleProgressEvent(event) {
        const payload = event && event.data && event.data.payload;
        if (!payload) return;

        // Idempotent: ignore duplicate / out-of-order events
        const currentCount = this.progressData ? this.progressData.completedScenarios : -1;
        if (payload.CompletedScenarios__c <= currentCount) return;

        this.progressData = {
            executionId:        payload.ExecutionId__c,
            completedScenarios: payload.CompletedScenarios__c,
            totalScenarios:     payload.TotalScenarios__c,
            latestScenarioName: payload.LatestScenarioName__c,
            latestResult:       payload.LatestResult__c,
            elapsedMs:          payload.ElapsedMs__c
        };

        this._startAutoRefresh();
    }

    _handleCompleteEvent(event) {
        const payload = event && event.data && event.data.payload;
        if (!payload) return;

        this._clearAutoRefresh();
        this.progressData = null;

        this.dispatchEvent(new CustomEvent('refreshdashboard', {
            detail: {
                executionId:     payload.ExecutionId__c,
                overallResult:   payload.OverallResult__c,
                totalDurationMs: payload.TotalDurationMs__c
            },
            bubbles:  true,
            composed: true
        }));
    }

    // =========================================================================
    // Auto-refresh timer
    // =========================================================================

    _startAutoRefresh() {
        if (this._refreshTimerId) return; // already running
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._refreshTimerId = setInterval(() => {
            this.dispatchEvent(new CustomEvent('refreshdashboard', {
                bubbles: true, composed: true
            }));
        }, AUTO_REFRESH_MS);
    }

    _clearAutoRefresh() {
        if (this._refreshTimerId) {
            clearInterval(this._refreshTimerId);
            this._refreshTimerId = null;
        }
    }

    // =========================================================================
    // Getters
    // =========================================================================

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

    // Show onboarding only when we have access AND execution wire resolved to null
    get showOnboarding() {
        return this.hasAccess && this._executionData === null;
    }

    get isScenariosPage() {
        return this.activePageId === 'scenarios';
    }

    get isSettingsPage() {
        return this.activePageId === 'settings';
    }

    get navItemClass() {
        const classes = {};
        PAGE_IDS.forEach(pageId => {
            classes[pageId] = this.activePageId === pageId ? ACTIVE_CLASS : DEFAULT_CLASS;
        });
        return classes;
    }

    get progressLabel() {
        if (!this.progressData) return '';
        return `In Progress: ${this.progressData.completedScenarios} of ${this.progressData.totalScenarios} scenarios complete`;
    }

    // =========================================================================
    // Event handlers
    // =========================================================================

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
            .then(data   => { this.permissionData  = data; })
            .catch(error => { this.permissionError = error; });
    }

    handleManualRefresh() {
        this.dispatchEvent(new CustomEvent('refreshdashboard', {
            bubbles: true, composed: true
        }));
    }
}
