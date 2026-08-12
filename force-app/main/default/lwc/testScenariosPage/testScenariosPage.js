import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getScenarios from '@salesforce/apex/SmokeTestScenarioController.getScenarios';
import toggleScenario from '@salesforce/apex/SmokeTestScenarioController.toggleScenario';
import createScenario from '@salesforce/apex/SmokeTestScenarioController.createScenario';

const CATEGORY_OPTIONS = [
    { label: 'All',        value: 'All' },
    { label: 'Sales',      value: 'Sales' },
    { label: 'Service',    value: 'Service' },
    { label: 'Experience', value: 'Experience' }
];

const STATUS_OPTIONS = [
    { label: 'All',      value: 'All' },
    { label: 'Enabled',  value: 'Enabled' },
    { label: 'Disabled', value: 'Disabled' }
];

export default class TestScenariosPage extends LightningElement {
    @api isAdmin = false;

    // Raw data from wire
    _scenarios = [];
    wireError;

    // Filter state
    @track searchText    = '';
    @track categoryFilter = 'All';
    @track statusFilter   = 'All';

    // UI state
    @track isLoading      = false;
    @track showModal      = false;
    @track showWizard     = false;
    @track togglingIds    = new Set();

    categoryOptions = CATEGORY_OPTIONS;
    statusOptions   = STATUS_OPTIONS;

    @wire(getScenarios)
    wiredScenarios({ data, error }) {
        if (data) {
            this._scenarios = data;
            this.wireError  = undefined;
        } else if (error) {
            this._scenarios = [];
            this.wireError  = this._extractMessage(error);
        }
    }

    // =========================================================================
    // Computed properties
    // =========================================================================

    get hasPermissionError() {
        return !this.isAdmin;
    }

    get filteredScenarios() {
        return this._scenarios.filter(s => {
            const matchesText = !this.searchText ||
                (s.label || s.developerName || '')
                    .toLowerCase()
                    .includes(this.searchText.toLowerCase());

            const matchesCategory = this.categoryFilter === 'All' ||
                (s.businessProcess || '').includes(this.categoryFilter);

            const matchesStatus = this.statusFilter === 'All' ||
                (this.statusFilter === 'Enabled'  &&  s.isEnabled) ||
                (this.statusFilter === 'Disabled' && !s.isEnabled);

            return matchesText && matchesCategory && matchesStatus;
        });
    }

    get totalCount() {
        return this._scenarios.length;
    }

    get enabledCount() {
        return this._scenarios.filter(s => s.isEnabled).length;
    }

    get disabledCount() {
        return this._scenarios.filter(s => !s.isEnabled).length;
    }

    get hasWireError() {
        return !!this.wireError;
    }

    get hasScenarios() {
        return this.filteredScenarios.length > 0;
    }

    get isEmpty() {
        return this._scenarios.length === 0 && !this.wireError;
    }

    // Annotate each scenario with UI-state fields for the template
    get scenarioRows() {
        return this.filteredScenarios.map(s => ({
            ...s,
            isToggling:     this.togglingIds.has(s.developerName),
            enabledLabel:   s.isEnabled ? 'Enabled' : 'Disabled',
            enabledVariant: s.isEnabled ? 'success' : 'warning',
            criticalIcon:   s.isCritical ? 'utility:error' : 'utility:info',
            criticalLabel:  s.isCritical ? 'Critical' : 'Non-critical',
            timeoutDisplay: s.timeoutSec ? s.timeoutSec + 's' : 'Default',
            rowKey:         s.developerName
        }));
    }

    // =========================================================================
    // Filter handlers
    // =========================================================================

    handleSearchChange(event) {
        this.searchText = event.target.value;
    }

    handleCategoryChange(event) {
        this.categoryFilter = event.detail.value;
    }

    handleStatusChange(event) {
        this.statusFilter = event.detail.value;
    }

    // =========================================================================
    // Toggle enable / disable
    // =========================================================================

    handleToggle(event) {
        const developerName = event.currentTarget.dataset.developerName;
        const scenario = this._scenarios.find(s => s.developerName === developerName);
        if (!scenario || this.togglingIds.has(developerName)) return;

        const newEnabled = !scenario.isEnabled;
        this._promptToggle(developerName, newEnabled);
    }

    _promptToggle(developerName, newEnabled) {
        const changeReason = newEnabled
            ? 'Enabled via Test Scenarios configuration page'
            : 'Disabled via Test Scenarios configuration page';

        this._markToggling(developerName, true);

        toggleScenario({ developerName, enabled: newEnabled, changeReason })
            .then(() => {
                this._updateLocalEnabled(developerName, newEnabled);
                this._showToast(
                    'Success',
                    `Scenario ${developerName} ${newEnabled ? 'enabled' : 'disabled'}. ` +
                    'Deployment queued — changes apply after metadata refresh.',
                    'success'
                );
            })
            .catch(error => {
                this._showToast('Error', this._extractMessage(error), 'error');
            })
            .finally(() => {
                this._markToggling(developerName, false);
            });
    }

    _markToggling(developerName, toggling) {
        const updated = new Set(this.togglingIds);
        if (toggling) {
            updated.add(developerName);
        } else {
            updated.delete(developerName);
        }
        this.togglingIds = updated;
    }

    _updateLocalEnabled(developerName, enabled) {
        this._scenarios = this._scenarios.map(s =>
            s.developerName === developerName ? { ...s, isEnabled: enabled } : s
        );
    }

    // =========================================================================
    // Add scenario modal
    // =========================================================================

    handleAddClick() {
        this.showModal = true;
    }

    handleModalClose() {
        this.showModal = false;
    }

    // =========================================================================
    // Guided Setup Wizard
    // =========================================================================

    handleAddFromTemplates() {
        this.showWizard = true;
    }

    handleWizardComplete() {
        this.showWizard = false;
        // Refresh scenarios after wizard deployment
        getScenarios()
            .then(data => { if (data) this._scenarios = data; })
            .catch(() => {});
    }

    handleWizardCancel() {
        this.showWizard = false;
    }

    handleModalSave(event) {
        const params = event.detail;
        this.isLoading = true;

        createScenario({ params })
            .then(result => {
                this.showModal = false;
                this._showToast(
                    'Success',
                    `Scenario "${params.developerName}" queued for deployment (Job: ${result.jobId}).`,
                    'success'
                );
                // Refresh wire to pick up newly created MDT after deployment completes
                return getScenarios();
            })
            .then(data => {
                if (data) this._scenarios = data;
            })
            .catch(error => {
                this._showToast('Error', this._extractMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

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
