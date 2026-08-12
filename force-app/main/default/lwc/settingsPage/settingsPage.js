import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSettings from '@salesforce/apex/SettingsController.getSettings';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';

const ROLLBACK_OPTIONS = [
    { label: 'Recommend Only',                   value: 'Recommend Only' },
    { label: 'Auto-Rollback on Critical Failure', value: 'Auto-Rollback on Critical Failure' },
    { label: 'Manual Approval Required',          value: 'Manual Approval Required' }
];

export default class SettingsPage extends LightningElement {
    @api isAdmin = false;

    // Wire adapter result
    _wireError;
    @track isLoading = false;

    // Settings values
    @track currentValues = {};
    originalValues       = {};

    // Rollback policy modal
    @track showChangeReasonModal      = false;
    @track pendingRollbackPolicy      = null;
    @track previousRollbackPolicy     = null;

    // Save state
    @track fieldErrors = {};

    rollbackOptions = ROLLBACK_OPTIONS;

    @wire(getSettings)
    wiredSettings({ data, error }) {
        if (data) {
            this.originalValues = { ...data };
            this.currentValues  = { ...data };
            this._wireError     = undefined;
        } else if (error) {
            this._wireError = this._extractMessage(error);
        }
    }

    // =========================================================================
    // Computed properties
    // =========================================================================

    get hasPermissionError() {
        return !this.isAdmin;
    }

    get hasWireError() {
        return !!this._wireError;
    }

    get wireErrorMessage() {
        return this._wireError;
    }

    get hasChanges() {
        return JSON.stringify(this.currentValues) !== JSON.stringify(this.originalValues);
    }

    // Execution settings
    get suiteTimeoutSec()         { return this.currentValues.SuiteTimeoutSec__c; }
    get scenarioTimeoutSec()      { return this.currentValues.PerScenarioTimeoutSec__c; }
    get cpuBudgetMs()             { return this.currentValues.GovernorBudgetCPUMs__c; }
    get soqlBudget()              { return this.currentValues.GovernorBudgetSOQL__c; }
    get dmlBudget()               { return this.currentValues.GovernorBudgetDML__c; }
    get circuitBreakerThreshold() { return this.currentValues.CircuitBreakerThreshold__c; }

    // Security
    get securityMinThreshold()   { return this.currentValues.SecurityScoreAbsoluteThreshold__c; }
    get securityMaxDrop()        { return this.currentValues.SecurityScoreRelativeThreshold__c; }
    get securityEnabled()        { return this.currentValues.SecurityHealthCheckEnabled__c; }

    // Rollback
    get rollbackPolicy()         { return this.currentValues.DefaultRollbackPolicy__c; }
    get dryRunMode()             { return this.currentValues.DryRunMode__c; }

    // Execution mode
    get shadowMode()             { return this.currentValues.ShadowMode__c; }
    get autoTrigger()            { return this.currentValues.AutoTriggerEnabled__c; }

    // Data retention
    get retentionDetailLogs()      { return this.currentValues.DataRetentionDaysInternal__c; }
    get retentionResultSummaries() { return this.currentValues.DataRetentionDaysConfidential__c; }
    get retentionSecurityScores()  { return this.currentValues.DataRetentionDaysSecurityScores__c; }
    get retentionAuditLogs()       { return this.currentValues.DataRetentionDaysAuditLogs__c; }

    // Field-level error getters
    get suiteTimeoutError()         { return this.fieldErrors.SuiteTimeoutSec__c; }
    get scenarioTimeoutError()      { return this.fieldErrors.PerScenarioTimeoutSec__c; }
    get cpuBudgetError()            { return this.fieldErrors.GovernorBudgetCPUMs__c; }
    get soqlBudgetError()           { return this.fieldErrors.GovernorBudgetSOQL__c; }
    get dmlBudgetError()            { return this.fieldErrors.GovernorBudgetDML__c; }
    get circuitBreakerError()       { return this.fieldErrors.CircuitBreakerThreshold__c; }
    get securityMinThresholdError() { return this.fieldErrors.SecurityScoreAbsoluteThreshold__c; }
    get securityMaxDropError()      { return this.fieldErrors.SecurityScoreRelativeThreshold__c; }
    get rollbackPolicyError()       { return this.fieldErrors.DefaultRollbackPolicy__c; }
    get retentionDetailLogsError()  { return this.fieldErrors.DataRetentionDaysInternal__c; }
    get retentionSummariesError()   { return this.fieldErrors.DataRetentionDaysConfidential__c; }
    get retentionScoresError()      { return this.fieldErrors.DataRetentionDaysSecurityScores__c; }
    get retentionAuditLogsError()   { return this.fieldErrors.DataRetentionDaysAuditLogs__c; }

    // Audit log retention compliance warning
    get auditLogRetentionInvalid() {
        const val = Number(this.retentionAuditLogs);
        return !isNaN(val) && val > 0 && val < 365;
    }

    // =========================================================================
    // Field change handlers
    // =========================================================================

    handleNumberChange(event) {
        const field = event.currentTarget.dataset.field;
        const val   = event.detail ? event.detail.value : event.target.value;
        this._updateField(field, val === '' || val === null ? null : Number(val));
    }

    handleToggleChange(event) {
        const field   = event.currentTarget.dataset.field;
        const checked = event.target.checked;
        this._updateField(field, checked);
    }

    handleRollbackPolicyChange(event) {
        const newPolicy = event.detail.value;
        const current   = this.currentValues.DefaultRollbackPolicy__c;
        if (newPolicy === current) return;

        // Rollback policy change requires change reason modal
        this.previousRollbackPolicy  = current;
        this.pendingRollbackPolicy   = newPolicy;
        this.showChangeReasonModal   = true;
    }

    handleChangeReasonConfirm(event) {
        const reason = event.detail;
        this._updateField('DefaultRollbackPolicy__c', this.pendingRollbackPolicy);
        this._pendingChangeReason    = reason;
        this.showChangeReasonModal   = false;
        this.pendingRollbackPolicy   = null;
        this.previousRollbackPolicy  = null;
    }

    handleChangeReasonCancel() {
        // Revert to previous value
        this.showChangeReasonModal  = false;
        this.pendingRollbackPolicy  = null;
        this.previousRollbackPolicy = null;
        // Re-render to reset radio selection (force reactivity)
        this.currentValues = { ...this.currentValues };
    }

    _updateField(field, value) {
        this.currentValues = { ...this.currentValues, [field]: value };
        // Clear error for this field
        if (this.fieldErrors[field]) {
            const updated = { ...this.fieldErrors };
            delete updated[field];
            this.fieldErrors = updated;
        }
    }

    // =========================================================================
    // Save / Discard
    // =========================================================================

    handleSave() {
        const changedFields = this._computeChangedFields();
        if (Object.keys(changedFields).length === 0) {
            this._showToast('Info', 'No changes to save', 'info');
            return;
        }

        this.isLoading = true;
        const changeReason = this._pendingChangeReason || '';

        saveSettings({ changedFields, changeReason })
            .then(result => {
                this.originalValues       = { ...this.currentValues };
                this.fieldErrors          = {};
                this._pendingChangeReason = null;
                this._showToast(
                    'Success',
                    `Settings saved successfully (Job: ${result.jobId}). Changes apply after metadata refresh.`,
                    'success'
                );
            })
            .catch(error => {
                const msg = this._extractMessage(error);
                // Try to parse field-specific errors from JSON
                try {
                    const parsed = JSON.parse(msg);
                    if (typeof parsed === 'object') {
                        this.fieldErrors = parsed;
                        this._showToast('Validation Error',
                            'Some fields have validation errors — see highlighted inputs.', 'error');
                        return;
                    }
                } catch (_) { /* not JSON, fall through */ }
                this._showToast('Error', msg, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleDiscard() {
        this.currentValues        = { ...this.originalValues };
        this.fieldErrors          = {};
        this._pendingChangeReason = null;
        this._showToast('Info', 'Changes discarded', 'info');
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    _computeChangedFields() {
        const changed = {};
        for (const key of Object.keys(this.currentValues)) {
            if (this.currentValues[key] !== this.originalValues[key]) {
                changed[key] = this.currentValues[key];
            }
        }
        return changed;
    }

    _showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _extractMessage(error) {
        if (!error) return 'An unexpected error occurred';
        if (typeof error === 'string') return error;
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return JSON.stringify(error);
    }
}
