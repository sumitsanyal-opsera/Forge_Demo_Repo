import { createElement } from 'lwc';
import { registerApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import GuidedSetupWizard from 'c/guidedSetupWizard';

import getSalesCloudTemplates
    from '@salesforce/apex/ScenarioTemplateService.getSalesCloudTemplates';
import getServiceCloudTemplates
    from '@salesforce/apex/ScenarioTemplateService.getServiceCloudTemplates';
import getExperienceCloudTemplates
    from '@salesforce/apex/ScenarioTemplateService.getExperienceCloudTemplates';

import mockSalesTemplates from './data/salesTemplates.json';
import mockDeployResult   from './data/deployResult.json';

const getSalesAdapter       = registerApexTestWireAdapter(getSalesCloudTemplates);
const getServiceAdapter     = registerApexTestWireAdapter(getServiceCloudTemplates);
const getExperienceAdapter  = registerApexTestWireAdapter(getExperienceCloudTemplates);

jest.mock(
    '@salesforce/apex/ScenarioTemplateService.validateApexClasses',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/ScenarioTemplateService.bulkDeployTemplates',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

import validateApexClasses
    from '@salesforce/apex/ScenarioTemplateService.validateApexClasses';
import bulkDeployTemplates
    from '@salesforce/apex/ScenarioTemplateService.bulkDeployTemplates';

const flushPromises = () => new Promise(resolve => setTimeout(resolve, 0));

function createComponent() {
    const el = createElement('c-guided-setup-wizard', { is: GuidedSetupWizard });
    document.body.appendChild(el);
    return el;
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
});

// =============================================================================
// Step 1: default render
// =============================================================================

describe('Step 1 — template selection', () => {
    it('renders step 1 by default', () => {
        const el = createComponent();
        const step1 = el.shadowRoot.querySelector('[data-step="1"]');
        expect(step1).not.toBeNull();
    });

    it('does not render step 2 on initial load', () => {
        const el = createComponent();
        const step2 = el.shadowRoot.querySelector('[data-step="2"]');
        expect(step2).toBeNull();
    });

    it('shows three cloud template cards after wire data loads', async () => {
        const el = createComponent();
        getSalesAdapter.emit(mockSalesTemplates);
        getServiceAdapter.emit([]);
        getExperienceAdapter.emit([]);
        await flushPromises();
        const cards = el.shadowRoot.querySelectorAll('c-cloud-template-card');
        expect(cards.length).toBe(3);
    });

    it('Next button is disabled when no templates selected', async () => {
        const el = createComponent();
        getSalesAdapter.emit(mockSalesTemplates);
        await flushPromises();
        const nextBtn = el.shadowRoot.querySelector('[data-id="next-btn"]');
        expect(nextBtn).not.toBeNull();
        // canGoNext = false → attribute disabled
        expect(nextBtn.disabled).toBe(true);
    });

    it('Next button is enabled after selecting a template', async () => {
        const el = createComponent();
        getSalesAdapter.emit(mockSalesTemplates);
        await flushPromises();

        // Simulate templateselected event from cloudTemplateCard
        const card = el.shadowRoot.querySelector('c-cloud-template-card');
        card.dispatchEvent(new CustomEvent('templateselected', {
            detail: { key: 'sales', selected: true }
        }));
        await flushPromises();

        const nextBtn = el.shadowRoot.querySelector('[data-id="next-btn"]');
        expect(nextBtn.disabled).toBe(false);
    });
});

// =============================================================================
// Step 2: preview
// =============================================================================

describe('Step 2 — preview and customize', () => {
    async function advanceToStep2(el) {
        getSalesAdapter.emit(mockSalesTemplates);
        getServiceAdapter.emit([]);
        getExperienceAdapter.emit([]);
        await flushPromises();

        const card = el.shadowRoot.querySelector('c-cloud-template-card');
        card.dispatchEvent(new CustomEvent('templateselected', {
            detail: { key: 'sales', selected: true }
        }));
        await flushPromises();

        validateApexClasses.mockResolvedValue({ AccountCrudScenario: true });

        const nextBtn = el.shadowRoot.querySelector('[data-id="next-btn"]');
        nextBtn.click();
        await flushPromises();
    }

    it('shows step 2 after clicking Next with selection', async () => {
        const el = createComponent();
        await advanceToStep2(el);
        const step2 = el.shadowRoot.querySelector('[data-step="2"]');
        expect(step2).not.toBeNull();
    });

    it('hides step 1 when on step 2', async () => {
        const el = createComponent();
        await advanceToStep2(el);
        const step1 = el.shadowRoot.querySelector('[data-step="1"]');
        expect(step1).toBeNull();
    });

    it('renders scenario preview table on step 2', async () => {
        const el = createComponent();
        await advanceToStep2(el);
        const table = el.shadowRoot.querySelector('c-scenario-preview-table');
        expect(table).not.toBeNull();
    });

    it('preview table receives correct scenario count', async () => {
        const el = createComponent();
        await advanceToStep2(el);
        const table = el.shadowRoot.querySelector('c-scenario-preview-table');
        expect(table.scenarios.length).toBe(4);
    });

    it('Back button returns to step 1', async () => {
        const el = createComponent();
        await advanceToStep2(el);

        const backBtn = el.shadowRoot.querySelector('[data-id="back-btn"]');
        expect(backBtn).not.toBeNull();
        backBtn.click();
        await flushPromises();

        const step1 = el.shadowRoot.querySelector('[data-step="1"]');
        expect(step1).not.toBeNull();
    });

    it('Deploy button is present on step 2', async () => {
        const el = createComponent();
        await advanceToStep2(el);
        const deployBtn = el.shadowRoot.querySelector('[data-id="deploy-btn"]');
        expect(deployBtn).not.toBeNull();
    });
});

// =============================================================================
// Step 3: deploy
// =============================================================================

describe('Step 3 — deployment', () => {
    async function advanceToStep3(el, deployOutcome) {
        getSalesAdapter.emit(mockSalesTemplates);
        getServiceAdapter.emit([]);
        getExperienceAdapter.emit([]);
        await flushPromises();

        const card = el.shadowRoot.querySelector('c-cloud-template-card');
        card.dispatchEvent(new CustomEvent('templateselected', {
            detail: { key: 'sales', selected: true }
        }));
        await flushPromises();

        validateApexClasses.mockResolvedValue({ AccountCrudScenario: true });

        const nextBtn = el.shadowRoot.querySelector('[data-id="next-btn"]');
        nextBtn.click();
        await flushPromises();

        bulkDeployTemplates.mockResolvedValue(deployOutcome);

        const deployBtn = el.shadowRoot.querySelector('[data-id="deploy-btn"]');
        deployBtn.click();
        await flushPromises();
    }

    it('shows step 3 after successful deploy', async () => {
        const el = createComponent();
        await advanceToStep3(el, mockDeployResult);
        const step3 = el.shadowRoot.querySelector('[data-step="3"]');
        expect(step3).not.toBeNull();
    });

    it('calls bulkDeployTemplates with scenarios on deploy click', async () => {
        const el = createComponent();
        await advanceToStep3(el, mockDeployResult);
        expect(bulkDeployTemplates).toHaveBeenCalledTimes(1);
    });

    it('shows success message with scenario count on success', async () => {
        const el = createComponent();
        await advanceToStep3(el, mockDeployResult);
        const successMsg = el.shadowRoot.querySelector('.deploy-success-message');
        expect(successMsg).not.toBeNull();
        expect(successMsg.textContent).toContain('4');
    });

    it('Done button is present after deploy', async () => {
        const el = createComponent();
        await advanceToStep3(el, mockDeployResult);
        const doneBtn = el.shadowRoot.querySelector('[data-id="done-btn"]');
        expect(doneBtn).not.toBeNull();
    });

    it('dispatches wizardcomplete event on Done click', async () => {
        const el = createComponent();
        const completeFn = jest.fn();
        el.addEventListener('wizardcomplete', completeFn);
        await advanceToStep3(el, mockDeployResult);

        const doneBtn = el.shadowRoot.querySelector('[data-id="done-btn"]');
        doneBtn.click();
        await flushPromises();

        expect(completeFn).toHaveBeenCalled();
    });

    it('shows error state on deployment failure', async () => {
        const el = createComponent();
        await advanceToStep3(el, {
            success: false,
            deployedCount: 0,
            errorMessage: 'Metadata API unavailable',
            skippedNames: [],
            warningClassNames: []
        });
        const step3 = el.shadowRoot.querySelector('[data-step="3"]');
        expect(step3).not.toBeNull();
        // No success icon
        const successIcon = el.shadowRoot.querySelector('.slds-illustration');
        expect(successIcon).toBeNull();
    });

    it('Retry button shown on failure', async () => {
        const el = createComponent();
        await advanceToStep3(el, {
            success: false,
            deployedCount: 0,
            errorMessage: 'Error',
            skippedNames: [],
            warningClassNames: []
        });
        const retryBtn = el.shadowRoot.querySelector('[data-id="retry-btn"]');
        expect(retryBtn).not.toBeNull();
    });
});

// =============================================================================
// De-duplication
// =============================================================================

describe('de-duplication', () => {
    it('de-duplicates overlapping scenarios from multiple templates', async () => {
        const el = createComponent();
        // Sales and Service both include Flow_Execution in this mock
        const sharedTemplate = [
            {
                scenarioName: 'Flow_Execution', label: 'Flow Execution',
                apexClassName: 'FlowExecutionScenario', executionOrder: 60,
                timeout: 45, cpuBudget: 5000, soqlBudget: 50, dmlBudget: 20,
                cloudType: 'Service', critical: false, description: 'Shared'
            }
        ];
        getSalesAdapter.emit([...mockSalesTemplates, ...sharedTemplate]);
        getServiceAdapter.emit([...sharedTemplate]);
        getExperienceAdapter.emit([]);
        await flushPromises();

        // Select both Sales and Service
        const cards = el.shadowRoot.querySelectorAll('c-cloud-template-card');
        cards[0].dispatchEvent(new CustomEvent('templateselected',
            { detail: { key: 'sales', selected: true } }));
        cards[1].dispatchEvent(new CustomEvent('templateselected',
            { detail: { key: 'service', selected: true } }));
        await flushPromises();

        validateApexClasses.mockResolvedValue({});

        const nextBtn = el.shadowRoot.querySelector('[data-id="next-btn"]');
        nextBtn.click();
        await flushPromises();

        const table = el.shadowRoot.querySelector('c-scenario-preview-table');
        // Flow_Execution should appear only once (5 Sales + 1 Service, shared = 5 unique)
        const uniqueNames = new Set(table.scenarios.map(s => s.scenarioName));
        expect(uniqueNames.size).toBe(table.scenarios.length);
    });
});
