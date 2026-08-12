import { LightningElement, track } from 'lwc';

const PROFILE_OPTIONS = [
    { label: 'Any Profile',            value: '' },
    { label: 'System Administrator',   value: 'System Administrator' },
    { label: 'Standard User',          value: 'Standard User' },
    { label: 'Minimum Access',         value: 'Minimum Access - Salesforce' }
];

const CATEGORY_OPTIONS = [
    { label: 'Sales',      value: 'Sales' },
    { label: 'Service',    value: 'Service' },
    { label: 'Experience', value: 'Experience' },
    { label: 'Automation', value: 'Automation' },
    { label: 'Integration',value: 'Integration' },
    { label: 'Reporting',  value: 'Reporting' },
    { label: 'Platform',   value: 'Platform' }
];

export default class AddScenarioModal extends LightningElement {
    profileOptions  = PROFILE_OPTIONS;
    categoryOptions = CATEGORY_OPTIONS;

    @track formData = {
        developerName:  '',
        label:          '',
        scenarioClass:  '',
        description:    '',
        businessProcess:'Sales',
        roleProfile:    '',
        timeoutSec:     null,
        cpuBudget:      null,
        soqlBudget:     null,
        dmlBudget:      null,
        isCritical:     false,
        isEnabled:      true,
        changeReason:   ''
    };

    @track errors = {};

    // =========================================================================
    // Field change handlers
    // =========================================================================

    handleFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        let value = event.detail ? event.detail.value : event.target.value;
        if (event.target && event.target.type === 'checkbox') {
            value = event.target.checked;
        }
        this.formData = { ...this.formData, [field]: value };
        // Clear error on change
        if (this.errors[field]) {
            const updated = { ...this.errors };
            delete updated[field];
            this.errors = updated;
        }
    }

    // =========================================================================
    // Validation
    // =========================================================================

    _validate() {
        const errs = {};
        const f = this.formData;

        if (!f.developerName || !f.developerName.trim()) {
            errs.developerName = 'Scenario name is required';
        } else if (!/^[a-zA-Z][a-zA-Z0-9_]{0,39}$/.test(f.developerName.trim())) {
            errs.developerName =
                'Must start with a letter, contain only letters/digits/underscores, max 40 characters';
        }

        if (!f.scenarioClass || !f.scenarioClass.trim()) {
            errs.scenarioClass = 'Apex class name is required';
        } else if (!/^[a-zA-Z][a-zA-Z0-9_]{0,255}$/.test(f.scenarioClass.trim())) {
            errs.scenarioClass = 'Apex class name is invalid';
        }

        if (!f.changeReason || !f.changeReason.trim()) {
            errs.changeReason = 'Change reason is required for audit log';
        }

        if (f.timeoutSec !== null && f.timeoutSec !== '') {
            const t = Number(f.timeoutSec);
            if (!Number.isInteger(t) || t < 1 || t > 60) {
                errs.timeoutSec = 'Timeout must be a whole number between 1 and 60 seconds';
            }
        }

        if (f.cpuBudget !== null && f.cpuBudget !== '') {
            const v = Number(f.cpuBudget);
            if (!Number.isInteger(v) || v < 1 || v > 10000) {
                errs.cpuBudget = 'CPU budget must be between 1 and 10,000 ms';
            }
        }

        if (f.soqlBudget !== null && f.soqlBudget !== '') {
            const v = Number(f.soqlBudget);
            if (!Number.isInteger(v) || v < 1 || v > 200) {
                errs.soqlBudget = 'SOQL budget must be between 1 and 200';
            }
        }

        if (f.dmlBudget !== null && f.dmlBudget !== '') {
            const v = Number(f.dmlBudget);
            if (!Number.isInteger(v) || v < 1 || v > 150) {
                errs.dmlBudget = 'DML budget must be between 1 and 150';
            }
        }

        this.errors = errs;
        return Object.keys(errs).length === 0;
    }

    // =========================================================================
    // Error getters for template
    // =========================================================================

    get developerNameError() { return this.errors.developerName; }
    get scenarioClassError()  { return this.errors.scenarioClass; }
    get changeReasonError()   { return this.errors.changeReason; }
    get timeoutSecError()     { return this.errors.timeoutSec; }
    get cpuBudgetError()      { return this.errors.cpuBudget; }
    get soqlBudgetError()     { return this.errors.soqlBudget; }
    get dmlBudgetError()      { return this.errors.dmlBudget; }

    get hasDeveloperNameError() { return !!this.errors.developerName; }
    get hasScenarioClassError() { return !!this.errors.scenarioClass; }
    get hasChangeReasonError()  { return !!this.errors.changeReason; }
    get hasTimeoutSecError()    { return !!this.errors.timeoutSec; }
    get hasCpuBudgetError()     { return !!this.errors.cpuBudget; }
    get hasSoqlBudgetError()    { return !!this.errors.soqlBudget; }
    get hasDmlBudgetError()     { return !!this.errors.dmlBudget; }

    // =========================================================================
    // Submit / cancel
    // =========================================================================

    handleSave() {
        if (!this._validate()) return;

        const payload = { ...this.formData };
        // Convert number strings to numbers for server-side validation
        if (payload.timeoutSec !== null && payload.timeoutSec !== '') {
            payload.timeoutSec = Number(payload.timeoutSec);
        } else {
            payload.timeoutSec = null;
        }
        if (payload.cpuBudget  !== null && payload.cpuBudget  !== '') payload.cpuBudget  = Number(payload.cpuBudget);
        if (payload.soqlBudget !== null && payload.soqlBudget !== '') payload.soqlBudget = Number(payload.soqlBudget);
        if (payload.dmlBudget  !== null && payload.dmlBudget  !== '') payload.dmlBudget  = Number(payload.dmlBudget);

        this.dispatchEvent(new CustomEvent('save', { detail: payload }));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleKeyDown(event) {
        if (event.key === 'Escape') {
            this.handleClose();
        }
    }
}
