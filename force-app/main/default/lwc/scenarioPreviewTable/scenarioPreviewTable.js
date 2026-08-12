import { LightningElement, api, track } from 'lwc';

export default class ScenarioPreviewTable extends LightningElement {
    @api classValidation = {};

    @track _scenarios = [];

    @api
    get scenarios() {
        return this._scenarios;
    }
    set scenarios(value) {
        this._scenarios = value ? value.map(s => ({ ...s })) : [];
    }

    get scenarioRows() {
        return this._scenarios.map(s => ({
            ...s,
            isMissingClass: this.classValidation[s.apexClassName] === false,
            warningTitle:   'Apex class ' + s.apexClassName + ' was not found in this org. '
                + 'Deploy the class before running this scenario.',
            rowKey:         s.scenarioName
        }));
    }

    get isEmpty() {
        return this._scenarios.length === 0;
    }

    handleTimeoutChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this._updateScenario(idx, 'timeout', parseInt(event.detail.value, 10));
    }

    handleCpuChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this._updateScenario(idx, 'cpuBudget', parseInt(event.detail.value, 10));
    }

    handleSoqlChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this._updateScenario(idx, 'soqlBudget', parseInt(event.detail.value, 10));
    }

    handleDmlChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this._updateScenario(idx, 'dmlBudget', parseInt(event.detail.value, 10));
    }

    _updateScenario(index, field, value) {
        const updated = [...this._scenarios];
        updated[index] = { ...updated[index], [field]: value };
        this._scenarios = updated;
        this.dispatchEvent(new CustomEvent('scenarioupdated', {
            detail: { scenarios: this._scenarios }
        }));
    }

    @api
    getScenarios() {
        return [...this._scenarios];
    }
}
