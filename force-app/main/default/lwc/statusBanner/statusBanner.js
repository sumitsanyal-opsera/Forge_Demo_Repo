import { LightningElement, wire } from 'lwc';
import getLatestExecution from '@salesforce/apex/SmokeTestDashboardController.getLatestExecution';

const STATUS_IN_PROGRESS = new Set(['Queued', 'In Progress']);
const STATUS_FAIL        = new Set(['Failed', 'Aborted']);

const RESULT_FAIL        = new Set(['Fail', 'Partial']);

const ICON_PASS        = 'utility:success';
const ICON_FAIL        = 'utility:error';
const ICON_IN_PROGRESS = 'utility:spinner';

const CLASS_BASE        = 'slds-notify slds-notify_alert';
const CLASS_PASS        = CLASS_BASE + ' slds-alert_success';
const CLASS_FAIL        = CLASS_BASE + ' slds-alert_error';
const CLASS_IN_PROGRESS = CLASS_BASE + ' slds-alert_offline';

const SLO_WARNING_MS = 600000; // 10 minutes

export default class StatusBanner extends LightningElement {
    _wiredResult;
    execution;
    loadError;

    @wire(getLatestExecution)
    wiredExecution(result) {
        this._wiredResult = result;
        const { data, error } = result;
        if (data !== undefined) {
            this.execution = data;    // null means no records exist
            this.loadError = undefined;
            if (error) {
                this.dispatchEvent(new CustomEvent('loaderror', { detail: error, bubbles: true }));
            }
        } else if (error) {
            this.loadError  = error;
            this.execution  = undefined;
            this.dispatchEvent(new CustomEvent('loaderror', { detail: error, bubbles: true }));
        }
    }

    // =========================================================================
    // Visibility guards
    // =========================================================================

    get hasData() {
        return this.execution != null;
    }

    get hasError() {
        return !!this.loadError;
    }

    // =========================================================================
    // Status derivation
    // =========================================================================

    get _derivedStatus() {
        if (!this.execution) return 'unknown';
        const status = this.execution.Status__c;
        if (STATUS_IN_PROGRESS.has(status)) return 'inprogress';
        if (STATUS_FAIL.has(status))        return 'fail';
        // Completed — inspect OverallResult__c
        const result = this.execution.OverallResult__c;
        if (result === 'Pass') return 'pass';
        if (RESULT_FAIL.has(result)) return 'fail';
        return 'unknown';
    }

    get statusLabel() {
        const s = this._derivedStatus;
        if (s === 'pass')       return 'Pass';
        if (s === 'fail')       return 'Fail';
        if (s === 'inprogress') return 'In Progress';
        return 'Unknown';
    }

    get iconName() {
        const s = this._derivedStatus;
        if (s === 'pass')       return ICON_PASS;
        if (s === 'fail')       return ICON_FAIL;
        return ICON_IN_PROGRESS;
    }

    get bannerClass() {
        const s = this._derivedStatus;
        if (s === 'pass')       return CLASS_PASS;
        if (s === 'fail')       return CLASS_FAIL;
        return CLASS_IN_PROGRESS;
    }

    // =========================================================================
    // Display fields
    // =========================================================================

    get triggeredBy() {
        if (!this.execution) return null;
        const name = this.execution.InitiatedBy__r && this.execution.InitiatedBy__r.Name;
        if (name) return name;
        return this.execution.TriggerSource__c || 'System';
    }

    get formattedStartTime() {
        return this.execution && this.execution.StartTime__c
            ? this.execution.StartTime__c
            : null;
    }

    get formattedDuration() {
        if (!this.execution) return null;
        const ms = this.execution.ExecutionTimeMs__c;
        if (ms != null) {
            return this._formatMs(ms);
        }
        // In-progress: compute elapsed from StartTime to now
        if (this.execution.StartTime__c) {
            const elapsed = Date.now() - new Date(this.execution.StartTime__c).getTime();
            return this._formatMs(elapsed);
        }
        return null;
    }

    get durationClass() {
        const ms = this.execution && this.execution.ExecutionTimeMs__c;
        return ms != null && ms > SLO_WARNING_MS ? 'duration-warning' : '';
    }

    get totalScenarios() {
        return this.execution ? this.execution.TotalScenarios__c : null;
    }

    get passedScenarios() {
        return this.execution ? this.execution.PassedScenarios__c : null;
    }

    get failedScenarios() {
        const count = this.execution ? this.execution.FailedScenarios__c : null;
        return count && count > 0 ? count : null;
    }

    // =========================================================================
    // Event handlers
    // =========================================================================

    handleRetry() {
        this.loadError = undefined;
        this.execution = undefined;
        getLatestExecution()
            .then(data  => { this.execution = data; })
            .catch(err  => { this.loadError = err; });
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    _formatMs(ms) {
        if (ms == null || ms <= 0) return '0s';
        const totalSecs = Math.floor(ms / 1000);
        const mins      = Math.floor(totalSecs / 60);
        const secs      = totalSecs % 60;
        if (mins === 0) return `${secs}s`;
        return `${mins}m ${secs}s`;
    }
}
