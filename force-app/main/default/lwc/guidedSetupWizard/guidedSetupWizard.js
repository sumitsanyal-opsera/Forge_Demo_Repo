import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSalesCloudTemplates
    from '@salesforce/apex/ScenarioTemplateService.getSalesCloudTemplates';
import getServiceCloudTemplates
    from '@salesforce/apex/ScenarioTemplateService.getServiceCloudTemplates';
import getExperienceCloudTemplates
    from '@salesforce/apex/ScenarioTemplateService.getExperienceCloudTemplates';
import validateApexClasses
    from '@salesforce/apex/ScenarioTemplateService.validateApexClasses';
import bulkDeployTemplates
    from '@salesforce/apex/ScenarioTemplateService.bulkDeployTemplates';

const STEP_SELECT   = 1;
const STEP_PREVIEW  = 2;
const STEP_DEPLOY   = 3;

const CLOUD_CONFIGS = [
    { key: 'sales',      icon: 'standard:account',          label: 'Sales Cloud' },
    { key: 'service',    icon: 'standard:case',              label: 'Service Cloud' },
    { key: 'experience', icon: 'standard:experience_cloud',  label: 'Experience Cloud' }
];

export default class GuidedSetupWizard extends LightningElement {
    @track currentStep       = STEP_SELECT;
    @track selectedKeys      = new Set();
    @track allTemplates      = {};        // key → List<ScenarioTemplate>
    @track scenariosToPreview = [];
    @track classValidation   = {};
    @track isLoading         = false;
    @track deployResult      = null;

    // =========================================================================
    // Wire adapters for template data
    // =========================================================================

    @wire(getSalesCloudTemplates)
    wiredSales({ data }) {
        if (data) this.allTemplates = { ...this.allTemplates, sales: data };
    }

    @wire(getServiceCloudTemplates)
    wiredService({ data }) {
        if (data) this.allTemplates = { ...this.allTemplates, service: data };
    }

    @wire(getExperienceCloudTemplates)
    wiredExperience({ data }) {
        if (data) this.allTemplates = { ...this.allTemplates, experience: data };
    }

    // =========================================================================
    // Computed properties
    // =========================================================================

    get cloudCards() {
        return CLOUD_CONFIGS.map(cfg => ({
            ...cfg,
            isSelected:    this.selectedKeys.has(cfg.key),
            scenarioCount: (this.allTemplates[cfg.key] || []).length
        }));
    }

    get isStep1() { return this.currentStep === STEP_SELECT; }
    get isStep2() { return this.currentStep === STEP_PREVIEW; }
    get isStep3() { return this.currentStep === STEP_DEPLOY; }

    get step1Class() {
        return 'slds-path__item'
            + (this.currentStep === STEP_SELECT  ? ' slds-is-current slds-is-active' :
               this.currentStep >  STEP_SELECT   ? ' slds-is-complete' : '');
    }
    get step2Class() {
        return 'slds-path__item'
            + (this.currentStep === STEP_PREVIEW ? ' slds-is-current slds-is-active' :
               this.currentStep >  STEP_PREVIEW  ? ' slds-is-complete' : '');
    }
    get step3Class() {
        return 'slds-path__item'
            + (this.currentStep === STEP_DEPLOY  ? ' slds-is-current slds-is-active' : '');
    }

    get canGoNext() {
        return this.selectedKeys.size > 0;
    }

    get isNextDisabled() {
        return this.selectedKeys.size === 0;
    }

    get deployButtonDisabled() {
        return this.isLoading || this.scenariosToPreview.length === 0;
    }

    get hasWarnings() {
        return Object.values(this.classValidation).some(v => v === false);
    }

    get missingClasses() {
        return Object.keys(this.classValidation).filter(k => this.classValidation[k] === false);
    }

    get deploySuccess() {
        return this.deployResult && this.deployResult.success;
    }

    get deployedCount() {
        return this.deployResult ? this.deployResult.deployedCount : 0;
    }

    get skippedCount() {
        return this.deployResult && this.deployResult.skippedNames
            ? this.deployResult.skippedNames.length : 0;
    }

    get successMessage() {
        if (!this.deployResult) return '';
        const parts = [];
        parts.push(this.deployedCount + ' scenario(s) queued for deployment.');
        if (this.skippedCount > 0) {
            parts.push(this.skippedCount + ' scenario(s) skipped (already exist).');
        }
        if (this.deployResult.warningClassNames &&
                this.deployResult.warningClassNames.length > 0) {
            parts.push('Warning: ' + this.deployResult.warningClassNames.length
                + ' Apex class(es) not found in org — deploy the missing classes and re-run scenarios.');
        }
        return parts.join(' ');
    }

    // =========================================================================
    // Step 1: template selection
    // =========================================================================

    handleTemplateSelected(event) {
        const { key, selected } = event.detail;
        const updated = new Set(this.selectedKeys);
        if (selected) {
            updated.add(key);
        } else {
            updated.delete(key);
        }
        this.selectedKeys = updated;
    }

    // =========================================================================
    // Navigation
    // =========================================================================

    handleNext() {
        if (this.currentStep === STEP_SELECT) {
            this._buildPreview();
            this.currentStep = STEP_PREVIEW;
        }
    }

    handleBack() {
        if (this.currentStep === STEP_PREVIEW) {
            this.currentStep = STEP_SELECT;
        }
    }

    handleDeploy() {
        this.isLoading = true;
        const scenarios = this.scenariosToPreview;

        bulkDeployTemplates({ scenarios })
            .then(result => {
                this.deployResult = result;
                this.currentStep  = STEP_DEPLOY;
                if (result.success) {
                    this.dispatchEvent(new ShowToastEvent({
                        title:   'Deployment Queued',
                        message: this.deployedCount + ' scenario(s) queued. '
                            + 'Changes apply after metadata refresh.',
                        variant: 'success'
                    }));
                    this.dispatchEvent(new CustomEvent('wizardcomplete', {
                        detail:   { deployedCount: result.deployedCount },
                        bubbles:  true,
                        composed: true
                    }));
                } else {
                    this.dispatchEvent(new ShowToastEvent({
                        title:   'Deployment Failed',
                        message: result.errorMessage || 'An error occurred during deployment.',
                        variant: 'error',
                        mode:    'sticky'
                    }));
                }
            })
            .catch(error => {
                this.deployResult = { success: false, errorMessage: this._extractMessage(error) };
                this.currentStep  = STEP_DEPLOY;
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Deployment Error',
                    message: this._extractMessage(error),
                    variant: 'error',
                    mode:    'sticky'
                }));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('wizardcancel', { bubbles: true, composed: true }));
    }

    handleDone() {
        this.dispatchEvent(new CustomEvent('wizardcomplete', {
            detail:   { deployedCount: this.deployedCount },
            bubbles:  true,
            composed: true
        }));
    }

    handleRetry() {
        this.currentStep  = STEP_PREVIEW;
        this.deployResult = null;
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    _buildPreview() {
        const seen    = new Set();
        const result  = [];
        const classes = [];

        for (const key of this.selectedKeys) {
            const templates = this.allTemplates[key] || [];
            for (const t of templates) {
                if (!seen.has(t.scenarioName)) {
                    seen.add(t.scenarioName);
                    result.push({ ...t });
                    classes.push(t.apexClassName);
                }
            }
        }
        result.sort((a, b) => (a.executionOrder || 0) - (b.executionOrder || 0));
        this.scenariosToPreview = result;

        // Validate class existence
        if (classes.length > 0) {
            validateApexClasses({ classNames: classes })
                .then(validation => { this.classValidation = validation || {}; })
                .catch(() => { this.classValidation = {}; });
        }
    }

    _extractMessage(error) {
        if (!error) return 'An unexpected error occurred';
        if (typeof error === 'string') return error;
        if (error.body && error.body.message) return error.body.message;
        if (error.message) return error.message;
        return JSON.stringify(error);
    }
}
